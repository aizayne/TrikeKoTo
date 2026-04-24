import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/ride.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rides_provider.dart';

/// Displays every ride assigned to the signed-in driver, sorted
/// newest-first. Mirrors the React reference at
/// `trikekoto-web/src/pages/RideHistory.jsx`:
///   • header with the driver's email
///   • stat cards (total / completed / cancelled)
///   • filter pills (All / Completed / Cancelled)
///   • a card per ride with status badge, route, and date
enum _HistoryFilter { all, completed, cancelled }

class DriverHistoryScreen extends ConsumerStatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  ConsumerState<DriverHistoryScreen> createState() =>
      _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends ConsumerState<DriverHistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authServiceProvider).currentEmail;
    final ridesAsync = ref.watch(myRidesHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/driver/dashboard'),
        ),
        title: const Text('Ride History'),
      ),
      body: SafeArea(
        child: ridesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
          error: (e, _) => _ErrorState(message: 'Could not load history: $e'),
          data: (rides) => _buildBody(email, rides),
        ),
      ),
    );
  }

  Widget _buildBody(String? email, List<Ride> rides) {
    // Tally on the unfiltered list so the stat cards reflect overall
    // history, not just the current view.
    var completed = 0;
    var cancelled = 0;
    for (final r in rides) {
      switch (r.status) {
        case RideStatus.completed:
          completed++;
        case RideStatus.cancelled:
          cancelled++;
        default:
          break;
      }
    }

    final filtered = switch (_filter) {
      _HistoryFilter.all => rides,
      _HistoryFilter.completed =>
        rides.where((r) => r.status == RideStatus.completed).toList(),
      _HistoryFilter.cancelled =>
        rides.where((r) => r.status == RideStatus.cancelled).toList(),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (email != null) _SubHeader(email: email),
        const SizedBox(height: 12),
        _StatRow(
          total: rides.length,
          completed: completed,
          cancelled: cancelled,
        ),
        const SizedBox(height: 16),
        _FilterRow(
          current: _filter,
          onChanged: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _EmptyState(hasAny: rides.isNotEmpty)
        else
          ...filtered.map((r) => _RideCard(ride: r)),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Sub-header — shows whose history this is
// ──────────────────────────────────────────────────────────────────────────

class _SubHeader extends StatelessWidget {
  final String email;
  const _SubHeader({required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.user, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            email,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Stat cards (Total / Completed / Cancelled)
// ──────────────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final int total;
  final int completed;
  final int cancelled;
  const _StatRow({
    required this.total,
    required this.completed,
    required this.cancelled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            value: total,
            label: 'Total',
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            value: completed,
            label: 'Completed',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            value: cancelled,
            label: 'Cancelled',
            color: AppColors.danger,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color == AppColors.muted ? AppColors.text : color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Filter pills
// ──────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final _HistoryFilter current;
  final ValueChanged<_HistoryFilter> onChanged;
  const _FilterRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.filter, size: 14, color: AppColors.muted),
        const SizedBox(width: 8),
        _pill('All', _HistoryFilter.all),
        const SizedBox(width: 6),
        _pill('Completed', _HistoryFilter.completed),
        const SizedBox(width: 6),
        _pill('Cancelled', _HistoryFilter.cancelled),
      ],
    );
  }

  Widget _pill(String label, _HistoryFilter value) {
    final active = current == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.surfaceAlt,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.accent : AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Single ride card
// ──────────────────────────────────────────────────────────────────────────

class _RideCard extends StatelessWidget {
  final Ride ride;
  const _RideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statusPill(ride.status),
              _DateLabel(date: ride.createdAt),
            ],
          ),
          const SizedBox(height: 10),
          _RouteRow(
            icon: LucideIcons.mapPin,
            color: AppColors.success,
            text: ride.pickup.isEmpty ? '—' : ride.pickup,
          ),
          const SizedBox(height: 4),
          _RouteRow(
            icon: LucideIcons.navigation,
            color: AppColors.accent,
            text: ride.dropoff.isEmpty ? '—' : ride.dropoff,
          ),
          if (ride.commuter.isNotEmpty || ride.commuterPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CommuterLine(
              commuter: ride.commuter.isEmpty ? 'Anonymous' : ride.commuter,
              phone: ride.commuterPhone,
            ),
          ],
          if (ride.rating != null) ...[
            const SizedBox(height: 8),
            _RatingLine(rating: ride.rating!, feedback: ride.feedback),
          ],
          if (ride.notes != null && ride.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              ride.notes!,
              style: const TextStyle(
                color: AppColors.muted,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(RideStatus s) {
    final (label, color, icon) = switch (s) {
      RideStatus.completed => (
        'Completed',
        AppColors.success,
        LucideIcons.checkCircle
      ),
      RideStatus.cancelled => (
        'Cancelled',
        AppColors.danger,
        LucideIcons.xCircle
      ),
      RideStatus.accepted => (
        'In Progress',
        AppColors.info,
        LucideIcons.clock
      ),
      RideStatus.inTransit => (
        'On Trip',
        AppColors.info,
        LucideIcons.car
      ),
      RideStatus.searching => (
        'Searching',
        AppColors.warning,
        LucideIcons.clock
      ),
      RideStatus.unknown => (
        'Unknown',
        AppColors.muted,
        LucideIcons.helpCircle
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ),
      ],
    );
  }
}

class _CommuterLine extends StatelessWidget {
  final String commuter;
  final String phone;
  const _CommuterLine({required this.commuter, required this.phone});

  @override
  Widget build(BuildContext context) {
    final tail = phone.isEmpty ? '' : '  •  $phone';
    return Row(
      children: [
        const Icon(LucideIcons.user, size: 12, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Commuter: $commuter$tail',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RatingLine extends StatelessWidget {
  final int rating;
  final String? feedback;
  const _RatingLine({required this.rating, this.feedback});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? LucideIcons.star : LucideIcons.star,
            size: 13,
            color: i <= rating
                ? AppColors.warning
                : AppColors.surfaceAlt,
          ),
        if (feedback != null && feedback!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '"${feedback!}"',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _DateLabel extends StatelessWidget {
  final DateTime? date;
  const _DateLabel({required this.date});

  @override
  Widget build(BuildContext context) {
    final text = date == null
        ? '—'
        // en_PH locale isn't always bundled; we keep the format
        // English-default which lines up with the rest of the app.
        : DateFormat('MMM d, y • h:mm a').format(date!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.calendar, size: 11, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Empty / error states
// ──────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  /// True when there *are* rides but the current filter hides them all,
  /// so the message can distinguish "no history yet" from "no matches".
  final bool hasAny;
  const _EmptyState({required this.hasAny});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.inbox, size: 32, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            hasAny
                ? 'No rides match this filter.'
                : 'No rides yet.',
            style: const TextStyle(color: AppColors.text, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            hasAny
                ? 'Try a different filter above.'
                : 'Completed rides will appear here.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertTriangle,
                size: 48, color: AppColors.warning),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.go('/driver/dashboard'),
              icon: const Icon(LucideIcons.arrowLeft, size: 14),
              label: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
