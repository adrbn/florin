import BackgroundTasks
import Foundation
import OSLog
import UIKit
import UserNotifications

/// Noticing what arrived while the app was closed.
///
/// A ledger you have to open to learn anything from is a ledger you check less
/// and less. This asks the bank on its own and says what came in — but sparingly
/// and honestly, for two reasons that both matter.
///
/// The consent behind a PSD2 connection allows four unattended pulls a day. Ask
/// more often and the bank refuses; the refusals then look like a broken sync,
/// which is worse than a slower one. So a wake-up that lands too soon after the
/// last successful sync does nothing rather than burn a pull.
///
/// And a notification per transaction would be a stream nobody reads. One
/// summary per wake-up, only when something actually arrived.
enum BackgroundRefresh {
    static let taskId = "com.adrbn.florin.refresh"
    /// PSD2 allows four unattended pulls a day; six hours leaves room for the
    /// ones the user asks for themselves.
    private static let minimumInterval: TimeInterval = 6 * 3600
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "background")

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskId, using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    /*
     * Ask for the morning, not for six hours from now.
     *
     * A bank does not publish continuously. La Banque Postale posts to its PSD2
     * feed overnight, so what was spent on Tuesday appears in the small hours of
     * Wednesday — and a wake-up six hours after the last one lands wherever the
     * clock happens to fall, which for a batched feed means either nothing new
     * or a summary delivered at four in the morning.
     *
     * Asking for shortly after seven puts the wake-up after the batch and
     * before the day: one notification, in the morning, saying what landed
     * overnight. iOS is free to ignore the time entirely — `earliestBeginDate`
     * is the earliest, not the appointment — but a request aimed at a useful
     * hour is more likely to be granted at one than a request aimed at nothing.
     *
     * Called after every run and at launch: iOS keeps at most one pending
     * request per identifier and drops it once it fires.
     */
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = nextMorning()
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The next 07:15 that is at least an hour away — so a run at 07:00 does
    /// not immediately ask to be woken again fifteen minutes later.
    static func nextMorning(from now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let floor = now.addingTimeInterval(3600)
        var components = calendar.dateComponents([.year, .month, .day], from: floor)
        components.hour = 7
        components.minute = 15
        guard let candidate = calendar.date(from: components) else {
            return now.addingTimeInterval(minimumInterval)
        }
        return candidate > floor
            ? candidate
            : calendar.date(byAdding: .day, value: 1, to: candidate) ?? floor
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            let found = await run()
            task.setTaskCompleted(success: found >= 0)
        }
        // iOS gives a background task seconds, not minutes, and kills the app
        // outright if it overruns. Cancelling ourselves loses a sync; being
        // killed loses the right to be woken again.
        task.expirationHandler = { work.cancel() }
    }

    /// Returns how many transactions arrived, or -1 when nothing was attempted.
    @discardableResult
    static func run() async -> Int {
        guard let store = LocalStore.shared, BankingFlow.isConfigured else { return -1 }

        let last = (try? store.database.scalar(
            "SELECT max(last_synced_at) FROM bank_connections"
        )?.string).flatMap { Timestamp.parse($0) }
        if let last, Date().timeIntervalSince(last) < minimumInterval {
            log.notice("skipped: synced recently")
            return -1
        }

        let before = (try? store.database.scalar(
            "SELECT count(*) FROM transactions WHERE deleted_at IS NULL"
        )?.int) ?? 0
        guard let config = try? BankingFlow.config(store) else { return -1 }
        // Booked only. Nobody is waiting on this one, and the extra call per
        // account would spend the day's unattended budget faster than it
        // earns it.
        _ = try? await BankingSync.run(
            store: store, config: config, pending: false, trigger: "scheduler"
        )
        let after = (try? store.database.scalar(
            "SELECT count(*) FROM transactions WHERE deleted_at IS NULL"
        )?.int) ?? before

        let arrived = max(0, after - before)
        if arrived > 0 { await notify(arrived, store: store) }
        return arrived
    }

    /// One line, with the figure that answers the question someone opens the
    /// app to ask: what came in, and what does it come to.
    private static func notify(_ count: Int, store: LocalStore) async {
        let centre = UNUserNotificationCenter.current()
        guard let settings = try? await centre.notificationSettings(),
              settings.authorizationStatus == .authorized
        else { return }

        let total = (try? store.database.scalar(
            """
            SELECT coalesce(sum(amount), 0) FROM transactions
            WHERE deleted_at IS NULL AND needs_review = 1 AND is_pending = 0
            """
        )?.double) ?? 0

        let content = UNMutableNotificationContent()
        content.title = Strings.device("v2.notify.title", "{count} nouvelles opérations",
                                       ["count": count])
        content.body = Strings.device(
            "v2.notify.body", "{amount} à vérifier dans Florin.",
            ["amount": Money.string(total, locale: Locale.current.identifier,
                                    currency: "EUR", decimals: false, signed: true)]
        )
        content.sound = nil
        try? await centre.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    /// Asked for at the moment it means something — after a bank is connected,
    /// not on a first launch where the app has nothing to tell anyone.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge])) ?? false
    }

    /*
     * Whether any of this can work at all.
     *
     * The wake-up depends on two switches the app does not own — the
     * notification permission and iOS's own background refresh — and when
     * either is off Florin looks broken while behaving correctly. Reading them
     * back is the difference between "you had no notifications" and "you had
     * none because background refresh is off for this app".
     */
    struct Readiness {
        var notificationsAllowed = false
        var backgroundAllowed = false
    }

    @MainActor
    static func readiness() async -> Readiness {
        let settings = try? await UNUserNotificationCenter.current().notificationSettings()
        return Readiness(
            notificationsAllowed: settings?.authorizationStatus == .authorized,
            backgroundAllowed: UIApplication.shared.backgroundRefreshStatus == .available
        )
    }

    /*
     * One notification, on purpose, a few seconds from now.
     *
     * The real one arrives from a background wake-up iOS may take days to
     * grant, so "did I set this up correctly?" is otherwise a question you
     * answer by waiting. The delay is there so the app can be put away first:
     * a banner does not appear over the app that posted it.
     */
    static func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = Strings.device("v2.notify.testTitle", "Florin vous parlera comme ça")
        content.body = Strings.device(
            "v2.notify.testBody",
            "Un résumé le matin, quand votre banque a publié la nuit."
        )
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
        )
    }
}
