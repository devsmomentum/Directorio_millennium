import 'package:flutter/material.dart';
import '../models/map_route.dart';

class RoutePointsPainter extends CustomPainter {
  final List<MapRoutePoint> points;
  final double animationValue;
  final Color routeColor;

  RoutePointsPainter({
    required this.points,
    this.animationValue = 1.0,
    this.routeColor = Colors.pinkAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || points.length < 2) return;

    final paint = Paint()
      ..color = routeColor
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = routeColor.withOpacity(0.3)
      ..strokeWidth = 16.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final path = Path();
    path.moveTo(points.first.x, points.first.y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }

    final pathMetrics = path.computeMetrics();
    final extractPath = Path();

    for (var metric in pathMetrics) {
      extractPath.addPath(
        metric.extractPath(0.0, metric.length * animationValue),
        Offset.zero,
      );
    }

    canvas.drawPath(extractPath, glowPaint);
    canvas.drawPath(extractPath, paint);
  }

  @override
  bool shouldRepaint(covariant RoutePointsPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.routeColor != routeColor;
  }
}
