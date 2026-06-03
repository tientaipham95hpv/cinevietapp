import 'package:flutter/material.dart';
import '../about/about_screen.dart';

/// Kept as a compatibility wrapper for any stale route/import.
/// Phase 10 no longer includes movie/new-episode notification inbox.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => const AboutScreen();
}
