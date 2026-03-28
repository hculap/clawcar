import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Concentric rings that pulse outward while the mic is in listening state.
/// Each ring fades and scales up on a staggered offset from a shared
/// repeating animation controller.
class PulseRings extends StatefulWidget {
  final Color color;
  final double size;
  final int ringCount;

  const PulseRings({
    super.key,
    required this.color,
    this.size = 240,
    this.ringCount = 3,
  });

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
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
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _PulseRingsPainter(
              progress: _controller.value,
              color: widget.color,
              ringCount: widget.ringCount,
            ),
          );
        },
      ),
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int ringCount;

  _PulseRingsPainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    for (var i = 0; i < ringCount; i++) {
      final stagger = i / ringCount;
      final ringProgress = (progress + stagger) % 1.0;

      // Scale from 40% to 100% of max radius
      final radius = maxRadius * (0.4 + 0.6 * ringProgress);

      // Fade out as ring expands
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0) * 0.4;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingsPainter old) =>
      old.progress != progress || old.color != color;
}
