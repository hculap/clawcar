import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

abstract class AudioPlayerBase {
  bool get isPlaying;
  Stream<dynamic> get playerState;
  Future<void> playAudioBytes(Uint8List audioData, {String? mimeType});
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  void dispose();
}

class AudioPlayerService implements AudioPlayerBase {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<PlayerState> get playerState => _player.playerStateStream;

  @override
  Future<void> playAudioBytes(Uint8List audioData, {String? mimeType}) async {
    _isPlaying = true;
    try {
      final source = _BytesAudioSource(audioData, mimeType: mimeType);
      await _player.setAudioSource(source);
      await _player.play();

      // Wait for playback to actually complete
      await _player.processingStateStream.firstWhere(
        (s) => s == ProcessingState.completed,
      );
    } finally {
      _isPlaying = false;
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    await _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
  }
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _data;
  final String? mimeType;

  _BytesAudioSource(this._data, {this.mimeType});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final effectiveStart = start ?? 0;
    final effectiveEnd = end ?? _data.length;

    return StreamAudioResponse(
      sourceLength: _data.length,
      contentLength: effectiveEnd - effectiveStart,
      offset: effectiveStart,
      stream: Stream.value(_data.sublist(effectiveStart, effectiveEnd)),
      contentType: mimeType ?? 'audio/mpeg',
    );
  }
}
