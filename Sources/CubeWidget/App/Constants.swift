import SwiftUI

/// Every tunable value of the app (sizes, colors, durations) lives here.
/// Sizes are in points (1 pt = 2 px on a Retina screen).
enum Constants {

    // MARK: - Colors

    enum Colors {
        /// Card background: pure opaque black.
        static let cardBackground = Color(hex: 0x000000)
        /// Thin outline around every card.
        static let cardBorder = Color(hex: 0x3A3A3C)
        /// Main text (project name, task).
        static let primaryText = Color.white
        /// Secondary info (duration, tokens, separators).
        static let secondaryText = Color(hex: 0x8E8E93)
        /// "attend ta réponse".
        static let waiting = Color(hex: 0xE5671A)
        /// "bosse".
        static let working = Color(hex: 0x6EB4F5)
        /// Task completed (halo and "✓ task" line).
        static let completed = Color(hex: 0x3FBF6E)
        /// Project name on the small cards below.
        static let backCardName = Color(hex: 0xDDDDDD)
    }

    // MARK: - Front card (active project)

    enum FrontCard {
        static let width: CGFloat = 360
        static let height: CGFloat = 84
        static let cornerRadius: CGFloat = 18
        static let borderWidth: CGFloat = 1
        /// Height of the cube image (the image includes the cube's own glow).
        static let cubeHeight: CGFloat = 64
        /// Space between the card's left edge and the cube.
        static let cubeLeadingPadding: CGFloat = 12
        /// Space between the cube and the text block.
        static let cubeToTextSpacing: CGFloat = 12
        /// Space between the text block and the card's right edge.
        static let trailingPadding: CGFloat = 16
        /// Vertical space between the 3 text lines.
        static let lineSpacing: CGFloat = 3

        static let projectNameFontSize: CGFloat = 15
        static let taskFontSize: CGFloat = 12.5
        static let statusFontSize: CGFloat = 11.5

        /// Side of the square card when the widget is folded (cube only).
        static let collapsedSide: CGFloat = 84
        /// Duration of the fold / unfold animation, in seconds.
        /// Fold / unfold: a soft spring, about this long, in seconds.
        static let collapseAnimationDuration: Double = 0.4
    }

    // MARK: - Cards below (other projects)

    enum BackCard {
        /// Height of the visible band of each card below.
        static let visibleHeight: CGFloat = 24
        /// Height of the part tucked under the card above (must be more than the corner radius).
        static let hiddenHeight: CGFloat = 30
        /// Maximum number of cards below the front card.
        static let maxCount = 2
        static let horizontalPadding: CGFloat = 16
        static let dotSize: CGFloat = 7
        static let dotToNameSpacing: CGFloat = 8
        static let fontSize: CGFloat = 11.5
        /// Duration of the animation when a card below comes to the front, in seconds.
        static let swapAnimationDuration = 0.45
        /// Text of a card that changes shape: the leaving text fades out this fast, the
        /// arriving text fades in at the end of the move (after `contentFadeInDelay`).
        static let contentFadeOutDuration = 0.12
        static let contentFadeInDuration = 0.2
        static let contentFadeInDelay = 0.22
        /// When its project starts waiting, the card bounces down (its top is hidden under
        /// the card above, so a jump up would not show) and its dot swells.
        static let jumpDepth: CGFloat = 5
        static let jumpDuration = 0.45
        /// The dot grows to this size (1.8 = 180 %) during the jump.
        static let jumpDotScale = 1.8
    }

    // MARK: - Halo around the front card

    enum Halo {
        /// Duration of the fade from one halo to another, in seconds.
        static let fadeDuration = 0.4

        // "bosse": a blue light running around the card, clockwise.
        /// Duration of one full lap, in seconds.
        static let lapDuration = 2.6
        /// Length of the fading trail behind the light (0.25 = a quarter of the outline).
        static let trailFraction = 0.25
        /// The trail is drawn as this many pieces, more and more transparent behind the head.
        static let trailPieces = 48
        /// Opacity of the head of the light.
        static let workingMaxOpacity = 0.65
        static let workingLineWidth: CGFloat = 2
        /// Width and blur of the soft glow that spills slightly outside the card.
        static let workingGlowWidth: CGFloat = 5
        static let workingGlowBlur: CGFloat = 5

        // "attend ta réponse": a still orange outline.
        static let waitingOpacity = 0.45
        static let waitingLineWidth: CGFloat = 2
        static let waitingGlowWidth: CGFloat = 4
        static let waitingGlowBlur: CGFloat = 6

        // Task completed: a still green outline (same widths as the orange one).
        static let completedOpacity = 0.75

        // Entrance when the active project starts working (you answered, or a session
        // opened): a blue ring, larger than the card, closes in on it faster and faster;
        // when it hits the card, the whole outline lights up, then that light gathers
        // into the running light. The cube makes a small "pop" at the impact.
        /// Time for the ring to close in on the card (until the impact), in seconds.
        static let entranceDuration = 0.45
        /// Time for the lit outline to gather into the running light, in seconds.
        static let entranceGatherDuration = 0.8
        /// How far outside the card the ring starts, in points (must stay below Window.haloMargin).
        static let entranceInflate: CGFloat = 16
        /// Opacity of the ring and of the outline lit by the impact.
        static let entranceMaxOpacity = 0.95
        static let entranceLineWidth: CGFloat = 2
        static let entranceGlowBlur: CGFloat = 5
        /// The cube grows by this much at the impact, then comes back (0.06 = 6 %).
        static let entranceCubePop = 0.06
        static let entranceCubePopDuration = 0.35
    }

    // MARK: - Cube animations
    // Frame numbers are the numbers at the start of the file names (01 = 01_centre.png…).

    enum Cube {
        // "Claude bosse": Travail 01 → 21, in a loop.
        /// Default duration of a Travail frame, in milliseconds.
        static let workingFrameMs = 90
        /// Travail frames that last longer (centered pauses, looking to the side).
        static let workingLongFramesMs: [Int: Int] = [1: 1000, 11: 1000, 21: 1000, 4: 500, 14: 500]
        /// Travail frames that are part of a blink…
        static let workingBlinkFrames: Set<Int> = [7, 8, 9, 10, 17, 18, 19, 20]
        /// …and their duration, in milliseconds.
        static let blinkFrameMs = 60
        /// Travail frames where the cube is centered with its eyes open: the loop is only
        /// ever left on one of these, so a blink or a glance is never cut.
        static let workingExitFrames: Set<Int> = [1, 6, 11, 16, 21]

        // Falling asleep: Sommeil 01 → 10.
        static let fallAsleepFrameMs = 180
        static let fallAsleepLongFramesMs: [Int: Int] = [3: 250, 6: 250, 8: 250, 9: 250, 10: 400]

        // Breathing while asleep (on Sommeil 10), done in code.
        /// How much the cube grows at the top of a breath (0.03 = 3 %).
        static let breathAmplitude = 0.03
        /// Duration of one full breath (in + out), in seconds.
        static let breathPeriod = 3.0
        /// When waking up mid-breath, time to smoothly return to normal size, in seconds.
        static let breathReleaseDuration = 0.3

        // Waking up.
        /// Sommeil frames played backwards (03 "lutte" is skipped).
        static let wakeUpSleepFrames = [9, 8, 7, 6, 5, 4, 1]
        static let wakeUpFrameMs = 100
        /// Travail frames of the blink that ends the wake-up (after Travail 01), at `blinkFrameMs`.
        static let wakeUpBlinkFrames = [7, 9, 7, 1]

        // Jumping while waiting for your answer.
        /// Duration of one jump, in seconds (takeoff → landing → squash → back to normal).
        static let jumpDuration = 0.4
        /// Height of the first jumps, in points.
        static let jumpHeight: CGFloat = 8
        /// Height of the reminder jumps, in points.
        static let smallJumpHeight: CGFloat = 5
        /// Number of jumps in a row when a session starts waiting.
        static let initialJumpCount = 2
        /// Seconds between two reminder jumps while you have not answered.
        static let reminderJumpInterval = 4.0
        /// How much the cube is squashed on landing (0.12 = 12 % flatter).
        static let landingSquash = 0.12

        // Orange cube while waiting for your answer, computed from the blue frames:
        // each frame is turned to grayscale, then each gray is replaced by this gradient.
        /// Color of the darkest grays (eyes).
        static let orangeGradientDark: UInt32 = 0x2A1A10
        /// Color of the middle grays (glow).
        static let orangeGradientMid: UInt32 = 0xE5671A
        /// Color of the lightest grays (body of the cube).
        static let orangeGradientLight: UInt32 = 0xFFE2C8
        /// Duration of the blue ↔ orange / green fade, in seconds.
        static let colorFadeDuration = 0.3

        // Task completed: the cube turns green and its eyes follow the mouse.
        /// How long the "task completed" state lasts, in seconds.
        static let celebrationDuration = 3.0
        /// Height of the single jump when the task is completed, in points (0 = no jump).
        static let celebrationJumpHeight: CGFloat = 14
        /// Green gradient, same method as the orange one (dark → mid → light grays).
        static let greenGradientDark: UInt32 = 0x0E2416
        static let greenGradientMid: UInt32 = 0x3FBF6E
        static let greenGradientLight: UInt32 = 0xDDF7E6

        // The eyes are drawn in code on top of Assets/Regard/cube_sans_yeux.png, using
        // Assets/Regard/oeil.png twice. Positions are in pixels of the original images.
        /// Top-left corner of each eye at rest.
        static let leftEyeRest = CGPoint(x: 467, y: 490)
        static let rightEyeRest = CGPoint(x: 801, y: 489)
        /// Size of Assets/Regard/oeil.png.
        static let eyeSize = CGSize(width: 100, height: 258)
        /// Farthest the eyes can move from rest, in each direction (x and y).
        static let eyeMaxOffset: CGFloat = 60
        /// Distance between the mouse and the cube (in points) at which the eyes have gone
        /// about 3/4 of the way to the maximum. Farther, they keep getting closer to it.
        static let eyeFollowDistance: CGFloat = 300
        /// How softly the eyes catch up with the mouse: time in seconds to cover about 2/3
        /// of the remaining way (bigger = slower, smoother).
        static let eyeFollowSmoothing = 0.08
        /// Eye position updates per second.
        static let eyeUpdatesPerSecond = 60.0
        /// When Claude finished its answer, the eyes follow the mouse this long (in seconds,
        /// counting the "task completed" state), then come back to the center.
        static let doneEyeFollowDuration = 60.0
        /// Part of the original images kept by Scripts/make_frames.swift (must match it).
        static let sourceCrop = CGRect(x: 236, y: 160, width: 900, height: 870)
    }

    // MARK: - Cube Hub

    /// The window gathering the projects, each with its terminal running Claude.
    enum Hub {
        static let windowSize = CGSize(width: 1100, height: 700)
        static let sidebarWidth: CGFloat = 290
        /// Font size of the terminals, in points.
        static let fontSize: CGFloat = 13
        /// Margin between the terminal's text and the window edges.
        static let terminalPadding: CGFloat = 8

        // The list on the left: one small black card per session, with its ice cube.
        static let sidebarBackground = Color(hex: 0x0A0A0B)
        static let sidebarPadding: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let rowCornerRadius: CGFloat = 14
        static let rowCubeSize: CGFloat = 40
        static let rowNameFontSize: CGFloat = 13
        static let rowDetailFontSize: CGFloat = 11
        static let rowHoverBackground = Color(hex: 0x111113)
        static let rowSelectedBackground = Color(hex: 0x141417)
        /// Glow around the selected card, in the color of its state.
        static let selectedGlowOpacity = 0.45
        static let selectedGlowRadius: CGFloat = 7
        static let sectionTitleFontSize: CGFloat = 10.5

        /// Themes of the list ("Freelance", "Projet perso"…): the palette to choose from
        /// (names shown in the menu, same order), the dot before a theme's name, the space
        /// above a theme's title, and the speed of folding / moving. No blue, green or
        /// orange (nor close shades): those are the states' colors.
        static let themeColors: [Color] = [
            Color(hex: 0xA78BFA), Color(hex: 0xF472B6), Color(hex: 0xF5C542), Color(hex: 0xE879F9),
            Color(hex: 0xE11D48), Color(hex: 0xD6C7A1), Color(hex: 0x8E8E93),
        ]
        static let themeColorNames = ["Violet", "Rose", "Jaune", "Fuchsia", "Framboise", "Sable", "Gris"]
        static let themeDotSize: CGFloat = 7
        static let themeHeaderTopPadding: CGFloat = 8
        static let themeAnimationDuration = 0.22
        /// A theme's look: its title is a tab tinted with its color, on top of a panel
        /// (tinted too, with a thin outline) that holds its cards, like a binder divider.
        static let themeTabOpacity = 0.16
        static let themeTabCornerRadius: CGFloat = 8
        static let themeTabHorizontalPadding: CGFloat = 9
        static let themeTabVerticalPadding: CGFloat = 4
        static let themePanelOpacity = 0.06
        static let themeOutlineOpacity = 0.28
        static let themePanelCornerRadius: CGFloat = 18
        /// Space between the panel's sides and its cards, and below its last card.
        static let themePanelInset: CGFloat = 6
        static let themePanelBottomPadding: CGFloat = 8
        /// The "+ Thème" button at the bottom of the list.
        static let addThemeFontSize: CGFloat = 12
        /// The small "Terminal" tag of a session running in Terminal.
        static let terminalTagFontSize: CGFloat = 9
        /// The field where a theme's name is typed, in the list.
        static let themeFieldFontSize: CGFloat = 12
        static let themeFieldCornerRadius: CGFloat = 7
        /// The dashed "Nouvelle session" card at the bottom of the list.
        static let newSessionCardTopPadding: CGFloat = 6
        static let newSessionCardDash: [CGFloat] = [5, 4]
        static let newSessionCardDashWidth: CGFloat = 1.2
        /// Opacity of its text and dashes, when not under the mouse.
        static let newSessionCardOpacity = 0.55
        /// The dashed square with a "+" where the cube would be.
        static let newSessionCubeSize: CGFloat = 30
        static let newSessionCubeCornerRadius: CGFloat = 8
        /// Cards making room while one is dragged to change the order.
        static let reorderAnimationDuration = 0.22
        /// The dragged card settling into its new place, once released.
        static let settleDuration = 0.25
        /// Distance the mouse must move before a card starts being dragged (a click
        /// below that still selects the card).
        static let dragStartDistance: CGFloat = 4
        /// The dragged card is slightly bigger, with a shadow, to look lifted.
        static let dragScale: CGFloat = 1.03
        static let dragShadowOpacity = 0.6
        static let dragShadowRadius: CGFloat = 10
        /// Title of the theme a card would be dropped in (from another theme): lit in its
        /// color, on a faint background of that color.
        static let dropTargetOpacity = 0.14
        static let dropTargetVerticalPadding: CGFloat = 3
        /// Place number shown, very discreet, to the left of each card.
        static let positionFontSize: CGFloat = 10
        static let positionOpacity = 0.45
        static let positionWidth: CGFloat = 14
        static let positionToCardSpacing: CGFloat = 6

        // The band above the terminal: the selected session's cube and details.
        static let headerCubeSize: CGFloat = 50
        static let headerNameFontSize: CGFloat = 16
        static let headerDetailFontSize: CGFloat = 12
        /// The ">_" icon at the right of the band: opens a Terminal window in the project's
        /// folder. Gray, lit on hover (like the bells).
        static let openTerminalIconSize: CGFloat = 18
        static let openTerminalIconColor = Color(hex: 0x6E6E73)
        static let openTerminalIconHoverColor = Color.white
        /// Space between that Terminal window and the Hub window (0 = right against it).
        /// The window keeps Terminal's usual size (80 x 24 by default, set in Terminal's
        /// settings → Profiles → Window).
        static let openTerminalGap: CGFloat = 0

        // The big cube of a session running in Terminal, and of the empty page.
        static let bigCubeSize: CGFloat = 130

        // The cubes' animation (simpler than the widget's, there can be many of them).
        /// Redraws per second during the "waiting" jump (otherwise a cube is only redrawn
        /// when its image changes).
        static let cubeFramesPerSecond = 20.0
        /// Soft light behind the cube, in the color of its state.
        static let cubeGlowOpacity = 0.32
        /// Height of the "waiting" jump, as a fraction of the cube's size.
        static let cubeJumpFraction: CGFloat = 0.14
        /// Opacity of a sleeping cube (closed terminal, no session).
        static let asleepOpacity = 0.55
    }

    // MARK: - Menu bar icon

    enum MenuBar {
        /// Height of the mini cube in the menu bar, in points.
        static let iconHeight: CGFloat = 18
        /// Mini jump while waiting for your answer, in points.
        static let jumpHeight: CGFloat = 2.5
        /// Icon redraws per second while the cube moves.
        static let framesPerSecond = 20.0
        /// Image of `Sommeil` shown when there is no session (10: asleep).
        static let sleepFrame = 10
    }

    // MARK: - Telegram

    enum Telegram {
        /// While waiting for your first message to the bot: how often Telegram is asked, in seconds.
        static let chatPollInterval = 3.0
        /// A request to Telegram gives up after this many seconds (no internet…).
        static let requestTimeout = 10.0
        /// Messages are sent only when you have not touched the mouse or keyboard for this
        /// long, in seconds (unless "Toujours envoyer" is checked).
        static let awayDelay = 180.0
        /// In a message, a longer task title is cut with "…" (number of characters).
        static let taskTitleMaxLength = 60
        /// "Réponse terminée": the beginning of Claude's answer, cut with "…" (characters).
        static let answerExcerptMaxLength = 100
        /// "Réponse terminée": the answer summarized in a few very short bullet points by a
        /// small Claude model (uses a little of the subscription, only when a message is
        /// sent). If it fails or takes longer than `summaryTimeout` seconds, the answer's
        /// first sentence is sent instead. A one-sentence answer is sent as is.
        static let summaryModel = "haiku"
        static let summaryMaxBullets = 4
        static let summaryWordsPerBullet = 6
        static let summaryTimeout = 20.0
        static let summaryPrompt = """
            Résume cette réponse d'un assistant de code en 2 à \(summaryMaxBullets) puces très courtes \
            (\(summaryWordsPerBullet) mots max chacune), en français : ce qui a été fait, et ce que \
            j'ai à faire s'il y a quelque chose. Sans titre ni phrase d'intro. Réponds uniquement \
            avec les puces, chacune commençant par « • ».
            """
        /// At most one message per session and per event in this time, in seconds.
        static let minimumInterval = 120.0
        /// While an event waits for you to be away: how often the app looks again, in seconds.
        static let checkInterval = 10.0
        /// Using the Mac this long after an event means you saw it (nothing sent), in seconds.
        static let presenceGrace = 2.0
        /// "Commandes depuis Telegram": how long a request to Telegram waits for a new
        /// message before asking again, and the pause after a failure (no internet…), in seconds.
        static let remoteWait = 25
        static let remoteRetryDelay = 5.0
        /// Your text is pasted into Claude, then Entrée is pressed this long after, in seconds.
        static let remoteSubmitDelay = 0.15
        /// A longer message is refused (number of characters).
        static let remoteMaxLength = 2000
        /// How many sent messages are remembered (to know which session a reply goes to).
        static let remoteRememberedMessages = 300
        /// A message written longer ago than this (in seconds) is refused: it arrived late
        /// (no network, Mac asleep) and may no longer fit what Claude is doing.
        static let remoteMaxAge: TimeInterval = 60
        /// At most this many messages typed into the sessions per minute (all sessions together).
        static let remoteMaxPerMinute = 5
        /// The same text to the same session again within this many seconds is refused
        /// (a message sent twice by mistake).
        static let remoteDuplicateWindow: TimeInterval = 30
        /// This many refused messages within `remoteRefusalWindow` seconds lock the commands again.
        static let remoteMaxRefusals = 10
        static let remoteRefusalWindow: TimeInterval = 10 * 60
        /// The journal ~/.cube-widget/remote.log: how much of each message is written, and
        /// its size (in bytes) before it is put aside as remote.log.1.
        static let remoteLogExcerptLength = 200
        static let remoteLogMaxSize = 1_000_000
        /// `/unlock` sent alone: how long the bot waits for the code, in seconds.
        static let remoteCodeWait: TimeInterval = 60
        /// T5, the Oui / Non buttons of a permission: they work this long after being sent
        /// (in seconds), and what is asked is shown cut after this many characters.
        static let permissionButtonsMaxAge: TimeInterval = 15 * 60
        static let permissionDetailMaxLength = 200
        /// Before pressing "1" (Oui) or Échap (Non), the terminal must show Claude's
        /// permission menu: a line with the first text and one with the second.
        static let permissionPromptMarkers = ["Do you want to", "1. Yes"]
        /// T6, the choice buttons of Claude's questions (they work as long as
        /// `permissionButtonsMaxAge`). A choice's label on its button is cut after this many
        /// characters.
        static let questionButtonMaxLength = 40
        /// Before pressing a choice's number, the terminal must show the question: this text
        /// at the bottom, and the beginning of the question and of the choice (this many
        /// characters, enough even if a long line is cut on two).
        static let questionPromptMarker = "Enter to select"
        static let questionMatchLength = 20
        /// Several questions: after the last answer, the terminal shows a summary to
        /// validate with "1". The app looks for this text every `questionSubmitDelay`
        /// seconds, `questionSubmitTries` times at most.
        static let questionSubmitMarker = "Submit answers"
        static let questionSubmitDelay: TimeInterval = 0.2
        static let questionSubmitTries = 15
        /// `/sessions`: at most this many sessions are listed (one message each).
        static let remoteSessionsListMax = 10
        /// The "réponses depuis Telegram" icon, just before the bell: the space between them.
        static let remoteIconSpacing: CGFloat = 2
        /// `/unlock` with the six-digit code: how long the commands stay unlocked, in seconds.
        static let unlockDuration: TimeInterval = 30 * 60
        /// This many wrong codes in a row turn the commands off (turn them on again on the Mac).
        static let maxFailedCodes = 5
        /// The code of the previous or next 30-second period is accepted too (phone clock a
        /// little off): number of periods on each side.
        static let codeTolerance = 1
        /// Size of the QR code that sets up the unlock code (Réglages → Telegram – Commandes), in points.
        static let codeQRSize: CGFloat = 160
        /// The bell on the cards (on / off for a project): its size, its discreet color,
        /// and its color under the mouse.
        static let bellSize: CGFloat = 13
        /// The clickable area around the bell, as a multiple of its size.
        static let bellHitScale: CGFloat = 1.7
        /// Bell of the widget's front card: distance from the card's top and right edges.
        static let frontBellTopInset: CGFloat = 6
        static let frontBellTrailingInset: CGFloat = 8
        /// Bell of the widget's cards below: size, and space before the status.
        static let backBellSize: CGFloat = 10.5
        static let backBellToStatusSpacing: CGFloat = 4
        static let bellColor = Color(hex: 0x48484C)
        static let bellHoverColor = Color(hex: 0xE0E0E0)
        /// The bell of a project with Telegram on: white, even without the mouse over it.
        static let bellOnColor = Color.white
    }

    // MARK: - Settings

    /// The "Réglages" window (gear of the Cube Hub, ⌘,).
    enum Settings {
        /// Size when first opened (then remembered), and smallest size, in points.
        static let windowSize = CGSize(width: 600, height: 430)
        static let minimumWindowSize = CGSize(width: 520, height: 340)
        /// Width of the list of pages on the left.
        static let sidebarWidth: CGFloat = 170
        /// The pages' icons: a white symbol on a small rounded square of the page's color.
        static let iconSize: CGFloat = 22
        static let iconSymbolSize: CGFloat = 12
        static let iconCornerRadius: CGFloat = 6
        static let generalColor = Color(hex: 0x8E8E93)
        static let widgetColor = Color(hex: 0x5E5CE6)
        static let telegramConnectionColor = Color(hex: 0x2AABEE)   // Telegram's own blue
        static let telegramNotificationsColor = Color(hex: 0xFF375F)
        static let telegramCommandsColor = Color(hex: 0xBF5AF2)
        static let soundsColor = Color(hex: 0xFF2D55)
        static let hubColor = Color(hex: 0x30B0C7)
        /// Sons: width of each volume slider. Cube Hub: the color dot before a theme's name.
        static let volumeSliderWidth: CGFloat = 130
        static let themeDotSize: CGFloat = 9
    }

    // MARK: - Sessions

    /// Reading the session files written by cube-hook (~/.cube-widget/sessions).
    enum Sessions {
        /// The folder is also re-read this often, in seconds (to notice a closed terminal).
        static let refreshInterval = 2.0
        /// A session without a known Claude Code process is forgotten after this much
        /// silence, in seconds (6 h).
        static let forgetSilentSessionAfter: TimeInterval = 6 * 3600
        /// How much of the end of the conversation file is read to find the token count.
        static let transcriptTailBytes: UInt64 = 2_000_000
    }

    // MARK: - Sounds

    /// Sounds of the Sons/ folder, each played once. Volume: 0 = silent, 1 = full
    /// (relative to the Mac's volume). A missing file means no sound for that event.
    enum Sound {
        /// Sons/bosse: the active project starts working (this file is louder than the others).
        static let workingVolume: Float = 0.4
        /// Sons/fini: a task was just completed in the active project.
        static let taskCompletedVolume: Float = 1.0
        /// Sons/attente: a session starts waiting for your answer.
        static let waitingVolume: Float = 1.0
        /// Sons/dodo: the cube starts falling asleep.
        static let fallAsleepVolume: Float = 0.4
        /// A sound that goes with a cube animation waits for that animation to start
        /// (end of the current move, or wake-up). Past this delay, in seconds, it is dropped.
        static let cueMaxDelay = 3.0
    }

    // MARK: - Window

    enum Window {
        /// Empty space around the cards inside the window, so the halo glow
        /// can spill outside the cards without being clipped.
        static let haloMargin: CGFloat = 20
        /// Default distance from the top-right corner of the screen on first launch.
        static let defaultScreenInset: CGFloat = 24
        /// The mouse must move this far before a click becomes a window drag.
        static let dragThreshold: CGFloat = 3
        /// Two clicks closer than this (in seconds) make a double click. A single click
        /// acts after this delay: shorter than the Mac's setting (0.5 s), so folding
        /// reacts faster.
        static let doubleClickWindow = 0.25
        /// Widget sizes offered in the right-click menu (1 = 100 %).
        /// Every size and font of the widget is multiplied by the chosen value.
        static let scaleChoices: [Double] = [1.0, 0.9, 0.8, 0.7, 0.6]
        /// Keyboard shortcut that shows or hides the widget, from any app: ⌃⌥W.
        /// Key code of the key (W = 13, see `kVK_ANSI_…` in Carbon's Events.h) and its
        /// modifiers (Control = 0x1000, Option = 0x0800, Command = 0x0100, Shift = 0x0200).
        static let toggleHotKeyCode: UInt32 = 13
        static let toggleHotKeyModifiers: UInt32 = 0x1000 | 0x0800
        /// The same shortcut as shown in the menus and in Réglages (change it with the two above).
        static let toggleHotKeyLabel = "⌃⌥W"
    }
}
