import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioRecorderService {
  final _recorder = AudioRecorder();
  final _audioController = StreamController<Uint8List>.broadcast();
  bool _isRecording = false;

  Stream<Uint8List> get audioStream => _audioController.stream;
  bool get isRecording => _isRecording;

  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission not granted');
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _isRecording = true;
    stream.listen(
      (data) => _audioController.add(Uint8List.fromList(data)),
      onError: (Object error) => _audioController.addError(error),
      onDone: () => _isRecording = false,
    );
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    await _recorder.stop();
    _isRecording = false;
  }

  void dispose() {
    stopRecording();
    _recorder.dispose();
    _audioController.close();
  }
}
