import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/ride.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// What the driver sees on the dashboard once they've accepted a ride.
/// Two-step terminal flow:
///   accepted     → "Passenger onboard"  → in_transit
///   in_transit   → "Complete ride"      → completed
///   either state → "Cancel ride"        → cancelled (with confirm)
///
/// The widget itself is dumb — it owns no Firestore state, only UI.
class DriverActiveRideView extends ConsumerStatefulWidget {
  final Ride ride;
  const DriverActiveRideView({super.key, required this.ride});

  @override
  ConsumerState<DriverActiveRideView> createState() =>
      _DriverActiveRideViewState();
}

class _DriverActiveRideViewState extends ConsumerState<DriverActiveRideView> {
  bool _busy = false;

  Future<void> _markOnboard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .markPassengerOnboard(widget.ride.id);
      // No toast on success — the UI swap from "Passenger onboard"
      // to "Complete ride" is the visible feedback.
    } catch (e) {
      if (!mounted) return;
      _toast('Could not start trip: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .completeRide(widget.ride.id);
      if (!mounted) return;
      _toast('Ride completed. Nice work.', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      _toast('Could not complete ride: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'The commuter will be notified. This counts against the cancellation rate shown on the admin dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep ride'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .driverCancelRide(widget.ride.id);
      if (!mounted) return;
      _toast('Ride cancelled.', AppColors.muted);
    } catch (e) {
      if (!mounted) return;
      _toast('Could not cancel ride: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color.withValues(alpha: 0.9),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final inTransit = ride.status == RideStatus.inTransit;

    final headerTitle = inTransit ? 'Passenger onboard' : 'Ride in progress';
    final headerHint = inTransit
        ? 'Drive to the dropoff, then complete the ride.'
        : 'Drive to the pickup, then mark passenger onboard.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  inTransit ? LucideIcons.userCheck : LucideIcons.car,
                  size: 22,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headerHint,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _routeRow(
            LucideIcons.circleDot,
            ride.pickup,
            // Once onboard, dim the pickup row — it's already done.
            inTransit ? AppColors.muted : AppColors.accent,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Container(
              width: 2,
              height: 18,
              color: AppColors.muted.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 6),
          _routeRow(LucideIcons.flag, ride.dropoff, AppColors.success),
          if (ride.commuter.isNotEmpty || ride.commuterPhone.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.surfaceAlt, height: 1),
            const SizedBox(height: 12),
            if (ride.commuter.isNotEmpty)
              _metaRow(LucideIcons.user, ride.commuter),
            if (ride.commuterPhone.isNotEmpty) ...[
              const SizedBox(height: 6),
              _metaRow(LucideIcons.phone, ride.commuterPhone),
            ],
          ],
          if (ride.notes != null && ride.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _metaRow(LucideIcons.fileText, ride.notes!),
          ],
          const SizedBox(height: 18),
          if (inTransit)
            PrimaryButton(
              label: 'Complete ride',
              icon: LucideIcons.checkCheck,
              busy: _busy,
              onPressed: _complete,
            )
          else
            PrimaryButton(
              label: 'Passenger onboard',
              icon: LucideIcons.userPlus,
              busy: _busy,
              onPressed: _markOnboard,
            ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Cancel ride',
            icon: LucideIcons.x,
            color: AppColors.danger,
            onPressed: _busy ? null : _cancel,
          ),
        ],
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

  Widget _metaRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
