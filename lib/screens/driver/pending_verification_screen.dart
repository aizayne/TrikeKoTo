import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/primary_button.dart';

/// Shown after a driver registers OR signs in with a still-pending
/// account. The user is signed out before landing here so they cannot
/// reach driver-only routes via direct navigation.
class PendingVerificationScreen extends StatelessWidget {
  const PendingVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.clock,
                    size: 56, color: AppColors.warning),
              ),
              const SizedBox(height: 20),
              const Text(
                'Account Under Review',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "Thanks for signing up! An administrator will verify your details shortly. You'll be able to sign in once your account is approved.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Back to home',
                icon: LucideIcons.arrowLeft,
                onPressed: () => context.go('/'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
