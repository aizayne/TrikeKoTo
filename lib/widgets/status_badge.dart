import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Small pill that color-codes a status string. Used everywhere a ride
/// or driver status appears — keeps the colour mapping consistent.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Convenience constructors for the four ride statuses.
  factory StatusBadge.searching() =>
      const StatusBadge(label: 'SEARCHING', color: AppColors.warning);
  factory StatusBadge.accepted() =>
      const StatusBadge(label: 'IN PROGRESS', color: AppColors.info);
  factory StatusBadge.completed() =>
      const StatusBadge(label: 'COMPLETED', color: AppColors.success);
  factory StatusBadge.cancelled() =>
      const StatusBadge(label: 'CANCELLED', color: AppColors.danger);
}
