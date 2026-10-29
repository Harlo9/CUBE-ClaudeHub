// cube-hook: run by the Claude Code hooks (configured in ~/.claude/settings.json).
//
// Claude Code starts it at each event and sends the event as JSON on stdin. It updates
// ~/.cube-widget/sessions/<session_id>.json, which the app watches.
//
// It must never disturb Claude Code: it prints nothing (some events add stdout to
// Claude's context), always exits with code 0 (2 would block Claude), and ignores
// anything it does not understand.

import Darwin
import Foundation
import SessionFile

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      let sessionID = event["session_id"] as? String,
      // Only letters, digits and dashes: the ID becomes a file name.
      !sessionID.isEmpty, sessionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
else { exit(0) }

let eventName = event["hook_event_name"] as? String ?? ""
let fileURL = SessionFiles.url(forSession: sessionID)
let fileManager = FileManager.default
try? fileManager.createDirectory(at: SessionFiles.sessionsDirectory, withIntermediateDirectories: true)

// Several hooks can run at the same time (tools used in parallel): one at a time
// reads and writes the files. The lock is released when the process exits.
let lockFD = open(SessionFiles.baseDirectory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o644)
if lockFD >= 0 { flock(lockFD, LOCK_EX) }

if eventName == "SessionEnd" {
    try? fileManager.removeItem(at: fileURL)
    exit(0)
}

let now = Date()
let existing = (try? Data(contentsOf: fileURL)).flatMap { try? SessionFiles.decoder().decode(SessionFile.self, from: $0) }
let transcriptPath = event["transcript_path"] as? String
var session = existing ?? SessionFile(
    sessionID: sessionID,
    cwd: event["cwd"] as? String ?? "",
    transcriptPath: transcriptPath,
    // A new session waits for your first message: nothing urgent.
    status: .done,
    // Hooks installed while the session was already running: the conversation file
    // was created when it started.
    startedAt: eventName == "SessionStart" ? now : creationDate(of: transcriptPath) ?? now,
    now: now
)

// MARK: - Status

/// Tools that wait for you: a question to answer, a plan to approve.
let toolsWaitingForYou = ["AskUserQuestion", "ExitPlanMode"]

switch eventName {
case "PreToolUse" where toolsWaitingForYou.contains(event["tool_name"] as? String ?? ""):
    setStatus(.waiting)
case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure":
    setStatus(.working)
case "Stop":
    // End of Claude's answer. Its beginning is kept, enough to summarize it on Telegram
    // (not all of it: an answer can be very long).
    setStatus(.done)
    let message = (event["last_assistant_message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    session.lastAnswer = .init(excerpt: String(message.prefix(4000)), at: now)
case "StopFailure", "PermissionRequest":
    setStatus(.waiting)
case "Notification":
    // `idle_prompt` (a minute after the end of an answer) changes nothing: still "done".
    let waitingTypes = ["permission_prompt", "elicitation_dialog"]
    if let type = event["notification_type"] as? String, waitingTypes.contains(type) {
        setStatus(.waiting)
    }
default:
    break
}
if eventName == "UserPromptSubmit" { session.lastPromptAt = now }

// MARK: - Tasks

let toolInput = event["tool_input"] as? [String: Any] ?? [:]
let toolResponse = event["tool_response"] as? [String: Any] ?? [:]

switch eventName {
case "TaskCreated":
    if let id = string(event["task_id"]) {
        upsertTask(id: id, subject: event["task_subject"] as? String, status: nil)
    }
case "TaskCompleted":
    if let id = string(event["task_id"]) {
        completeTask(id: id, subject: event["task_subject"] as? String)
    }
case "PostToolUse":
    switch event["tool_name"] as? String {
    case "TaskCreate":
        let task = toolResponse["task"] as? [String: Any]
        if let id = string(task?["id"]) {
            upsertTask(id: id, subject: toolInput["subject"] as? String ?? task?["subject"] as? String, status: nil)
        }
    case "TaskUpdate":
        guard let id = string(toolInput["taskId"]) else { break }
        let statusChange = toolResponse["statusChange"] as? [String: Any]
        let status = statusChange?["to"] as? String ?? toolInput["status"] as? String
        if status == "deleted" {
            session.tasks.removeAll { $0.id == id }
        } else if status == "completed" {
            completeTask(id: id, subject: toolInput["subject"] as? String)
        } else {
            upsertTask(id: id, subject: toolInput["subject"] as? String, status: status)
        }
    default:
        break
    }
default:
    break
}

// MARK: - Permission asked

let toolName = event["tool_name"] as? String ?? "?"

switch eventName {
case "PermissionRequest" where toolName == "AskUserQuestion":
    // A question also comes as a permission request: it is kept as a question (below),
    // never answered with Oui / Non.
    break
case "PermissionRequest":
    // Kept for the Oui / Non buttons on Telegram, until the session moves on.
    session.pendingPermission = .init(tool: toolName,
                                      detail: permissionDetail(toolInput),
                                      description: (toolInput["description"] as? String).map { String($0.prefix(300)) },
                                      at: now)
case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "SessionStart":
    session.pendingPermission = nil
default:
    break
}

// MARK: - Question asked

switch eventName {
case "PreToolUse" where toolName == "AskUserQuestion":
    // Kept for the choice buttons on Telegram, until the session moves on.
    session.pendingQuestion = questions(toolInput).map { .init(items: $0, at: now) }
case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "SessionStart":
    session.pendingQuestion = nil
default:
    break
}

// MARK: - Process

if let transcriptPath { session.transcriptPath = transcriptPath }
if session.pid == nil || session.tty == nil, let claude = findClaudeProcess() {
    session.pid = claude.pid
    session.tty = claude.tty
}
session.updatedAt = now

// Written to a temporary file, then renamed: the app never reads a half-written file.
if let data = try? SessionFiles.encoder().encode(session) {
    try? data.write(to: fileURL, options: .atomic)
}

// MARK: - Helpers

func setStatus(_ status: SessionFile.Status) {
    guard session.status != status else { return }
    session.status = status
    session.statusChangedAt = now
}

/// Adds a task, or updates the one with this ID.
func upsertTask(id: String, subject: String?, status: String?) {
    if let index = session.tasks.firstIndex(where: { $0.id == id }) {
        if let subject { session.tasks[index].subject = subject }
        if let status { session.tasks[index].status = status }
    } else {
        session.tasks.append(.init(id: id, subject: subject ?? "", status: status ?? "pending"))
    }
}

/// Marks a task as completed. `TaskCompleted` and the `TaskUpdate` that follows both
/// report it: only the first one counts as "just completed".
func completeTask(id: String, subject: String?) {
    let wasCompleted = session.tasks.first { $0.id == id }?.status == "completed"
    upsertTask(id: id, subject: subject, status: "completed")
    guard !wasCompleted, let task = session.tasks.first(where: { $0.id == id }) else { return }
    session.lastCompletedTask = .init(id: id, subject: task.subject, at: now)
}

/// Task IDs come as strings ("1"), but accept numbers too.
/// What a tool would do, in a few words: its command, file, address or pattern, or
/// else its whole input (cut after 500 characters).
func permissionDetail(_ input: [String: Any]) -> String {
    for key in ["command", "file_path", "notebook_path", "url", "pattern", "path"] {
        if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(500)) }
    }
    let data = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])) ?? Data()
    return String((String(data: data, encoding: .utf8) ?? "").prefix(500))
}

/// The questions of `AskUserQuestion` (`questions`: `question`, `header`, `options` with
/// their `label`, `multiSelect`). Nil if there is none.
func questions(_ input: [String: Any]) -> [SessionFile.Question.Item]? {
    let items = (input["questions"] as? [[String: Any]] ?? []).compactMap { item -> SessionFile.Question.Item? in
        guard let question = item["question"] as? String else { return nil }
        let options = (item["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
        return .init(question: String(question.prefix(500)), header: item["header"] as? String,
                     options: options.map { String($0.prefix(200)) },
                     multiSelect: item["multiSelect"] as? Bool ?? false)
    }
    return items.isEmpty ? nil : items
}

func string(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

func creationDate(of path: String?) -> Date? {
    guard let path else { return nil }
    return (try? fileManager.attributesOfItem(atPath: path))?[.creationDate] as? Date
}

/// The Claude Code process: the first parent whose executable is Claude's
/// (`…/claude/versions/2.1.x` or `…/claude`). Its kernel name is its version number,
/// so the executable path is checked, not the name. Nil if not found: a wrong PID
/// (e.g. a shell that exits right away) would make the app think the session ended.
func findClaudeProcess() -> (pid: Int32, tty: String?)? {
    var pid = getppid()
    for _ in 0..<6 {
        guard pid > 1, let info = processInfo(pid) else { break }
        let path = executablePath(pid) ?? ""
        if path.contains("/claude/versions/") || (path as NSString).lastPathComponent == "claude" {
            return (pid, info.tty)
        }
        pid = info.parent
    }
    return nil
}

func processInfo(_ pid: Int32) -> (parent: Int32, tty: String?)? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let device = info.kp_eproc.e_tdev
    var tty: String?
    if device != -1, let name = devname(device, S_IFCHR) {
        tty = "/dev/" + String(cString: name)
    }
    return (info.kp_eproc.e_ppid, tty)
}

func executablePath(_ pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
}
