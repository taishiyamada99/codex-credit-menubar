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
            "/Applications/Codex.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/MacOS/codex",
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
            guard FileManager.default.isExecutableFile(atPath: expanded) else {
                return []
            }
            return [CodexCommand(
                launchPath: expanded,
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
}
