import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// NeuroSense app mark from the mobile design: a rounded square with a white
/// circular "brain halves" symbol. TEMPORARY drawing until the real logo file arrives.
class NeuroLogo extends StatelessWidget {
  const NeuroLogo({super.key, this.size = 56, this.onDark = false, this.color});

  final double size;

  /// On dark backgrounds the tile is blue; otherwise navy.
  final bool onDark;

  /// Overrides the tile colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'NeuroSense logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? (onDark ? AppColors.primary : AppColors.navyCard),
          borderRadius: BorderRadius.circular(size * 0.26),
        ),
        alignment: Alignment.center,
        child: CustomPaint(size: Size.square(size * 0.5), painter: const _MarkPainter()),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round;
    final c = Offset(s / 2, s / 2);
    canvas.drawCircle(c, s * 0.46, stroke);
    // Two hemispheres as facing arcs, and the midline.
    final left = Rect.fromCenter(center: Offset(s * 0.40, s * 0.47), width: s * 0.30, height: s * 0.50);
    final right = Rect.fromCenter(center: Offset(s * 0.60, s * 0.47), width: s * 0.30, height: s * 0.50);
    canvas.drawArc(left, math.pi * 0.55, math.pi * 0.95, false, stroke);
    canvas.drawArc(right, -math.pi * 0.5, math.pi * 0.95, false, stroke);
    canvas.drawLine(Offset(s / 2, s * 0.62), Offset(s / 2, s * 0.92), stroke);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => false;
}

/// Logo + serif "NeuroSense" word mark.
class NeuroWordmark extends StatelessWidget {
  const NeuroWordmark({super.key, this.onDark = false, this.logoSize = 64});

  final bool onDark;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeuroLogo(size: logoSize, onDark: onDark),
        const SizedBox(height: 16),
        Text(
          'NeuroSense',
          style: TextStyle(
            fontFamily: AppTextStyles.serif,
            fontSize: logoSize * 0.6,
            fontWeight: FontWeight.w700,
            color: onDark ? Colors.white : AppColors.navy,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'AI-ASSISTED MRI ANALYSIS',
          style: AppTextStyles.overline.copyWith(
            fontSize: 13,
            letterSpacing: 2.4,
            color: onDark ? AppColors.onNavyAccent : AppColors.primary,
          ),
        ),
      ],
    );
  }
}
