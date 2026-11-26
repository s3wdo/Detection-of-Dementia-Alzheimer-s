import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Faint line drawing of an axial brain outline behind the dark welcome
/// screen (decoration only — not an MRI image).
class BrainLinePainter extends CustomPainter {
  const BrainLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.12);
    final c = Offset(size.width * 0.52, size.height * 0.46);
    final r = size.width * 0.62;

    // Skull.
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 2.1, height: r * 2.4), paint);

    // Wavy cortex outline.
    final cortex = Path();
    for (var i = 0; i <= 360; i += 2) {
      final a = i * math.pi / 180;
      final wobble = 1 + 0.06 * math.sin(a * 22) + 0.03 * math.sin(a * 7);
      final p = Offset(c.dx + math.cos(a) * r * 0.86 * wobble, c.dy + math.sin(a) * r * 1.0 * wobble);
      i == 0 ? cortex.moveTo(p.dx, p.dy) : cortex.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(cortex, paint);

    // Ventricles and midline.
    canvas.drawArc(Rect.fromCenter(center: c.translate(-r * 0.12, 0), width: r * 0.36, height: r * 0.8), math.pi * 0.5,
        math.pi, false, paint);
    canvas.drawArc(Rect.fromCenter(center: c.translate(r * 0.12, 0), width: r * 0.36, height: r * 0.8), -math.pi * 0.5,
        math.pi, false, paint);
    canvas.drawLine(c.translate(0, -r * 0.95), c.translate(0, -r * 0.45), paint);
    canvas.drawLine(c.translate(0, r * 0.5), c.translate(0, r * 0.95), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
