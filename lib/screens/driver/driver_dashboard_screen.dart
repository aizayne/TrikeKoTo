import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/driver.dart';
import '../../models/ride.dart';
import '../../providers/auth_provider.dart';
import '../../providers/presence_provider.dart';
import '../../providers/rides_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/matching_service.dart';
import '../../widgets/incoming_ride_card.dart';
import '../../widgets/status_badge.dart';
import 'driver_active_ride_view.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() =>
      _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen> {
  /// rideId currently being accepted — disables the card to prevent
  /// double-taps while the Firestore transaction is in flight.
  String? _acceptingRideId;

  /// rideIds the driver has dismissed locally. Mirrors the React UX:
  /// "ignored" rides stay hidden until the driver leaves the screen.
  /// Also used as the silent fallback when an accept loses the race.
  final Set<String> _ignoredIds = <String>{};

  Future<void> _signOut() async {
    // Make sure we go offline FIRST so the active_drivers doc reflects
    // the truth before the user loses Auth credentials.
    await ref.read(presenceProvider.notifier).goOffline();
    await ref.read(authServiceProvider).signOut();
    if (mounted) context.go('/');
  }

  Future<void> _accept(OfferedRide offered) async {
    if (_acceptingRideId != null) return;
    final ride = offered.ride;
    final email = ref.read(authServiceProvider).currentEmail;
    if (email == null) return;

    final pos = ref.read(presenceProvider).lastPosition;
    final driverLoc = pos == null
        ? null
        : (lat: pos.latitude, lng: pos.longitude);

    setState(() => _acceptingRideId = ride.id);
    try {
      await ref.read(firestoreServiceProvider).acceptRide(
            rideId: ride.id,
            driverEmail: email,
            driverLocation: driverLoc,
          );
      // Acceptance succeeded — the activeRideForDriverProvider stream
      // will flip and the UI will swap to the in-progress view on its
      // own. No toast needed; the visible state change is the feedback.
    } on RideAcceptanceException catch (_) {
      // Lost the race or ride disappeared. Silently hide the card.
      if (!mounted) return;
      setState(() => _ignoredIds.add(ride.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not accept ride: $e'),
          backgroundColor: AppColors.danger.withValues(alpha: 0.9),
        ),
      );
    } finally {
      if (mounted) setState(() => _acceptingRideId = null);
    }
  }

  void _ignore(OfferedRide offered) {
    setState(() => _ignoredIds.add(offered.ride.id));
  }

  @override
  Widget build(BuildContext context) {
    final driverAsync = ref.watch(currentDriverProvider);
    final presence = ref.watch(presenceProvider);
    final activeRide = ref.watch(activeRideForDriverProvider).valueOrNull;
    final incoming = ref
        .watch(incomingRidesProvider)
        .where((o) => !_ignoredIds.contains(o.ride.id))
        .toList();
    final upcoming = ref.watch(upcomingScheduledRidesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TrikeKoTo Driver',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          if (presence.isOnline)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: StatusBadge(
                  label: 'ONLINE',
                  color: AppColors.success,
                  icon: LucideIcons.dot,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(LucideIcons.user),
            tooltip: 'Profile',
            onPressed: () => context.go('/driver/profile'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.history),
            tooltip: 'Ride history',
            onPressed: () => context.go('/driver/history'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.logOut),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DriverHeaderCard(driverAsync: driverAsync),
            const SizedBox(height: 12),
            _OnlineToggleCard(presence: presence),
            if (presence.error != null) ...[
              const SizedBox(height: 12),
              _PermissionBanner(state: presence),
            ],
            const SizedBox(height: 24),
            _SectionTitle(
              icon: activeRide != null
                  ? LucideIcons.car
                  : LucideIcons.bell,
              title: activeRide != null ? 'Active ride' : 'Incoming rides',
              hint: activeRide != null
                  ? null
                  : presence.isOnline
                      ? (incoming.isEmpty
                          ? 'No nearby pickups yet — keep this screen open.'
                          : null)
                      : 'Go online to start receiving ride requests.',
            ),
            const SizedBox(height: 8),
            _IncomingSection(
              activeRide: activeRide,
              isOnline: presence.isOnline,
              starting: presence.starting,
              incoming: incoming,
              acceptingRideId: _acceptingRideId,
              onAccept: _accept,
              onIgnore: _ignore,
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              icon: LucideIcons.calendar,
              title: 'Upcoming scheduled rides',
              hint: upcoming.isEmpty
                  ? 'Scheduled rides within 15 minutes appear in the list above.'
                  : null,
            ),
            const SizedBox(height: 8),
            _UpcomingScheduledList(rides: upcoming),
            const SizedBox(height: 24),
            const _OnlineHintFooter(),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Header card with driver name + plate
// ──────────────────────────────────────────────────────────────────────────

class _DriverHeaderCard extends StatelessWidget {
  final AsyncValue<Driver?> driverAsync;
  const _DriverHeaderCard({required this.driverAsync});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: driverAsync.when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(
            'Could not load profile: $e',
            style: const TextStyle(color: AppColors.danger),
          ),
          data: (driver) {
            if (driver == null) {
              return const Text(
                'No profile found.',
                style: TextStyle(color: AppColors.muted),
              );
            }
            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.car,
                      color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.fullName.isEmpty
                            ? driver.email
                            : driver.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Plate ${driver.plateNumber}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Online / offline toggle card
// ──────────────────────────────────────────────────────────────────────────

class _OnlineToggleCard extends ConsumerWidget {
  final PresenceState presence;
  const _OnlineToggleCard({required this.presence});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = presence.isOnline;
    final color = online ? AppColors.success : AppColors.muted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    online ? LucideIcons.zap : LucideIcons.zapOff,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        online ? "You're online" : "You're offline",
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        online
                            ? 'Listening for nearby ride requests.'
                            : 'Tap below to start accepting rides.',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: online,
                  activeThumbColor: AppColors.success,
                  onChanged: presence.starting
                      ? null
                      : (v) {
                          final notifier =
                              ref.read(presenceProvider.notifier);
                          v ? notifier.goOnline() : notifier.goOffline();
                        },
                ),
              ],
            ),
            if (presence.starting) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surfaceAlt,
                minHeight: 3,
              ),
              const SizedBox(height: 8),
              const Text(
                'Getting your location…',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
            if (online && presence.lastPosition != null) ...[
              const SizedBox(height: 12),
              _CoordsRow(
                lat: presence.lastPosition!.latitude,
                lng: presence.lastPosition!.longitude,
                accuracyM: presence.lastPosition!.accuracy,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoordsRow extends StatelessWidget {
  final double lat;
  final double lng;
  final double accuracyM;
  const _CoordsRow({
    required this.lat,
    required this.lng,
    required this.accuracyM,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.mapPin, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}  •  ±${accuracyM.toStringAsFixed(0)}m',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Permission / error banner
// ──────────────────────────────────────────────────────────────────────────

class _PermissionBanner extends ConsumerWidget {
  final PresenceState state;
  const _PermissionBanner({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perm = state.permission;
    final loc = ref.read(locationServiceProvider);

    VoidCallback? action;
    String? actionLabel;

    if (perm == LocationPermissionResult.serviceDisabled) {
      action = loc.openLocationSettings;
      actionLabel = 'Open location settings';
    } else if (perm == LocationPermissionResult.deniedForever) {
      action = loc.openAppSettings;
      actionLabel = 'Open app settings';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.alertTriangle,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.error ?? 'Location is required.',
                  style: const TextStyle(color: AppColors.text, fontSize: 13),
                ),
                if (action != null && actionLabel != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: action,
                    icon: const Icon(LucideIcons.settings, size: 14),
                    label: Text(actionLabel),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Incoming-rides region: chooses between active-ride view, list of
// IncomingRideCards, or an empty-state placeholder. Keeping the
// branching here keeps the build() method above readable.
// ──────────────────────────────────────────────────────────────────────────

class _IncomingSection extends StatelessWidget {
  final Ride? activeRide;
  final bool isOnline;
  final bool starting;
  final List<OfferedRide> incoming;
  final String? acceptingRideId;
  final void Function(OfferedRide) onAccept;
  final void Function(OfferedRide) onIgnore;

  const _IncomingSection({
    required this.activeRide,
    required this.isOnline,
    required this.starting,
    required this.incoming,
    required this.acceptingRideId,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    if (activeRide != null) {
      return DriverActiveRideView(ride: activeRide!);
    }
    if (!isOnline) {
      return const _PlaceholderPanel(
        icon: LucideIcons.zapOff,
        text:
            "You're offline.\nFlip the switch above to start receiving rides.",
      );
    }
    if (incoming.isEmpty) {
      return _PlaceholderPanel(
        icon: starting ? LucideIcons.loader : LucideIcons.inbox,
        text: starting
            ? 'Getting your first location fix…'
            : 'No nearby ride requests right now.\nWe will keep listening.',
      );
    }
    return Column(
      children: [
        for (final offered in incoming)
          IncomingRideCard(
            offered: offered,
            busy: acceptingRideId == offered.ride.id,
            onAccept: () => onAccept(offered),
            onIgnore: () => onIgnore(offered),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Upcoming scheduled rides — read-only glance-ahead list
// ──────────────────────────────────────────────────────────────────────────

class _UpcomingScheduledList extends StatelessWidget {
  final List<Ride> rides;
  const _UpcomingScheduledList({required this.rides});

  @override
  Widget build(BuildContext context) {
    if (rides.isEmpty) {
      return const _PlaceholderPanel(
        icon: LucideIcons.calendarClock,
        text: 'No scheduled rides on the horizon.',
      );
    }
    return Column(
      children: [
        for (final r in rides) _ScheduledRideTile(ride: r),
      ],
    );
  }
}

class _ScheduledRideTile extends StatelessWidget {
  final Ride ride;
  const _ScheduledRideTile({required this.ride});

  @override
  Widget build(BuildContext context) {
    final when = ride.scheduledFor;
    final whenLabel = when == null
        ? '—'
        : DateFormat('EEE, MMM d • h:mm a').format(when);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.calendarClock,
                size: 16, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  whenLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ride.pickup.isEmpty ? '—' : ride.pickup}  →  ${ride.dropoff.isEmpty ? '—' : ride.dropoff}',
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Section helpers
// ──────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  const _SectionTitle({required this.icon, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.muted),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PlaceholderPanel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.muted, size: 28),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _OnlineHintFooter extends StatelessWidget {
  const _OnlineHintFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Keep this screen open while online —\nbackground tracking is disabled by design.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.muted.withValues(alpha: 0.7),
          fontSize: 11,
        ),
      ),
    );
  }
}
