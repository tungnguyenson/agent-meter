# Agent Meter

A native macOS menu bar app for monitoring subscription usage and rate limits
across coding agents. The first supported providers are Claude Code and Codex.

<p align="center">
  <img src="screenshot.png" alt="Light Mode" width="45%" />
  <img src="screenshot-2.png" alt="Dark Mode" width="45%" />
</p>

## Features

- **Multiple providers**: Enable Claude Code, Codex, or both and switch without restarting
- **Dynamic limits**: Renders every rate-limit window reported by each provider
- **Menu bar widget**: Pin up to two provider metrics in Icon, Compact, or Detailed modes
- **Per-provider isolation**: A failed provider keeps its last successful snapshot and does not block the others
- **Notifications and caching**: Provider-scoped threshold alerts and offline snapshots
- **Secure fallback credentials**: Optional Claude web-session fallback is stored in Agent Meter's Keychain item, never in preferences
- **Native macOS**: Built with SwiftUI for a minimal resource footprint

## Requirements

- macOS 14.0 (Sonoma) or later
- At least one authenticated provider:
  - Claude Code CLI (`claude login`)
  - Codex CLI 0.146.0 or newer (`codex login`)
- Xcode 15.0+ (only to build from source)

## Installation

### Download release

1. Download the latest `AgentMeter-*.dmg` from the [Releases](https://github.com/tungnguyenson/agent-meter/releases) page
2. Open the DMG and drag **AgentMeter.app** into your Applications folder
3. Launch the app

> Full releases are signed with a Developer ID certificate and notarized by Apple, so they open without a Gatekeeper prompt. See [docs/releasing.md](docs/releasing.md) for how releases are built and signed.

### Build from source

```bash
# Clone the repository
git clone https://github.com/tungnguyenson/agent-meter.git
cd agent-meter

# Build a release .app into ./build/Build/Products/Release/
./scripts/build-app.sh

# Or build a distributable DMG (requires: pip install dmgbuild)
./scripts/create-dmg.sh [version]

# Or open in Xcode
open AgentMeter.xcodeproj
```

## Configuration

Agent Meter uses the sessions already owned by each CLI. It does not copy Codex
credentials and only reads the Claude Code keychain entry:

```bash
claude login
codex login
```

See [Claude Code provider](docs/providers/claude-code.md),
[Codex provider](docs/providers/codex.md), and
[feasibility](docs/feasibility.md) for the exact data sources and limitations.

### Settings

Open settings from the menu bar popover:

- **General**: Providers, Codex binary path, refresh interval, and optional Claude web fallback
- **Appearance**: Menu bar display mode (Icon Only / Compact / Detailed) and color scheme (Auto / Light / Dark)
- **Notifications**: Enable/disable alerts and configure the alert thresholds
- **About**: App version and information

## Architecture

The app separates provider acquisition from normalized usage state and UI:

```
AgentMeter/
├── App/                          # Lifecycle: entry point, menu bar, central AppState
├── Core/                         # Business logic (no SwiftUI)
│   ├── Constants.swift           # Endpoints, thresholds, timeouts, intervals
│   ├── DependencyContainer.swift # Service locator for dependency injection
│   ├── Protocols/                # Service abstractions (enable mock injection)
│   ├── Models/                   # UsageSnapshot, UsageMetric, settings
│   ├── Providers/                # Claude Code and Codex adapters
│   ├── Services/                 # API, Keychain, notifications
│   └── Managers/                 # Coordination, polling, per-provider cache
├── UI/                           # SwiftUI views
│   ├── MenuBar/                  # Status item rendering
│   ├── Popover/                  # Main usage display
│   ├── Settings/                 # Preferences
│   └── Components/               # Reusable views
└── Extensions/                   # Swift extensions
```

### Key components

- **UsageCoordinator**: Concurrent refresh with isolated provider state
- **ClaudeCodeProvider**: Anthropic OAuth usage API plus optional web fallback
- **CodexProvider**: Long-lived local `codex app-server` JSON-RPC client
- **SnapshotCacheManager**: Versioned snapshots in `~/Library/Caches/AgentMeter/Providers/`

## Development

```bash
# Run all tests
xcodebuild test -scheme AgentMeter

# Run a single test class
xcodebuild test -scheme AgentMeter -only-testing AgentMeterTests/UsageManagerTests
```

Pushes to `main` trigger the [Build DMG](.github/workflows/build-dmg.yml) GitHub Action, which builds, signs, and notarizes the app, packages a DMG, and publishes it as a prerelease. Pushing a `v*` tag (e.g. `v1.0.0`) publishes a full release instead. See [docs/releasing.md](docs/releasing.md) for the full pipeline, trigger rules, and the signing secrets it needs.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Claude Code integration expanded to support multiple providers (Codex)
- Codex integration uses the locally installed Codex CLI app-server

---

**Developed by ali@[puq.ai](https://puq.ai)**
