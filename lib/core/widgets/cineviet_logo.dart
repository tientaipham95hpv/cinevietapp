import 'package:flutter/material.dart';

import '../theme/cineviet_colors.dart';
import '../theme/cineviet_dimensions.dart';

class CineVietLogo extends StatelessWidget {
  const CineVietLogo({super.key, this.size = 56, this.showText = true});

  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _CineVietLogoPainter(),
        isComplex: false,
        willChange: false,
      ),
    );
    if (!showText) return icon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        SizedBox(width: CineVietSpacing.md),
        const Text(
          'CineViet',
          style: TextStyle(
            color: CineVietColors.accent,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _CineVietLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = shortest * 0.42;

    final bgRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(shortest * 0.22),
    );
    canvas.drawRRect(bgRect, Paint()..color = CineVietColors.bg2);

    final glowPaint = Paint()
      ..color = CineVietColors.accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.16
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius * 0.86, glowPaint);

    final ringPaint = Paint()
      ..color = CineVietColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.075
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius * 0.86, ringPaint);

    final play = Path()
      ..moveTo(center.dx - shortest * 0.10, center.dy - shortest * 0.19)
      ..lineTo(center.dx - shortest * 0.10, center.dy + shortest * 0.19)
      ..lineTo(center.dx + shortest * 0.23, center.dy)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = CineVietColors.accent
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _CineVietLogoPainter oldDelegate) => false;
}
