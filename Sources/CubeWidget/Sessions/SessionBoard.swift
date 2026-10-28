import SessionFile
import SwiftUI

/// A task that was just completed in a session, shown for a few seconds.
struct Celebration: Equatable {
    let id = UUID()
    let sessionID: Session.ID
    /// Empty when Claude simply finished its answer (shown as "✓ Terminé").
    let taskTitle: String
}

/// The sessions shown by the widget, in display order: the first one is the active
/// project (front card), the next ones are the cards below.
@MainActor
final class SessionBoard: ObservableObject {
    @Published private(set) var sessions: [Session] {
        didSet {
            guard !soundsMuted else { return }
            celebrateFinishedAnswer(previous: oldValue)
            playWaitingSound(previous: oldValue)
            playWorkingSound(previous: oldValue)
        }
    }
    @Published private(set) var celebration: Celebration?
    /// Number of jumps of each card below; a card jumps when its number changes.
    @Published private(set) var cardJumps: [Session.ID: Int] = [:]
    private var celebrationEnd: Task<Void, Never>?
    /// Receives the sounds of the active project, which go with a cube animation
    /// (the cube plays them when the animation starts). Without it they play right away.
    var cueActiveSound: ((SoundPlayer.Sound) -> Void)?

    /// Fake sessions chosen in the Debug menu are shown instead of the real ones.
    private(set) var isDemo: Bool
    /// The last real sessions received, kept while the demo is shown.
    private var realSessions: [SessionStore.Snapshot] = []
    /// When each session's last completed task was seen, to start the green state once.
    private var seenCompletions: [Session.ID: Date] = [:]
    private var hasLoadedRealSessions = false
    private var soundsMuted = false

    /// - Parameter demo: start with fake sessions (used by `--snapshot`).
    init(demo: Bool = false) {
        isDemo = demo
        sessions = demo ? Array(Session.previews.prefix(3)) : []
    }

    var active: Session? { sessions.first }

    /// The session running in this terminal device, if any.
    func session(onTTY tty: String?) -> Session? {
        guard let tty else { return nil }
        return sessions.first { $0.tty == tty }
    }

    /// Other projects that get a card below the front card.
    var visibleOthers: [Session] {
        Array(sessions.dropFirst().prefix(Constants.BackCard.maxCount))
    }

    /// Task completed in the active session, if any. Waiting for your answer has priority:
    /// while the active session waits, there is no celebration.
    var activeCelebration: Celebration? {
        guard let active, active.status != .waiting,
              let celebration, celebration.sessionID == active.id else { return nil }
        return celebration
    }

    /// What the cube should show for the active project.
    var cubeMood: CubeAnimator.Mood {
        guard let active else { return .sleeping }
        if active.status == .waiting { return .waiting }
        if activeCelebration != nil { return .celebrating }
        return active.status == .done ? .done : .working
    }

    /// Starts the "task completed" state for a session. It ends by itself after
    /// `Constants.Cube.celebrationDuration` seconds (a new completed task restarts the timer).
    func taskCompleted(sessionID: Session.ID, title: String) {
        let newCelebration = Celebration(sessionID: sessionID, taskTitle: title)
        celebration = newCelebration
        // Only when the green state really shows (active project, not waiting).
        if activeCelebration?.id == newCelebration.id { playActiveSound(.taskCompleted) }
        celebrationEnd?.cancel()
        celebrationEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Cube.celebrationDuration))
            guard !Task.isCancelled, let self, self.celebration?.id == newCelebration.id else { return }
            withAnimation(.easeInOut(duration: Constants.Cube.colorFadeDuration)) {
                self.celebration = nil
            }
        }
    }

    // MARK: - Real sessions

    /// Shows the sessions read from the hook files.
    ///
    /// The active session (front card) stays the same until you click another card or it
    /// ends; then the next card comes to the front. Below it: first the sessions waiting
    /// for your answer, then the others, the most recent change first.
    func applyRealSessions(_ snapshots: [SessionStore.Snapshot]) {
        realSessions = snapshots
        guard !isDemo else { return }
        let isFirstLoad = !hasLoadedRealSessions
        hasLoadedRealSessions = true

        let all = snapshots.map(Self.session(from:))
        let ids = Set(all.map(\.id))
        var activeID = sessions.first?.id
        if let id = activeID, !ids.contains(id) {
            // The active session ended: the next card that still exists comes to the front.
            activeID = sessions.dropFirst().first { ids.contains($0.id) }?.id
        }
        if activeID == nil {
            // No active session yet: the one with the latest activity.
            activeID = snapshots.max { $0.file.updatedAt < $1.file.updatedAt }?.file.sessionID
        }
        let others = all.filter { $0.id != activeID }.sorted(by: Self.isBefore)
        let ordered = all.filter { $0.id == activeID } + others

        if ordered != sessions {
            // At launch, sessions that were already there make no sound.
            soundsMuted = isFirstLoad
            withAnimation(.smooth(duration: Constants.BackCard.swapAnimationDuration)) {
                sessions = ordered
            }
            soundsMuted = false
        }

        // A task just completed in the active session: green state.
        for snapshot in snapshots {
            guard let done = snapshot.file.lastCompletedTask else { continue }
            let id = snapshot.file.sessionID
            let isNew = seenCompletions[id] != done.at
            seenCompletions[id] = done.at
            if isNew, !isFirstLoad, id == active?.id,
               Date().timeIntervalSince(done.at) < Constants.Cube.celebrationDuration {
                taskCompleted(sessionID: id, title: done.subject)
            }
        }
    }

    private static func session(from snapshot: SessionStore.Snapshot) -> Session {
        let file = snapshot.file
        // The task in progress; if none, the last one created.
        let task = file.tasks.last { $0.status == "in_progress" } ?? file.tasks.last
        return Session(
            id: file.sessionID,
            projectName: URL(fileURLWithPath: file.cwd).lastPathComponent,
            status: {
                switch file.status {
                case .working: .working
                case .waiting: .waiting
                case .done: .done
                }
            }(),
            startedAt: file.startedAt,
            contextTokens: snapshot.contextTokens ?? 0,
            currentTask: task.flatMap { $0.subject.isEmpty ? nil : $0.subject },
            statusChangedAt: file.statusChangedAt,
            tty: file.tty,
            folder: URL(fileURLWithPath: file.cwd),
            pid: file.pid
        )
    }

    /// Order of the cards below: first the sessions waiting for your answer, then the
    /// others, the most recent status change first.
    private static func isBefore(_ a: Session, _ b: Session) -> Bool {
        if (a.status == .waiting) != (b.status == .waiting) { return a.status == .waiting }
        return a.statusChangedAt > b.statusChangedAt
    }

    /// Brings a session to the front. The cards below take their final order right away
    /// (the previous active session among them), so nothing moves again afterwards.
    func activate(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let chosen = sessions[index]
        let others = sessions.filter { $0.id != id }
        sessions = [chosen] + (isDemo ? others : others.sorted(by: Self.isBefore))
    }

    /// Plays the waiting sound once when a session (front card or below) starts waiting.
    /// A session that appears already waiting does not play it.
    private func playWaitingSound(previous: [Session]) {
        let wasWaiting = Dictionary(previous.map { ($0.id, $0.status == .waiting) }, uniquingKeysWith: { a, _ in a })
        let startedWaiting = sessions.filter { $0.status == .waiting && wasWaiting[$0.id] == false }
        guard let first = startedWaiting.first else { return }
        // The cube does not change for a card below: that card jumps instead.
        for session in startedWaiting where session.id != active?.id {
            cardJumps[session.id, default: 0] += 1
        }
        if first.id == active?.id {
            playActiveSound(.waiting)
        } else {
            SoundPlayer.play(.waiting)
        }
    }

    /// When the active project finishes its answer (bosse → terminé): "task completed"
    /// state, unless one is already showing (a task completed just before).
    private func celebrateFinishedAnswer(previous: [Session]) {
        guard let active, active.status == .done,
              let before = previous.first, before.id == active.id, before.status == .working,
              activeCelebration == nil else { return }
        taskCompleted(sessionID: active.id, title: "")
    }

    /// Plays the working sound when the active project starts working: it was waiting
    /// for you or had finished, or there was no session at all. Bringing a card to the
    /// front does not.
    private func playWorkingSound(previous: [Session]) {
        guard let active, active.status == .working else { return }
        let before = previous.first
        if before == nil || (before?.id == active.id && before?.status != .working) {
            playActiveSound(.working)
        }
    }

    private func playActiveSound(_ sound: SoundPlayer.Sound) {
        if let cueActiveSound {
            cueActiveSound(sound)
        } else {
            SoundPlayer.play(sound)
        }
    }

    // MARK: - Debug (demo sessions)

    private var debugBackCount = 2

    /// Goes back to the real sessions after a demo.
    func showRealSessions() {
        guard isDemo else { return }
        isDemo = false
        celebration = nil
        applyRealSessions(realSessions)
    }

    /// The Debug menu switches to fake sessions, so the real ones do not overwrite them.
    private func enterDemo() {
        guard !isDemo else { return }
        isDemo = true
        celebration = nil
        sessions = Array(Session.previews.prefix(1 + debugBackCount))
    }

    /// `nil` removes every session.
    func debugSetActiveStatus(_ status: SessionStatus?) {
        enterDemo()
        guard let status else {
            sessions = []
            return
        }
        if sessions.isEmpty {
            sessions = Array(Session.previews.prefix(1 + debugBackCount))
        }
        sessions[0].status = status
    }

    /// Completes the active session's task; a fake next task takes its place afterwards.
    /// The session is first set to "bosse" (a task ends while Claude works), otherwise
    /// waiting would have priority, or there would be no session at all.
    func debugCompleteTask() {
        debugSetActiveStatus(.working)
        guard let active else { return }
        taskCompleted(sessionID: active.id, title: active.currentTask ?? "Tâche de démo")
        sessions[0].currentTask = "Tâche suivante (démo)"
    }

    /// The first card below that is not waiting starts waiting (it jumps, with the sound).
    func debugBackCardStartsWaiting() {
        enterDemo()
        if sessions.count < 2 { debugSetBackCount(max(1, debugBackCount)) }
        guard sessions.count > 1 else { return }
        let index = sessions.indices.dropFirst().first { sessions[$0].status != .waiting } ?? sessions.count - 1
        sessions[index].status = .working
        sessions[index].status = .waiting
        // Waiting sessions come first below the active card.
        let moved = sessions.remove(at: index)
        sessions.insert(moved, at: 1)
    }

    /// Claude finishes its answer: green state, then the cube stays green.
    func debugFinishAnswer() {
        debugSetActiveStatus(.working)
        debugSetActiveStatus(.done)
    }

    func debugSetBackCount(_ count: Int) {
        enterDemo()
        debugBackCount = count
        guard let active else { return }
        sessions = [active] + Session.previews.filter { $0.id != active.id }.prefix(count)
    }
}
