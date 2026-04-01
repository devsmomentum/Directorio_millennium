import 'package:flutter/material.dart';
import 'dart:ui';
import '../models/map_node.dart';

class RoutePainter extends CustomPainter {
  final List<MapNode> route;
  final double animationValue; // 🆕 Valor de progreso (0.0 a 1.0)

  RoutePainter({required this.route, this.animationValue = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty || route.length < 2) return;

    final paint = Paint()
      ..color = Colors.pinkAccent
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Efecto de brillo (Neón)
    final glowPaint = Paint()
      ..color = Colors.pinkAccent.withOpacity(0.3)
      ..strokeWidth = 16.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // 1. Construir el Path completo
    final path = Path();
    path.moveTo(route.first.x, route.first.y);
    for (int i = 1; i < route.length; i++) {
      path.lineTo(route[i].x, route[i].y);
    }

    // 2. Extraer solo el fragmento según la animación
    final pathMetrics = path.computeMetrics();
    final extractPath = Path();

    for (var metric in pathMetrics) {
      extractPath.addPath(
        metric.extractPath(0.0, metric.length * animationValue),
        Offset.zero,
      );
    }

    // 3. Dibujar
    canvas.drawPath(extractPath, glowPaint);
    canvas.drawPath(extractPath, paint);
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.animationValue != animationValue;
  }
}
