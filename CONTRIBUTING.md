# Contributing to ClawCar

Thank you for your interest in contributing!

## Getting Started

1. Fork the repo
2. Install Flutter 3.32+ ([flutter.dev](https://flutter.dev/docs/get-started/install))
3. Clone your fork and run:
   ```bash
   flutter pub get
   dart run build_runner build
   ```
4. Create a feature branch: `git checkout -b feat/my-feature`

## Development

### Running the app
```bash
flutter run
```

### Running tests
```bash
flutter test
```

### Code generation (Freezed/Riverpod)
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Code Style

- Use Dart's official style guide
- Run `dart format .` before committing
- Run `dart analyze` and fix all issues
- Keep files under 400 lines
- Use Freezed for models (immutable)
- Use Riverpod for state management

## Commit Messages

Follow conventional commits:
```
feat: add gateway autodiscovery
fix: handle WebSocket reconnection timeout
refactor: extract audio pipeline
```

## Pull Requests

1. Keep PRs focused on a single feature or fix
2. Include tests for new functionality
3. Update documentation if needed
4. Ensure CI passes

## Architecture

See [CLAUDE.md](CLAUDE.md) for architecture details.

## CarPlay / Android Auto

Native car platform code lives in:
- `ios/Runner/CarPlay/` (Swift)
- `android/app/src/main/kotlin/.../car/` (Kotlin)

These communicate with Flutter via platform channels. See the bridge services in `lib/car/`.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
