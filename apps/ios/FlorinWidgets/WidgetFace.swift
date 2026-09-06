import AppIntents
import Foundation
import WidgetKit

/// Which of the widget's two answers is showing.
///
/// The tile leads with what is left for the month, because that is the question
/// asked several times a week in a shop. Net worth is the other question — the
/// one asked once a month, sitting down — and it does not deserve the default
/// slot for the reason the original widget was changed: on a screen seen eighty
/// times a day, a figure that moves monthly says nothing new between glances.
///
/// But it is one tap away rather than a separate widget, because two tiles for
/// two views of the same ledger is two tiles nobody has room for.
enum WidgetFace: String {
    case leftToSpend
    case netWorth

    var other: WidgetFace { self == .leftToSpend ? .netWorth : .leftToSpend }

    /*
     * The App Group, not `standard`.
     *
     * The intent runs in the widget's process and the view is rendered in
     * another; only the shared container is seen by both. `standard` would
     * have flipped a flag the view never read, and the tap would have looked
     * broken while doing exactly what it was told.
     */
    private static let key = "florin.widget.face"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshot.group)
    }

    static var current: WidgetFace {
        guard let raw = defaults?.string(forKey: key) else { return .leftToSpend }
        return WidgetFace(rawValue: raw) ?? .leftToSpend
    }

    static func store(_ face: WidgetFace) {
        defaults?.set(face.rawValue, forKey: key)
    }
}

/// The tap. Interactive widgets landed in iOS 17 and the app's floor is 17.4,
/// so this flips the face in place instead of opening the app — which is the
/// difference between a glance and an errand.
struct ToggleWidgetFaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch view"
    /// Nothing to open: the whole point is that the home screen answers.
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetFace.store(WidgetFace.current.other)
        // WidgetKit reloads after an intent on its own; asking costs nothing
        // and this is not something a home screen gets to be flaky about.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
