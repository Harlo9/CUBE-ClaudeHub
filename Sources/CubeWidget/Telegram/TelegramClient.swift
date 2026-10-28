import Foundation

/// Talks to Telegram's Bot API (https://core.telegram.org/bots/api): plain HTTPS requests
/// to `api.telegram.org/bot<token>/<method>`. The token is never printed or logged.
enum TelegramClient {
    /// The bot's own account, used to check a token and to show its @name.
    struct Bot { let username: String }
    /// The conversation between you and the bot (where messages are sent).
    struct Chat { let id: Int64; let name: String }

    /// Checks the token and returns the bot's name.
    static func bot(token: String) async throws -> Bot {
        let result = try await call("getMe", token: token, parameters: [:])
        guard let username = result["username"] as? String else { throw TelegramError.unexpected }
        return Bot(username: username)
    }

    /// The last private conversation in which someone wrote to the bot (you, after
    /// sending it a message), or nil if nobody did yet.
    static func latestChat(token: String) async throws -> Chat? {
        let result = try await call("getUpdates", token: token, parameters: [:])
        guard let updates = result as? [[String: Any]] else { throw TelegramError.unexpected }
        for update in updates.reversed() {
            guard let message = update["message"] as? [String: Any],
                  let chat = message["chat"] as? [String: Any],
                  chat["type"] as? String == "private",
                  let id = (chat["id"] as? NSNumber)?.int64Value else { continue }
            let name = chat["first_name"] as? String ?? chat["username"] as? String ?? "toi"
            return Chat(id: id, name: name)
        }
        return nil
    }

    /// With `isHTML`, the text may use Telegram's HTML tags (`<b>bold</b>`…). With
    /// `replyTo`, the message is shown as an answer to that message. Returns the new
    /// message's number (to recognize your replies to it).
    @discardableResult
    static func send(_ text: String, to chatID: Int64, token: String, isHTML: Bool = false,
                     replyTo: Int? = nil, askReply placeholder: String? = nil,
                     buttons: [[Button]]? = nil) async throws -> Int? {
        var parameters: [String: Any] = ["chat_id": chatID, "text": text]
        if isHTML { parameters["parse_mode"] = "HTML" }
        // Telegram opens the keyboard to answer this message, with a hint in the text field.
        if let placeholder { parameters["reply_markup"] = ["force_reply": true, "input_field_placeholder": placeholder] }
        // Buttons under the message; a tap comes back as a `ButtonPress` with their `data`.
        if let buttons {
            parameters["reply_markup"] = ["inline_keyboard": buttons.map { $0.map { ["text": $0.text, "callback_data": $0.data] } }]
        }
        if let replyTo { parameters["reply_parameters"] = ["message_id": replyTo, "allow_sending_without_reply": true] }
        let result = try await call("sendMessage", token: token, parameters: parameters)
        return ((result as? [String: Any])?["message_id"] as? NSNumber)?.intValue
    }

    /// Removes a message from the conversation (the bot may remove yours in a private chat).
    static func deleteMessage(_ messageID: Int, in chatID: Int64, token: String) async throws {
        _ = try await call("deleteMessage", token: token, parameters: ["chat_id": chatID, "message_id": messageID])
    }

    /// A button under a message (`data`: up to 64 bytes, sent back when it is tapped).
    struct Button {
        let text: String
        let data: String
    }

    /// Answers a tap on a button: stops its spinner, and shows `text` for a moment on the phone.
    static func answerButton(_ id: String, text: String, token: String) async throws {
        _ = try await call("answerCallbackQuery", token: token, parameters: ["callback_query_id": id, "text": text])
    }

    /// Removes the buttons under one of the bot's messages (the text stays).
    static func removeButtons(of messageID: Int, in chatID: Int64, token: String) async throws {
        _ = try await call("editMessageReplyMarkup", token: token, parameters: [
            "chat_id": chatID, "message_id": messageID, "reply_markup": ["inline_keyboard": [[String: String]]()],
        ])
    }

    /// The bot's commands, proposed by Telegram when you type "/" (and in its Menu button).
    static func setCommands(_ commands: [(name: String, description: String)], token: String) async throws {
        _ = try await call("setMyCommands", token: token, parameters: [
            "commands": commands.map { ["command": $0.name, "description": $0.description] },
        ])
    }

    static func deleteCommands(token: String) async throws {
        _ = try await call("deleteMyCommands", token: token, parameters: [:])
    }

    /// A message you wrote to the bot.
    struct Incoming {
        let updateID: Int
        let messageID: Int
        let chatID: Int64
        let isPrivate: Bool
        let date: Date
        let text: String?
        /// The bot's message you replied to, if any.
        let replyTo: Int?
        /// A tap on one of the bot's buttons (then `messageID` is the bot's message, and
        /// there is no text).
        var button: ButtonPress? = nil
    }

    struct ButtonPress {
        /// To answer the tap (`answerButton`).
        let id: String
        let data: String
        /// Who tapped (in a private conversation, the same number as the conversation).
        let fromID: Int64
    }

    /// The messages received after `offset` (each update has a number; asking from a
    /// number tells Telegram the earlier ones were read). Telegram keeps the request open
    /// up to `wait` seconds until something arrives ("long polling"): nothing listens
    /// on the Mac, the app only asks.
    static func updates(token: String, offset: Int?, wait: Int) async throws -> [Incoming] {
        var parameters: [String: Any] = ["timeout": wait, "allowed_updates": ["message", "callback_query"]]
        if let offset { parameters["offset"] = offset }
        let result = try await call("getUpdates", token: token, parameters: parameters,
                                    timeout: TimeInterval(wait) + Constants.Telegram.requestTimeout)
        guard let updates = result as? [[String: Any]] else { throw TelegramError.unexpected }
        return updates.compactMap { update in
            guard let updateID = (update["update_id"] as? NSNumber)?.intValue else { return nil }
            if let query = update["callback_query"] as? [String: Any] {
                let message = query["message"] as? [String: Any] ?? [:]
                let chat = message["chat"] as? [String: Any] ?? [:]
                let from = query["from"] as? [String: Any] ?? [:]
                return Incoming(updateID: updateID,
                                messageID: (message["message_id"] as? NSNumber)?.intValue ?? 0,
                                chatID: (chat["id"] as? NSNumber)?.int64Value ?? 0,
                                isPrivate: chat["type"] as? String == "private",
                                date: Date(),
                                text: nil, replyTo: nil,
                                button: ButtonPress(id: query["id"] as? String ?? "",
                                                    data: query["data"] as? String ?? "",
                                                    fromID: (from["id"] as? NSNumber)?.int64Value ?? 0))
            }
            let message = update["message"] as? [String: Any] ?? [:]
            let chat = message["chat"] as? [String: Any] ?? [:]
            let reply = message["reply_to_message"] as? [String: Any]
            return Incoming(updateID: updateID,
                            messageID: (message["message_id"] as? NSNumber)?.intValue ?? 0,
                            chatID: (chat["id"] as? NSNumber)?.int64Value ?? 0,
                            isPrivate: chat["type"] as? String == "private",
                            date: Date(timeIntervalSince1970: (message["date"] as? NSNumber)?.doubleValue ?? 0),
                            text: message["text"] as? String,
                            replyTo: (reply?["message_id"] as? NSNumber)?.intValue)
        }
    }

    /// Text shown as is inside an HTML message (`<`, `>` and `&` would be read as tags).
    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// One request. Telegram answers `{"ok": true, "result": …}` or
    /// `{"ok": false, "error_code": 401, "description": "…"}`.
    private static func call(_ method: String, token: String, parameters: [String: Any],
                             timeout: TimeInterval = Constants.Telegram.requestTimeout) async throws -> AnyObject {
        guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == ":" || $0 == "_" || $0 == "-" }),
              let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw TelegramError.badToken
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TelegramError.offline
        }
        guard let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TelegramError.unexpected
        }
        if answer["ok"] as? Bool == true, let result = answer["result"] {
            return result as AnyObject
        }
        switch answer["error_code"] as? Int {
        case 401, 404: throw TelegramError.badToken
        case 400, 403: throw TelegramError.chatUnreachable
        default: throw TelegramError.server(answer["description"] as? String ?? "erreur inconnue")
        }
    }
}

/// What can go wrong, in words shown in the menu and the setup window.
enum TelegramError: LocalizedError {
    case offline, badToken, chatUnreachable, unexpected, server(String)

    var errorDescription: String? {
        switch self {
        case .offline: "pas de connexion à Telegram"
        case .badToken: "token du bot refusé"
        case .chatUnreachable: "conversation introuvable (envoie un message au bot)"
        case .unexpected: "réponse inattendue de Telegram"
        case .server(let description): "Telegram : \(description)"
        }
    }
}
