import Foundation

struct CodexCommand: Hashable {
    let launchPath: String
    let arguments: [String]
    let label: String
}

struct SourceResolver {
    func resolve(mode: SourceMode, customPath: String) -> [CodexCommand] {
        switch mode {
        case .autoDesktopFirst:
            return desktopCommands() + cliCommands()
        case .codexApp:
            return desktopCommands()
        case .codexCLI:
            return cliCommands()
        case .customPath:
            return customCommands(path: customPath)
        }
    }

    private func desktopCommands() -> [CodexCommand] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/bin/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex"
        ]

        return candidates.compactMap { path in
            guard FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return CodexCommand(
                launchPath: path,
                arguments: ["app-server", "--listen", "stdio://"],
                label: "Codex App"
            )
        }
    }

    private func cliCommands() -> [CodexCommand] {
        [CodexCommand(
            launchPath: "/usr/bin/env",
            arguments: ["codex", "app-server", "--listen", "stdio://"],
            label: "Codex CLI"
        )]
    }

    private func customCommands(path: String) -> [CodexCommand] {
        let expanded = NSString(string: path).expandingTildeInPath
        guard !expanded.isEmpty else {
            return []
        }

        if expanded.contains("/") {
            let safePath = sanitizePathForCodexApp(path: expanded)
            guard let safePath else {
                return []
            }
            guard FileManager.default.isExecutableFile(atPath: safePath) else {
                return []
            }
            return [CodexCommand(
                launchPath: safePath,
                arguments: ["app-server", "--listen", "stdio://"],
                label: "Custom"
            )]
        }

        return [CodexCommand(
            launchPath: "/usr/bin/env",
            arguments: [expanded, "app-server", "--listen", "stdio://"],
            label: "Custom"
        )]
    }

    func isUnsafeCodexAppPath(_ path: String) -> Bool {
        path.lowercased().contains("/codex.app/contents/macos/")
    }

    func sanitizePathForCodexApp(path: String) -> String? {
        guard isUnsafeCodexAppPath(path) else {
            return path
        }

        guard let prefix = path.range(of: "/Contents/MacOS/", options: [.caseInsensitive]) else {
            return nil
        }
        let appRoot = String(path[..<prefix.lowerBound])
        let fallback = appRoot + "/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: fallback) {
            return fallback
        }
        return nil
    }
}
