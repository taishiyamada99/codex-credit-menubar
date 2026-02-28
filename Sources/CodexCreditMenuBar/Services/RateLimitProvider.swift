import Foundation

protocol RateLimitProvider {
    var stream: AsyncStream<ServiceEvent> { get }
    func start() async
    func stop() async
    func refreshNow() async
    func applySettings(_ settings: AppSettings) async
}
