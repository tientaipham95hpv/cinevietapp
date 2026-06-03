import 'package:flutter/material.dart';

import '../theme/cineviet_colors.dart';
import '../theme/cineviet_dimensions.dart';

class CineVietLogo extends StatelessWidget {
  const CineVietLogo({super.key, this.size = 56, this.showText = true});

  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final icon = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/cineviet-icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
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
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}
