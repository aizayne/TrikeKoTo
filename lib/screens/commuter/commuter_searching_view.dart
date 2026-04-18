import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/primary_button.dart';

/// Phase 2 of the booking flow — driver search animation + elapsed timer.
/// The actual matching happens on the driver side; this view only
/// reports time-since-submit and offers a cancel button.
class CommuterSearchingView extends StatefulWidget {
  final String pickup;
  final String dropoff;
  final bool busy;
  final Future<void> Function() onCancel;

  const CommuterSearchingView({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.busy,
    required this.onCancel,
  });

  @override
  State<CommuterSearchingView> createState() => _CommuterSearchingViewState();
}

class _CommuterSearchingViewState extends State<CommuterSearchingView> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final m = (_seconds ~/ 60).toString();
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          const _Pulse(),
          const SizedBox(height: 28),
          const Text(
            'Looking for a driver…',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Elapsed $_elapsed',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 32),
          _RouteCard(pickup: widget.pickup, dropoff: widget.dropoff),
          const Spacer(),
          SecondaryButton(
            label: 'Cancel ride',
            icon: LucideIcons.x,
            color: AppColors.danger,
            onPressed: widget.busy ? null : widget.onCancel,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Two staggered ripples for a layered pulse.
          _ring(0.0),
          _ring(0.5),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.car,
                color: AppColors.accent, size: 40),
          ),
        ],
      ),
    );
  }

  Widget _ring(double phase) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = ((_ctrl.value + phase) % 1.0);
        final scale = 0.6 + 0.6 * v;
        final opacity = (1.0 - v).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity * 0.55,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppColors.accent, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RouteCard extends StatelessWidget {
  final String pickup;
  final String dropoff;
  const _RouteCard({required this.pickup, required this.dropoff});

  @override
  Widget build(BuildContext context) {
    return Card(
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
    );
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
