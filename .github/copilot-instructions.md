---
description: "Workspace Copilot instructions for ClaudeMeter (macOS SwiftUI app). Use these guidelines to stay aligned with project architecture and test patterns."
---

# ClaudeMeter Copilot Workspace Instructions

## 🧩 What this repo is
- Native macOS app written in Swift + SwiftUI, targeting macOS 14+.
- Core architecture:
  - `ClaudeMeter/Core/` for business logic: Managers, Services, Models, Protocols, Dependency injection
  - `ClaudeMeter/UI/` for SwiftUI presentation (MenuBar, Popover, Settings)
  - `ClaudeMeter/App/` for app lifecycle and state
- Tests in `ClaudeMeterTests/` and `ClaudeMeterUITests/`.

## 🚀 Build & test commands
- `xcodebuild -scheme ClaudeMeter -configuration Release build`
- `xcodebuild test -scheme ClaudeMeter`
- `scripts/build-app.sh` (wrapper script; supports version input)
- `open ClaudeMeter.xcodeproj` (Xcode 15+ expected)

## 🏗️ Core conventions
- Protocol-based external dependencies (`ApiServiceProtocol`, `KeychainServiceProtocol`, etc.).
- Use `DependencyContainer` for injection, with `#if DEBUG` mock wiring in tests.
- `Constants.swift` centralizes magic numbers, endpoints, thresholds.
- `@MainActor` on published state managers and UI updates.
- `struct` and `enum` preferred for value safety; class for ObservableObjects/components requiring identity.
- `// MARK: -` in Swift files for sectioning.
- License header is expected in all Swift files.

## 🧪 Testing guidelines
- Unit tests in `ClaudeMeterTests/` mirror production structure (Managers/Services/Mocks).
- Mocks: `MockAPIService`, `MockKeychainService`, `MockCacheManager`, `MockNotificationService`, and `MockURLProtocol` for networking.
- Keep tests deterministic (use dependency injection for time/network states), avoid async timeouts by explicit expectations.
- Shared fixtures in `ClaudeMeterTests/TestUtilities/TestData.swift`.

## 🔍 PR and issue help
- Prefer small changes with focused meaning and one goal (bugfix or feature), with regression tests when applicable.
- For behavior changes in app settings or usage tracking, update `UsageManager` + any persisted state serialization.
- For UI changes, update SwiftUI previews and add / adjust UI tests if behavior is non-trivial.

## 📌 Knowledge links
- `README.md` for project overview and usage
- `CONTRIBUTING.md` for commit style and workflow (if present; otherwise follow standard GitHub procedure)
- `scripts/build-app.sh` for release packaging command pattern

## 💡 Agent behavior hints
- Prefer non-invasive refactors that keep separation between Core and UI layers.
- If a requested task involves external API behavior in `Core/Services`, propose adding protocol test coverage for interaction and error paths.
- If editing SwiftUI popovers or menu bar behavior, confirm whether app state should be shared via `AppState` vs local view model.

## 🛠️ Path-specific recomendations
- `ClaudeMeter/Core/Managers/`: keep business logic independent of UI (avoid importing SwiftUI here; use Core types + publishers)
- `ClaudeMeter/Core/Services/`: keep each service responsible for its own system integration and error translation.
- `ClaudeMeter/UI/`: follow SwiftUI best practices (state lifting, view modules, and light controllers in ViewModels).
