import BackgroundTasks
import Foundation
import OSLog
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

    /// Ask again for later. Called after every run and at launch, because iOS
    /// keeps at most one pending request per identifier and drops it once it
    /// fires.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
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
        )?.string)?.flatMap { ISO8601DateFormatter.florinNoFraction.date(from: $0) }
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
        _ = try? await BankingSync.run(store: store, config: config, pending: false)
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
}
