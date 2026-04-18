import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme.dart';
import '../widgets/primary_button.dart';

/// Stub for screens that will be filled in by later build steps
/// (commuter booking, driver dashboard, admin panel, feedback, …).
/// Keeps the router compilable while we work through the steps in
/// order so we can hot-reload and iterate without dead links.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String? note;

  const PlaceholderScreen({
    super.key,
    required this.title,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.construction,
                  size: 56, color: AppColors.muted),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                note ?? 'This screen is coming in a later build step.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Back to home',
                icon: LucideIcons.arrowLeft,
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
