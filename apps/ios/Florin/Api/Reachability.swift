import Foundation
import Network

/*
 * Whether this phone has a route out at all.
 *
 * Without it, opening the app in the métro started a bank sync that could not
 * work: `URLSession` is told not to wait for connectivity, but a PSD2 pull is
 * not one request — it walks every connection and every account in turn, and
 * each leg spends its own timeout before the next one starts. Four accounts
 * with a twenty-second ceiling is a spinner that turns for a minute and a half
 * and then says nothing useful, over figures that were already correct on
 * screen.
 *
 * A path that is not satisfied is the one failure worth predicting: it is
 * known before the first packet, it will not change during the attempt, and
 * the honest answer — the balances Florin already holds, with the date they
 * were fetched — is the same answer the sync would have produced.
 *
 * Fail-open. The monitor's first callback lands within milliseconds of start,
 * but until it does this says "online", because refusing to sync on a hunch is
 * a worse bug than trying and failing.
 */
@MainActor
final class Reachability: ObservableObject {
    static let shared = Reachability()

    @Published private(set) var online = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.online != satisfied else { return }
                self.online = satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.adrbn.florin.reachability"))
    }

    /// Starts the monitor. Called at launch so the first answer is in by the
    /// time anything asks — reading `online` is otherwise what starts it, and
    /// the first read would get the optimistic default.
    static func begin() { _ = shared }
}
