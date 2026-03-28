import AVFoundation
import Foundation

/// Manages AVAudioSession configuration for CarPlay audio routing.
///
/// Configures the session for simultaneous recording and playback
/// through the car's audio system (Bluetooth/USB/built-in).
enum CarPlayAudioSession {

    /// Activates audio session for voice interaction in the car.
    ///
    /// Category: `.playAndRecord` for simultaneous mic input and speaker output.
    /// Mode: `.voiceChat` enables echo cancellation and AGC optimized for voice.
    /// Options:
    ///   - `.defaultToSpeaker`: routes playback to car speakers
    ///   - `.allowBluetooth`: allows Bluetooth HFP for car systems
    ///   - `.allowBluetoothA2DP`: allows high-quality Bluetooth audio output
    static func activateForCarPlay() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .defaultToSpeaker,
                .allowBluetooth,
                .allowBluetoothA2DP,
            ]
        )

        try session.setActive(true, options: [])
    }

    /// Deactivates the audio session, notifying other apps they can resume.
    static func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
