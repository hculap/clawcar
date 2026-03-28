# ClawCar

**Voice-first mobile client for [OpenClaw](https://github.com/openclaw/openclaw) AI gateway with CarPlay and Android Auto support.**

Talk to your AI agents while driving. ClawCar connects to your self-hosted OpenClaw gateway and provides a hands-free voice interface — on your phone, CarPlay, or Android Auto.

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│   ClawCar   │────▶│  OpenClaw Gateway │────▶│  AI Agent   │
│  (mobile)   │◀────│  (your server)    │◀────│  (LLM)      │
└─────────────┘     └──────────────────┘     └─────────────┘
     │                      │
     │  audio ──▶ STT ──▶ agent ──▶ TTS ──▶ audio
     │                      │
     ▼                      ▼
┌─────────┐          ┌───────────┐
│ CarPlay │          │ Android   │
│         │          │ Auto      │
└─────────┘          └───────────┘
```

1. **You speak** — ClawCar records audio with Voice Activity Detection
2. **Audio sent to OpenClaw** — Gateway handles STT (speech-to-text)
3. **Agent processes** — Your configured AI agent generates a response
4. **Response spoken back** — Gateway handles TTS (text-to-speech), ClawCar plays audio

No STT/TTS processing happens on the device. OpenClaw handles the full voice pipeline server-side.

## Features

- **Gateway Discovery** — mDNS autodiscovery of OpenClaw gateways on your network, or manual address entry
- **Agent Selection** — Browse and select from available agents on your gateway
- **Voice-First UI** — Minimal visual interface, optimized for voice interaction
- **Voice Activity Detection** — Neural VAD (Silero) detects when you stop speaking
- **CarPlay Support** — Native `CPVoiceControlTemplate` integration (iOS 26.4+)
- **Android Auto Support** — Native Car App Library integration
- **Auto-Reconnect** — Resilient WebSocket connection with exponential backoff
- **Dark Theme** — Designed for low-distraction use while driving

## Requirements

- **OpenClaw gateway** running on your network (v1.0+)
- **iOS 17+** (CarPlay voice apps require iOS 26.4+)
- **Android API 21+** (Android Auto requires separate approval)
- **Flutter 3.32+** for building from source

## Getting Started

### Install from source

```bash
# Clone the repo
git clone https://github.com/hculap/clawcar.git
cd clawcar

# Install dependencies
flutter pub get

# Generate Freezed/Riverpod code
dart run build_runner build --delete-conflicting-outputs

# Run on connected device
flutter run
```

### Connect to your gateway

1. Open ClawCar — it automatically scans for OpenClaw gateways via mDNS
2. Select your gateway from the list, or enter the address manually
3. Choose an agent
4. Tap the microphone and start talking

## Architecture

```
lib/
├── main.dart                          # Entry point
├── app.dart                           # App widget & theme
├── core/
│   ├── gateway/
│   │   ├── gateway_client.dart        # WebSocket client with reconnection
│   │   ├── gateway_protocol.dart      # Protocol v3 frame types
│   │   └── gateway_discovery.dart     # mDNS service discovery
│   ├── audio/
│   │   ├── audio_recorder.dart        # PCM16 mic recording
│   │   ├── audio_player_service.dart  # Streaming audio playback
│   │   └── vad_service.dart           # Silero Voice Activity Detection
│   └── config/
│       └── app_config.dart            # Persistent settings
├── features/
│   ├── discovery/                     # Gateway discovery screen
│   ├── agents/                        # Agent selection screen
│   ├── voice_chat/                    # Voice conversation screen
│   └── settings/                      # App settings
├── car/
│   ├── carplay/                       # CarPlay platform channel bridge
│   └── android_auto/                  # Android Auto platform channel bridge
└── shared/
    ├── models/                        # Freezed data models
    └── providers/                     # Riverpod providers
```

### Car Platform Integration

CarPlay and Android Auto require **native platform code** — Flutter widgets cannot drive the car head unit directly.

| Platform | Implementation | Category |
|----------|---------------|----------|
| **CarPlay** | Swift `CPVoiceControlTemplate` | Voice-based Conversational App (iOS 26.4+) |
| **Android Auto** | Kotlin `CarAppService` + Car App Library | Templated app with `CarMicrophone` |

Both communicate with Flutter via `MethodChannel` / `EventChannel`. The native modules handle car UI templates while Flutter manages business logic, gateway communication, and audio processing.

### OpenClaw Gateway Protocol

ClawCar uses the [OpenClaw Gateway Protocol v3](https://docs.openclaw.ai/gateway/protocol):

- **Transport:** WebSocket (default port 18789)
- **Discovery:** mDNS `_openclaw-gw._tcp`
- **Auth:** Ed25519 device pairing or token-based
- **Voice:** Gateway Talk Mode — audio in, audio out

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.32+ / Dart 3.8+ |
| State | Riverpod 3 |
| Models | Freezed (immutable) |
| Networking | `web_socket_channel` |
| Discovery | `nsd` (mDNS/Bonjour) |
| Audio Recording | `record` |
| VAD | `vad` (Silero neural model) |
| Audio Playback | `just_audio` |
| CarPlay | Native Swift (platform channels) |
| Android Auto | Native Kotlin (platform channels) |

## Roadmap

See the [GitHub Project](https://github.com/hculap/clawcar/projects) for detailed tracking.

### Phase 1: Core Voice Client
- [ ] Gateway discovery (mDNS + manual)
- [ ] WebSocket connection with auth
- [ ] Audio recording + VAD
- [ ] Send audio to gateway, receive and play response
- [ ] Agent selection UI

### Phase 2: CarPlay
- [ ] Apple CarPlay entitlement application
- [ ] CPVoiceControlTemplate implementation
- [ ] Voice control state sync with Flutter
- [ ] CarPlay Simulator testing

### Phase 3: Android Auto
- [ ] Car App Library integration
- [ ] CarMicrophone voice input
- [ ] Android Desktop Head Unit (DHU) testing

### Phase 4: Polish
- [ ] Session history
- [ ] Continuous conversation mode
- [ ] Settings persistence
- [ ] Error recovery UX
- [ ] Accessibility

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License — see [LICENSE](LICENSE).

## Acknowledgments

- [OpenClaw](https://github.com/openclaw/openclaw) — the AI agent gateway this client connects to
- [Silero VAD](https://github.com/snakers4/silero-vad) — voice activity detection model
