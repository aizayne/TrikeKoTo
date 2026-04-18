import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/primary_button.dart';

/// Confirmation view shown after creating a scheduled ride. The ride
/// stays in `searching` status until the matcher picks it up at
/// scheduledFor − 15 min; from the commuter's perspective that detail
/// is hidden — they just see "scheduled for X".
class CommuterScheduledView extends StatelessWidget {
  final String pickup;
  final String dropoff;
  final DateTime scheduledFor;
  final bool busy;
  final Future<void> Function() onCancel;

  const CommuterScheduledView({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.scheduledFor,
    required this.busy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE, MMM d • h:mm a').format(scheduledFor);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.calendarCheck,
                size: 56, color: AppColors.violet),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ride scheduled',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            fmt,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            "We'll start matching ${_leadCopy(scheduledFor)} before pickup.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row(LucideIcons.circleDot, pickup, AppColors.accent),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 9),
                    child: Container(
                      width: 2,
                      height: 18,
                      color: AppColors.muted.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _row(LucideIcons.flag, dropoff, AppColors.success),
                ],
              ),
            ),
          ),
          const Spacer(),
          SecondaryButton(
            label: 'Cancel scheduled ride',
            icon: LucideIcons.x,
            color: AppColors.danger,
            onPressed: busy ? null : onCancel,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _leadCopy(DateTime dt) {
    final until = dt.difference(DateTime.now());
    if (until.inMinutes <= 15) return 'momentarily';
    return '15 minutes';
  }

  Widget _row(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppColors.text),
          ),
        ),
      ],
    );
  }
}
