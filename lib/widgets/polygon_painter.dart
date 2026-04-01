import 'package:flutter/material.dart';
import '../models/map_polygon.dart';

class PolygonHighlightPainter extends CustomPainter {
  final MapPolygon polygon;
  final Color fillColor;
  final Color borderColor;
  final double pulseValue; // 0.0 a 1.0 para animación de pulso

  PolygonHighlightPainter({
    required this.polygon,
    required this.fillColor,
    required this.borderColor,
    this.pulseValue = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.points.length < 3) return;

    final path = Path();
    path.moveTo(polygon.points.first.x, polygon.points.first.y);
    for (int i = 1; i < polygon.points.length; i++) {
      path.lineTo(polygon.points[i].x, polygon.points[i].y);
    }
    path.close();

    // Relleno con opacidad pulsante
    final fillPaint = Paint()
      ..color = fillColor.withAlpha((fillColor.alpha * (0.15 + 0.15 * pulseValue)).round())
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Glow del borde
    final glowPaint = Paint()
      ..color = borderColor.withAlpha((borderColor.alpha * 0.3 * pulseValue).round())
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, glowPaint);

    // Borde sólido
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant PolygonHighlightPainter oldDelegate) {
    return oldDelegate.polygon != polygon ||
        oldDelegate.pulseValue != pulseValue;
  }
}
