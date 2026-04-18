import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme.dart';
import '../services/matching_service.dart';
import 'primary_button.dart';

/// One offered-ride card. Shows pickup/dropoff, distance to pickup,
/// the driver's current rank in the deterministic offer order, and an
/// Accept button. The Ignore action is also exposed for the React
/// parity (drivers can dismiss a ride they don't want to chase).
class IncomingRideCard extends StatelessWidget {
  final OfferedRide offered;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const IncomingRideCard({
    super.key,
    required this.offered,
    required this.busy,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final ride = offered.ride;
    final isTopOffer = offered.myRank == 0;
    final priorityColor =
        isTopOffer ? AppColors.success : AppColors.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: priorityColor.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTopOffer ? LucideIcons.zap : LucideIcons.bell,
                        size: 12,
                        color: priorityColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        offered.myRank < 0
                            ? 'New ride'
                            : isTopOffer
                                ? 'Top offer'
                                : 'Rank #${offered.myRank + 1}',
                        style: TextStyle(
                          color: priorityColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (offered.distanceKm != null)
                  Row(
                    children: [
                      const Icon(LucideIcons.mapPin,
                          size: 12, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        '${offered.distanceKm!.toStringAsFixed(1)} km away',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _routeRow(LucideIcons.circleDot, ride.pickup, AppColors.accent),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 9),
              child: Container(
                width: 2,
                height: 16,
                color: AppColors.muted.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 6),
            _routeRow(LucideIcons.flag, ride.dropoff, AppColors.success),
            if (ride.notes != null && ride.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.fileText,
                        size: 13, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ride.notes!,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (ride.commuter.isNotEmpty)
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(LucideIcons.user,
                            size: 12, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ride.commuter,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (ride.commuterPhone.isNotEmpty)
                  Row(
                    children: [
                      const Icon(LucideIcons.phone,
                          size: 12, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(
                        ride.commuterPhone,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: SecondaryButton(
                    label: 'Ignore',
                    icon: LucideIcons.x,
                    color: AppColors.muted,
                    onPressed: busy ? null : onIgnore,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: 'Accept',
                    icon: LucideIcons.check,
                    busy: busy,
                    onPressed: onAccept,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                offered.totalRanked <= 1
                    ? 'You are the only nearby driver.'
                    : 'Offered to ${offered.offerDepth} of ${offered.totalRanked} nearby drivers',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            style: const TextStyle(fontSize: 14, color: AppColors.text),
          ),
        ),
      ],
    );
  }
}
