@testable import CubeWidget
import Foundation
import SessionFile
import XCTest

/// The texts sent to Telegram, and the text typed into a session from Telegram.
@MainActor
final class TelegramTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Notifications

    func testNotificationText() {
        XCTAssertEqual(TelegramNotifier.text("Site", "Tâche finie ✅", "Écrire les tests"),
                       "<b>Site</b> - Tâche finie ✅\nÉcrire les tests")
        // Without a task, only the first line.
        XCTAssertEqual(TelegramNotifier.text("Site", "Attend ta réponse ⏳", nil), "<b>Site</b> - Attend ta réponse ⏳")
        XCTAssertEqual(TelegramNotifier.text("Site", "Attend ta réponse ⏳", "   "), "<b>Site</b> - Attend ta réponse ⏳")
    }

    /// A long task title is cut with "…", to the maximum length.
    func testLongTaskIsCut() {
        let limit = Constants.Telegram.taskTitleMaxLength
        let text = TelegramNotifier.text("Site", "Tâche finie ✅", String(repeating: "a", count: limit + 20))
        let task = String(text.split(separator: "\n")[1])
        XCTAssertEqual(task.count, limit)
        XCTAssertTrue(task.hasSuffix("…"))
    }

    /// Names and tasks are escaped: Telegram reads the message as HTML.
    func testHTMLIsEscaped() {
        XCTAssertEqual(TelegramNotifier.text("a<b>", "Fini", "x & y"), "<b>a&lt;b&gt;</b> - Fini\nx &amp; y")
    }

    // MARK: - Permissions and questions

    func testPermissionText() {
        let permission = SessionFile.Permission(tool: "Bash", detail: "touch notes.txt",
                                                description: "Créer le fichier", at: now)
        XCTAssertEqual(TelegramRemote.permissionText(permission),
                       "🔐 <b>Bash</b> : <code>touch notes.txt</code>\n<i>Créer le fichier</i>")
    }

    func testSingleQuestionText() {
        let question = SessionFile.Question(items: [.init(question: "Quelle couleur ?", header: "Couleur",
                                                          options: ["Violet", "Rose"], multiSelect: false)], at: now)
        XCTAssertEqual(TelegramRemote.questionText(question, index: 0), "❓ <b>Couleur</b> : Quelle couleur ?")
        XCTAssertEqual(TelegramRemote.choicesText(question.items[0]), "• Violet\n• Rose")
    }

    func testSeveralQuestionsAreNumbered() {
        let question = SessionFile.Question(items: [
            .init(question: "Saison ?", header: "Saison", options: ["Hiver", "Été"], multiSelect: false),
            .init(question: "Mer ou montagne ?", header: "Lieu", options: ["Mer", "Montagne"], multiSelect: false),
        ], at: now)
        XCTAssertEqual(TelegramRemote.questionText(question, index: 1), "❓ <b>Lieu</b> (2/2) : Mer ou montagne ?")
    }

    /// Several choices possible: answered on the Mac.
    func testMultiSelectSaysToAnswerOnTheMac() {
        let question = SessionFile.Question(items: [.init(question: "Lesquels ?", header: nil,
                                                          options: ["A", "B"], multiSelect: true)], at: now)
        XCTAssertTrue(TelegramRemote.questionText(question, index: 0).contains("réponds depuis le Mac"))
    }

    // MARK: - Text typed from Telegram

    /// Control characters (Échap, Ctrl-C…) could drive the terminal: they are removed.
    func testTypedTextIsCleaned() {
        XCTAssertEqual(TelegramRemote.cleaned("  Salut\u{1B}[A\u{03}  "), "Salut[A")
        XCTAssertEqual(TelegramRemote.cleaned("ligne 1\r\nligne 2\rligne 3"), "ligne 1\nligne 2\nligne 3")
    }
}
