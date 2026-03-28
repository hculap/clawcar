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

### Android Auto DHU Testing

The [Desktop Head Unit (DHU)](https://developer.android.com/training/cars/testing/dhu) emulates an Android Auto head unit on your development machine. Use it to test voice interaction without a real car.

#### Prerequisites

1. **Android SDK** with `ANDROID_HOME` set (defaults to `~/Library/Android/sdk` on macOS)
2. **DHU emulator** installed via SDK Manager:
   - Android Studio → SDK Manager → SDK Tools tab → check **Android Auto Desktop Head Unit Emulator**
   - Or: `sdkmanager 'extras;google;auto'`
3. **Android Auto app** installed on the phone/emulator
4. **Developer mode** enabled in Android Auto:
   - Open Android Auto on the phone → tap the version number 10 times
   - Open Developer Settings → enable **Unknown sources**

#### Running the DHU

```bash
# Quick start (TCP transport, recommended)
./scripts/dhu-test.sh

# USB transport (for physical devices over USB)
./scripts/dhu-test.sh --usb
```

**Manual steps** (if you prefer not to use the script):
```bash
# 1. Forward the TCP port
adb forward tcp:5277 tcp:5277

# 2. Launch DHU
$ANDROID_HOME/extras/google/auto/desktop-head-unit --transport=tcp
```

#### Verifying Voice Interaction

1. Launch DHU — ClawCar should appear as an app in the car launcher
2. Tap the **ClawCar** icon to open the voice screen
3. Tap the **microphone** button — the UI state should cycle through:
   - `idle` → `listening` (mic active)
   - `listening` → `processing` (after speech ends / tap to stop)
   - `processing` → `speaking` (audio response plays)
   - `speaking` → `idle` (response complete)
4. Verify state transitions appear correctly on the DHU message template
5. Check `adb logcat -s FlutterActivity` for platform channel events

#### Troubleshooting

| Problem | Solution |
|---------|----------|
| ClawCar doesn't appear in DHU | Ensure the app is installed (`flutter run`) and DHU is connected. Check `adb logcat` for `CarAppService` binding errors. |
| "Host not allowed" error | The app uses `ALLOW_ALL_HOSTS_VALIDATOR` in debug builds. Ensure you're running a debug build (`flutter run` without `--release`). |
| Mic button unresponsive | Check that `RECORD_AUDIO` permission is granted. Run `adb shell pm grant com.clawcar.clawcar android.permission.RECORD_AUDIO`. |
| DHU won't connect | Verify `adb forward tcp:5277 tcp:5277` succeeded. Restart ADB with `adb kill-server && adb start-server`. |

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
