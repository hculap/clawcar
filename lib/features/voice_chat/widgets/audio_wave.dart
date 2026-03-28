import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated waveform bars shown during the speaking state.
/// Each bar oscillates at a slightly different frequency to create
/// a natural audio-wave look.
class AudioWave extends StatefulWidget {
  final Color color;
  final double width;
  final double height;
  final int barCount;

  const AudioWave({
    super.key,
    required this.color,
    this.width = 200,
    this.height = 60,
    this.barCount = 5,
  });

  @override
  State<AudioWave> createState() => _AudioWaveState();
}

class _AudioWaveState extends State<AudioWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _AudioWavePainter(
              progress: _controller.value,
              color: widget.color,
              barCount: widget.barCount,
            ),
          );
        },
      ),
    );
  }
}

class _AudioWavePainter extends CustomPainter {
  final double progress;
  final Color color;
  final int barCount;

  _AudioWavePainter({
    required this.progress,
    required this.color,
    required this.barCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (barCount * 2 - 1);
    final maxBarHeight = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      // Each bar has a different phase offset for natural movement
      final phase = progress * 2 * math.pi + (i * math.pi / barCount * 2);
      final heightFraction = 0.3 + 0.7 * ((math.sin(phase) + 1) / 2);
      final barHeight = maxBarHeight * heightFraction;

      final x = i * barWidth * 2;
      final y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_AudioWavePainter old) =>
      old.progress != progress || old.color != color;
}
