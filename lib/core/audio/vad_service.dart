import 'dart:async';

import 'package:vad/vad.dart';

enum VadState { idle, listening, speechDetected, speechEnded }

class VadService {
  VadHandler? _handler;
  final _stateController = StreamController<VadState>.broadcast();
  final _speechController = StreamController<List<double>>.broadcast();
  VadState _state = VadState.idle;

  Stream<VadState> get stateChanges => _stateController.stream;
  Stream<List<double>> get speechFrames => _speechController.stream;
  VadState get state => _state;

  Future<void> initialize() async {
    _handler = VadHandler.create();

    _handler!.onSpeechStart.listen((_) {
      _setState(VadState.speechDetected);
    });

    _handler!.onSpeechEnd.listen((audioData) {
      _speechController.add(audioData);
      _setState(VadState.speechEnded);
    });

    _handler!.onError.listen((error) {
      _setState(VadState.idle);
    });
  }

  Future<void> startListening() async {
    if (_handler == null) {
      throw StateError('VAD not initialized');
    }
    await _handler!.startListening(
      positiveSpeechThreshold: 0.8,
      negativeSpeechThreshold: 0.35,
      minSpeechFrames: 5,
      redemptionFrames: 8,
      preSpeechPadFrames: 3,
    );
    _setState(VadState.listening);
  }

  Future<void> stopListening() async {
    await _handler?.stopListening();
    _setState(VadState.idle);
  }

  void _setState(VadState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _handler?.dispose();
    _stateController.close();
    _speechController.close();
  }
}
