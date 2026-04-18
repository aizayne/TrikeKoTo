import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/driver.dart';
import '../../models/ride.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rides_provider.dart';
import '../../widgets/primary_button.dart';

/// Phase 4 of the commuter flow: the ride is accepted and we now show
/// a live map tracking the assigned driver until they arrive.
///
/// Three live data sources are stitched together:
///   1. The ride doc itself — for status transitions, pickup/dropoff
///      strings, and the snapshot of `driverLocation` taken at accept
///      time (used to seed the map before the live stream arrives).
///   2. `active_drivers/{driverEmail}.location` — the live GPS feed.
///   3. `drivers/{driverEmail}` — the driver profile for the info card.
///
/// The map intentionally uses OpenStreetMap tiles + flutter_map so the
/// app stays free of API-key obligations for the thesis demo.
class CommuterAcceptedView extends ConsumerStatefulWidget {
  final String rideId;
  const CommuterAcceptedView({super.key, required this.rideId});

  @override
  ConsumerState<CommuterAcceptedView> createState() =>
      _CommuterAcceptedViewState();
}

class _CommuterAcceptedViewState extends ConsumerState<CommuterAcceptedView> {
  final MapController _mapController = MapController();

  /// Last LatLng we panned the map to. Used to skip redundant move()
  /// calls when the same coords come through twice (Firestore can emit
  /// duplicate snapshots when other unrelated fields change).
  LatLng? _lastPannedTo;

  bool _cancelling = false;

  /// Default fallback — Balaybay Resettlement. Only used until either
  /// the seeded driverLocation or the first live coord arrives.
  static final LatLng _fallbackCenter =
      LatLng(AppConstants.balaybayLat, AppConstants.balaybayLng);

  Future<void> _confirmCancel() async {
    if (_cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'The driver is already on the way. Cancelling now will stop '
          'them from picking you up.',
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

    setState(() => _cancelling = true);
    try {
      await ref.read(firestoreServiceProvider).cancelRide(widget.rideId);
      // The parent screen's ride listener will catch the status change
      // and bounce us back to the booking form — nothing else to do.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not cancel: $e'),
          backgroundColor: AppColors.danger.withValues(alpha: 0.9),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  /// Pan the map only when the coords actually change — avoids the
  /// jittery feel of repeated `move()` calls on duplicate snapshots.
  void _maybePan(LatLng next) {
    final last = _lastPannedTo;
    if (last != null && last.latitude == next.latitude && last.longitude == next.longitude) {
      return;
    }
    _lastPannedTo = next;
    // flutter_map 7.x has no built-in tween; the React reference uses
    // a 0.8s panTo. An instant move feels close enough at this zoom and
    // keeps the dependency surface small.
    _mapController.move(next, _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideStreamProvider(widget.rideId));

    return rideAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Could not load ride: $e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      ),
      data: (ride) => _AcceptedBody(
        ride: ride,
        mapController: _mapController,
        fallbackCenter: _fallbackCenter,
        cancelling: _cancelling,
        onCancel: _confirmCancel,
        onLiveCoords: _maybePan,
      ),
    );
  }
}

/// Pulled out so the map + listeners can rebuild based on the latest
/// ride snapshot without recreating the [MapController]. The controller
/// must outlive these rebuilds so that programmatic moves during a
/// pan animation aren't lost.
class _AcceptedBody extends ConsumerWidget {
  final Ride ride;
  final MapController mapController;
  final LatLng fallbackCenter;
  final bool cancelling;
  final Future<void> Function() onCancel;
  final void Function(LatLng) onLiveCoords;

  const _AcceptedBody({
    required this.ride,
    required this.mapController,
    required this.fallbackCenter,
    required this.cancelling,
    required this.onCancel,
    required this.onLiveCoords,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driverEmail = ride.assignedDriver;

    // Seed: prefer the live stream, fall back to the snapshot stored on
    // the ride at accept time, finally fall back to the village centre.
    final liveLoc = driverEmail == null
        ? const AsyncValue<GeoCoords?>.data(null)
        : ref.watch(driverLiveLocationProvider(driverEmail));
    final seeded = ride.driverLocation;

    final liveCoords = liveLoc.valueOrNull;
    final mapCoords = liveCoords ?? seeded;
    final hasGps = mapCoords != null;
    final mapCenter = mapCoords == null
        ? fallbackCenter
        : LatLng(mapCoords.lat, mapCoords.lng);

    // React to the live stream by panning the map. We do this in build
    // via ref.listen so the controller stays a single instance.
    if (driverEmail != null) {
      ref.listen<AsyncValue<GeoCoords?>>(
        driverLiveLocationProvider(driverEmail),
        (_, next) {
          final c = next.valueOrNull;
          if (c == null) return;
          onLiveCoords(LatLng(c.lat, c.lng));
        },
      );
    }

    final driverAsync = driverEmail == null
        ? const AsyncValue<Driver?>.data(null)
        : ref.watch(driverProfileProvider(driverEmail));

    final pickupCoords = ride.pickupCoords;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 280,
            child: hasGps
                ? FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: mapCenter,
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.doubleTapZoom,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.trikekoto.app',
                      ),
                      MarkerLayer(
                        markers: [
                          if (pickupCoords != null)
                            Marker(
                              point:
                                  LatLng(pickupCoords.lat, pickupCoords.lng),
                              width: 36,
                              height: 36,
                              child: const _PickupMarker(),
                            ),
                          Marker(
                            point: mapCenter,
                            width: 44,
                            height: 44,
                            child: const _TrikeMarker(),
                          ),
                        ],
                      ),
                    ],
                  )
                : const _MapPlaceholder(),
          ),
        ),
        const SizedBox(height: 16),
        const _HeaderRow(),
        const SizedBox(height: 12),
        _DriverInfoCard(driverAsync: driverAsync),
        const SizedBox(height: 12),
        _RouteSummary(
          pickup: ride.pickup,
          dropoff: ride.dropoff,
          notes: ride.notes,
        ),
        const SizedBox(height: 18),
        SecondaryButton(
          label: 'Cancel ride',
          icon: LucideIcons.x,
          color: AppColors.danger,
          onPressed: cancelling ? null : onCancel,
        ),
        const SizedBox(height: 8),
        if (cancelling)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Live map updates as the driver moves toward you.\n'
            'You will be returned home automatically once the ride completes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Driver is on the way!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Your trike is heading to your pickup point.',
                style: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.9),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.dot, size: 14, color: AppColors.success),
              SizedBox(width: 4),
              Text(
                'LIVE',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  final AsyncValue<Driver?> driverAsync;
  const _DriverInfoCard({required this.driverAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: driverAsync.when(
        loading: () => const _LoadingDriverRow(),
        error: (_, _) => const Text(
          'Driver details unavailable.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        data: (driver) {
          if (driver == null) {
            return const Text(
              'Loading driver details…',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR DRIVER',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _InfoColumn(
                      icon: LucideIcons.user,
                      label: 'Name',
                      value: driver.fullName.isEmpty
                          ? driver.email
                          : driver.fullName,
                    ),
                  ),
                  Expanded(
                    child: _InfoColumn(
                      icon: LucideIcons.car,
                      label: 'Plate',
                      value: driver.plateNumber.isEmpty
                          ? '—'
                          : driver.plateNumber,
                    ),
                  ),
                ],
              ),
              if (driver.phone.isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoColumn(
                  icon: LucideIcons.phone,
                  label: 'Phone',
                  value: driver.phone,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LoadingDriverRow extends StatelessWidget {
  const _LoadingDriverRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text(
          'Loading driver details…',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoColumn({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final String pickup;
  final String dropoff;
  final String? notes;

  const _RouteSummary({
    required this.pickup,
    required this.dropoff,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RouteRow(
            icon: LucideIcons.circleDot,
            color: AppColors.accent,
            text: pickup.isEmpty ? '—' : pickup,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
            child: Container(
              width: 2,
              height: 14,
              color: AppColors.muted.withValues(alpha: 0.4),
            ),
          ),
          _RouteRow(
            icon: LucideIcons.flag,
            color: AppColors.success,
            text: dropoff.isEmpty ? '—' : dropoff,
          ),
          if (notes != null && notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: AppColors.surfaceAlt, height: 1),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.fileText,
                    size: 13, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notes!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
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

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 10),
          Text(
            'Waiting for driver GPS…',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TrikeMarker extends StatelessWidget {
  const _TrikeMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(LucideIcons.car, size: 22, color: Colors.black),
    );
  }
}

class _PickupMarker extends StatelessWidget {
  const _PickupMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.info,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(LucideIcons.mapPin, size: 16, color: Colors.white),
    );
  }
}
