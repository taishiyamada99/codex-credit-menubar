import XCTest
@testable import CodexCreditMenuBar

final class SourceResolverTests: XCTestCase {
    private let resolver = SourceResolver()

    func testUnsafeCodexAppPathDetection() {
        XCTAssertTrue(resolver.isUnsafeCodexAppPath("/Applications/Codex.app/Contents/MacOS/codex"))
        XCTAssertTrue(resolver.isUnsafeCodexAppPath("/Applications/Codex.app/Contents/MacOS/Codex"))
        XCTAssertFalse(resolver.isUnsafeCodexAppPath("/Applications/Codex.app/Contents/Resources/codex"))
    }

    func testSanitizeSafePathPassThrough() {
        let safe = "/Applications/Codex.app/Contents/Resources/codex"
        XCTAssertEqual(resolver.sanitizePathForCodexApp(path: safe), safe)
    }

    func testDesktopModeNeverReturnsMacOSBinary() {
        let commands = resolver.resolve(mode: .autoDesktopFirst, customPath: "")
        let unsafe = commands.first { resolver.isUnsafeCodexAppPath($0.launchPath) }
        XCTAssertNil(unsafe)
    }
}
