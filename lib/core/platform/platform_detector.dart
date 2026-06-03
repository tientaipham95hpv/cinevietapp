import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum CineVietPlatform { mobile, tablet, tv, desktop }

class PlatformInfo {
  const PlatformInfo({
    required this.type,
    required this.width,
    required this.height,
    required this.shortestDp,
    required this.dpr,
  });

  final CineVietPlatform type;
  final double width;
  final double height;
  final double shortestDp;
  final double dpr;

  bool get isMobile => type == CineVietPlatform.mobile;
  bool get isTablet => type == CineVietPlatform.tablet;
  bool get isTv => type == CineVietPlatform.tv;
  bool get isDesktop => type == CineVietPlatform.desktop;
}

class PlatformDetector {
  PlatformDetector._();

  static PlatformInfo of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final shortest = size.shortestSide;
    final dpr = mq.devicePixelRatio;
    final landscape = size.width > size.height;
    final directionalNav = mq.navigationMode == NavigationMode.directional;

    CineVietPlatform type;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      type = CineVietPlatform.desktop;
    } else if (shortest >= 600 ||
        (!kIsWeb && Platform.isIOS && shortest >= 370)) {
      // Netflix-style touch family: tablets stay tablet/touch-first.
      // Never classify 600dp+ touch tablets as TV from size alone.
      type = CineVietPlatform.tablet;
    } else if (!kIsWeb &&
        Platform.isAndroid &&
        landscape &&
        size.width >= 960 &&
        (directionalNav || shortest >= 300)) {
      // Android TV / TV box class.
      // Common TV boxes expose 1920x1080 as ~960x540dp, below the 600dp tablet breakpoint.
      // This catches TV boxes without stealing real tablets.
      type = CineVietPlatform.tv;
    } else if (size.width >= 1200) {
      type = CineVietPlatform.desktop;
    } else {
      type = CineVietPlatform.mobile;
    }

    return PlatformInfo(
      type: type,
      width: size.width,
      height: size.height,
      shortestDp: shortest,
      dpr: dpr,
    );
  }
}
