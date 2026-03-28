import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;
  Stream<PlayerState> get playerState => _player.playerStateStream;

  Future<void> playAudioBytes(Uint8List audioData, {String? mimeType}) async {
    _isPlaying = true;
    try {
      final source = _BytesAudioSource(audioData, mimeType: mimeType);
      await _player.setAudioSource(source);
      await _player.play();
    } finally {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

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
