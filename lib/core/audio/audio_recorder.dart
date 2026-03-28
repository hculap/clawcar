import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// PCM16 audio recording config: 16kHz, mono, with processing enabled.
const audioRecordConfig = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  autoGain: true,
  echoCancel: true,
  noiseSuppress: true,
);

/// Interface for audio recording services used by the voice pipeline.
abstract class AudioRecorderBase {
  Stream<Uint8List> get audioStream;
  bool get isRecording;
  Future<void> startRecording();
  Future<void> stopRecording();
  Future<void> dispose();
}

/// Cross-platform audio recording service that streams PCM16 chunks.
///
/// Streams raw PCM16 audio at 16kHz mono via [audioStream].
/// Handles microphone permissions, subscription lifecycle, and error recovery.
class AudioRecorderService implements AudioRecorderBase {
  AudioRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final _audioController = StreamController<Uint8List>.broadcast();
  StreamSubscription<List<int>>? _recordingSubscription;
  bool _isRecording = false;
  bool _isDisposed = false;

  /// Broadcast stream of PCM16 audio chunks (16kHz, mono).
  Stream<Uint8List> get audioStream => _audioController.stream;

  /// Whether the recorder is actively streaming audio.
  bool get isRecording => _isRecording;

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() async {
    _assertNotDisposed();
    return _recorder.hasPermission();
  }

  /// Starts streaming PCM16 audio from the microphone.
  ///
  /// Throws [StateError] if microphone permission is not granted
  /// or if the service has been disposed.
  Future<void> startRecording() async {
    _assertNotDisposed();
    if (_isRecording) return;

    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      throw StateError('Microphone permission not granted');
    }

    final stream = await _recorder.startStream(audioRecordConfig);

    _isRecording = true;
    _recordingSubscription = stream.listen(
      (data) {
        if (!_audioController.isClosed) {
          _audioController.add(Uint8List.fromList(data));
        }
      },
      onError: (Object error) {
        if (!_audioController.isClosed) {
          _audioController.addError(error);
        }
      },
      onDone: () {
        _isRecording = false;
        _recordingSubscription = null;
      },
    );
  }

  /// Stops recording and cancels the audio stream subscription.
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _recorder.stop();
  }

  /// Releases all resources. The service cannot be used after disposal.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await stopRecording();
    await _recorder.dispose();
    await _audioController.close();
  }

  void _assertNotDisposed() {
    if (_isDisposed) {
      throw StateError('AudioRecorderService has been disposed');
    }
  }
}
