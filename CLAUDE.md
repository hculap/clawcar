# ClawCar - Development Guide

## Project Overview
Voice-first mobile client for OpenClaw AI gateway with CarPlay and Android Auto support.
The app records audio, sends it to OpenClaw gateway (which handles STT/TTS), and plays back audio responses.

## Tech Stack
- **Framework:** Flutter 3.32+ / Dart 3.8+
- **State Management:** Riverpod 3 with code generation
- **Protocol:** OpenClaw Gateway Protocol v3 (WebSocket JSON frames)
- **CarPlay:** Native Swift via platform channels (CPVoiceControlTemplate)
- **Android Auto:** Native Kotlin via platform channels (Car App Library)

## Architecture
- `lib/core/` - Gateway client, audio services, configuration
- `lib/features/` - Feature modules (discovery, agents, voice_chat, settings)
- `lib/car/` - CarPlay and Android Auto platform channel bridges
- `lib/shared/` - Models, providers, utilities
- `ios/Runner/CarPlay/` - Native Swift CarPlay implementation
- `android/app/src/main/kotlin/.../car/` - Native Kotlin Android Auto implementation

## Key Patterns
- **Immutability:** Use Freezed for all models. Never mutate state directly.
- **Feature-first:** Organize by feature/domain, not by type.
- **Riverpod providers:** Use StreamProvider for real-time data (WebSocket, audio, VAD).
- **Platform channels:** CarPlay/Android Auto communicate via MethodChannel/EventChannel.

## Audio Flow (POC)
1. App records raw audio via `record` package
2. VAD (Silero via `vad` package) detects end of speech
3. Audio sent to OpenClaw gateway via WebSocket
4. Gateway runs STT -> agent -> TTS
5. App receives audio response and plays it back via `just_audio`

## OpenClaw Gateway Protocol
- WebSocket on port 18789 (default)
- Frame types: `req`, `res`, `event`
- Discovery: mDNS `_openclaw-gw._tcp`
- Auth: Ed25519 device pairing or token/password
- Key methods: `connect`, `agent`, `chat.send`, `tts.convert`

## Commands
- `flutter pub get` - Install dependencies
- `flutter run` - Run on connected device
- `dart run build_runner build` - Generate Freezed/Riverpod code
- `flutter test` - Run unit tests
- `flutter test integration_test/` - Run integration tests

## Code Style
- Max file length: 400 lines (800 absolute max)
- Max function length: 50 lines
- No console.log/print statements in production code
- Validate all external input with schemas
- Handle all errors explicitly
