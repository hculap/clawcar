import 'package:flutter/material.dart';

import '../../../core/audio/voice_pipeline.dart';
import 'pulse_rings.dart';

/// Large, animated microphone button that reflects the current pipeline state.
///
/// Touch target is always >= 80dp for safe in-car tapping.
/// Visual effects layer behind the button depending on state:
///   - idle: static glow ring
///   - listening: pulsing concentric rings
///   - processing: rotating arc spinner
///   - speaking: audio wave bars below the button
///   - error: muted styling with error icon
class MicButton extends StatelessWidget {
  final PipelineState state;
  final VoidCallback onPressed;

  /// Outer diameter of the button area (includes animation space).
  static const double outerSize = 240.0;

  /// Diameter of the tappable circle.
  static const double buttonSize = 120.0;

  const MicButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(state, context);

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background animation layer
          _buildBackgroundEffect(color),

          // Glow behind button
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            width: buttonSize + 24,
            height: buttonSize + 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: state == PipelineState.idle
                  ? []
                  : [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 32,
                        spreadRadius: 8,
                      ),
                    ],
            ),
          ),

          // Main button
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color, width: 3),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _iconFor(state),
                        key: ValueKey(state),
                        size: 48,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundEffect(Color color) {
    return switch (state) {
      PipelineState.listening => PulseRings(
          color: color,
          size: outerSize,
        ),
      PipelineState.processing => _ProcessingSpinner(color: color),
      _ => const SizedBox.shrink(),
    };
  }

  static Color _colorFor(PipelineState state, BuildContext context) {
    return switch (state) {
      PipelineState.idle => Theme.of(context).colorScheme.primary,
      PipelineState.listening => const Color(0xFFEF5350),
      PipelineState.processing => const Color(0xFFFFA726),
      PipelineState.speaking => const Color(0xFF66BB6A),
      PipelineState.error => Colors.grey,
    };
  }

  /// Expose color for external widgets (wave, status text) to stay in sync.
  static Color colorFor(PipelineState state, BuildContext context) =>
      _colorFor(state, context);

  static IconData _iconFor(PipelineState state) {
    return switch (state) {
      PipelineState.idle => Icons.mic_none_rounded,
      PipelineState.listening => Icons.mic_rounded,
      PipelineState.processing => Icons.hourglass_top_rounded,
      PipelineState.speaking => Icons.volume_up_rounded,
      PipelineState.error => Icons.mic_off_rounded,
    };
  }
}

/// Rotating arc spinner shown during the processing state.
class _ProcessingSpinner extends StatefulWidget {
  final Color color;

  const _ProcessingSpinner({required this.color});

  @override
  State<_ProcessingSpinner> createState() => _ProcessingSpinnerState();
}

class _ProcessingSpinnerState extends State<_ProcessingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
      width: MicButton.buttonSize + 40,
      height: MicButton.buttonSize + 40,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          painter: _ArcPainter(color: widget.color),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;

  _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Draw a 270-degree arc
    canvas.drawArc(rect.deflate(4), -0.5, 4.7, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}
