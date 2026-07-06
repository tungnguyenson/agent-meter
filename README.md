# ClaudeMeter

A native macOS menu bar app that monitors your Claude Code usage, token consumption, and rate limits in real-time.

<p align="center">
  <img src="screenshot.png" alt="Light Mode" width="45%" />
  <img src="screenshot-2.png" alt="Dark Mode" width="45%" />
</p>

## Features

- **Real-time monitoring**: Tracks 5-hour and 7-day usage windows, plus per-model limits (Opus, Sonnet, Design) and extra usage when available
- **Menu bar widget**: Shows current utilization at a glance in three modes — Icon Only, Compact, or Detailed (with a fixed or live-countdown style)
- **Plan detection**: Recognizes your subscription tier (Free, Pro, Max, Max 5x, Team, Enterprise)
- **Notifications**: Configurable alerts when you approach a limit, with hysteresis and throttling to avoid repeat spam (default thresholds: 75%, 90%, 95%)
- **Adaptive polling**: Refresh rate scales with your usage level and current activity, with a circuit breaker that backs off after repeated API failures
- **Offline caching**: Displays your last known usage even when offline
- **Web API fallback**: Optionally uses a web session as a backup when the OAuth API is rate limited
- **Native macOS**: Built with SwiftUI for a minimal resource footprint

## Requirements

- macOS 14.0 (Sonoma) or later
- Claude Code CLI authenticated (`claude login`)
- Xcode 15.0+ (only to build from source)

## Installation

### Download release

1. Download the latest `ClaudeMeter-*.dmg` from the [Releases](https://github.com/tungnguyenson/claude-meter/releases) page
2. Open the DMG and drag **ClaudeMeter.app** into your Applications folder
3. Launch the app

> Full releases are signed with a Developer ID certificate and notarized by Apple, so they open without a Gatekeeper prompt. See [docs/releasing.md](docs/releasing.md) for how releases are built and signed.

### Build from source

```bash
# Clone the repository
git clone https://github.com/tungnguyenson/claude-meter.git
cd claude-meter

# Build a release .app into ./build/Build/Products/Release/
./scripts/build-app.sh

# Or build a distributable DMG (requires: pip install dmgbuild)
./scripts/create-dmg.sh [version]

# Or open in Xcode
open ClaudeMeter.xcodeproj
```

## Configuration

ClaudeMeter reads the OAuth credentials that the Claude Code CLI stores in your system keychain, so no separate sign-in is needed. Just make sure you're authenticated:

```bash
claude login
```

Once logged in, ClaudeMeter automatically detects your session. See [docs/authentication.md](docs/authentication.md) for how credential lookup and the web fallback work.

### Settings

Open settings from the menu bar popover:

- **General**: Launch at login, show in Dock, refresh interval (30 seconds to 1 hour), and Web API fallback credentials
- **Appearance**: Menu bar display mode (Icon Only / Compact / Detailed) and color scheme (Auto / Light / Dark)
- **Notifications**: Enable/disable alerts and configure the alert thresholds
- **About**: App version and information

## Architecture

Three strictly separated layers:

```
ClaudeMeter/
├── App/                          # Lifecycle: entry point, menu bar, central AppState
├── Core/                         # Business logic (no SwiftUI)
│   ├── Constants.swift           # Endpoints, thresholds, timeouts, intervals
│   ├── DependencyContainer.swift # Service locator for dependency injection
│   ├── Protocols/                # Service abstractions (enable mock injection)
│   ├── Models/                   # UsageData, AppSettings, SubscriptionType, …
│   ├── Services/                 # API, Keychain, Notifications, version resolver
│   └── Managers/                 # Usage, Polling, Cache
├── UI/                           # SwiftUI views
│   ├── MenuBar/                  # Status item rendering
│   ├── Popover/                  # Main usage display
│   ├── Settings/                 # Preferences
│   └── Components/               # Reusable views
└── Extensions/                   # Swift extensions
```

### Key components

- **APIService**: Communicates with the Anthropic API, with retry and backoff
- **KeychainService**: Reads Claude Code OAuth credentials from the system keychain
- **NotificationService**: System notifications with a threshold buffer and throttling
- **PollingManager**: Adaptive polling with a failure circuit breaker and network-wake recovery
- **CacheManager**: Offline caching of usage data in `~/Library/Caches/ClaudeMeter/`

## Development

```bash
# Run all tests
xcodebuild test -scheme ClaudeMeter

# Run a single test class
xcodebuild test -scheme ClaudeMeter -only-testing ClaudeMeterTests/UsageManagerTests
```

Pushes to `main` trigger the [Build DMG](.github/workflows/build-dmg.yml) GitHub Action, which builds, signs, and notarizes the app, packages a DMG, and publishes it as a prerelease. Pushing a `v*` tag (e.g. `v1.0.0`) publishes a full release instead. See [docs/releasing.md](docs/releasing.md) for the full pipeline, trigger rules, and the signing secrets it needs.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built for use with [Claude Code](https://claude.ai/claude-code)
- Powered by the Anthropic API

---

**Developed by ali@[puq.ai](https://puq.ai)**
