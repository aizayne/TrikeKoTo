import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// Phase 5 of the commuter flow: tap a star, optionally leave a
/// comment, submit. The Firestore rule forbids re-rating, so we treat
/// a successful write as terminal and call [onDone].
///
/// Skip is intentionally lossy: we just call [onDone] without writing
/// anything. The ride sits in `completed` with `rating == null` —
/// admin analytics treat that as "no response".
class CommuterRatingView extends ConsumerStatefulWidget {
  final String rideId;
  final VoidCallback onDone;

  const CommuterRatingView({
    super.key,
    required this.rideId,
    required this.onDone,
  });

  @override
  ConsumerState<CommuterRatingView> createState() =>
      _CommuterRatingViewState();
}

class _CommuterRatingViewState extends ConsumerState<CommuterRatingView> {
  /// 1..5; 0 means nothing tapped yet (submit disabled).
  int _rating = 0;

  final TextEditingController _comment = TextEditingController();

  bool _submitting = false;
  String? _error;

  /// Comment cap matches the React reference. The Firestore rule does
  /// not enforce a max on `feedback`, but we keep the UI in step.
  static const int _commentMax = 500;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    if (_rating < AppConstants.minRating || _rating > AppConstants.maxRating) {
      return;
    }
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(firestoreServiceProvider).rateRide(
            rideId: widget.rideId,
            rating: _rating,
            feedback: _comment.text,
          );
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not submit rating: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _rating >= AppConstants.minRating && !_submitting;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.checkCheck,
                  size: 44, color: AppColors.info),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Ride complete!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'How was your trip?',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          _StarRow(
            value: _rating,
            onChanged: _submitting
                ? null
                : (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Center(
              child: Text(
                _ratingLabel(_rating),
                style: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _comment,
            maxLines: 4,
            maxLength: _commentMax,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Comments (optional)',
              hintText: 'Tell us about your experience…',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 64),
                child: Icon(LucideIcons.messageSquare, size: 18),
              ),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.alertTriangle,
                      size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Submit rating',
            icon: LucideIcons.send,
            busy: _submitting,
            onPressed: canSubmit ? _submit : null,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Skip for now',
            icon: LucideIcons.arrowRight,
            onPressed: _submitting ? null : widget.onDone,
          ),
        ],
      ),
    );
  }
}

/// Tap-to-rate row of five stars. Hover state is omitted on purpose —
/// touch-first UX, no need to mirror the React hover affordance.
class _StarRow extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  const _StarRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 1; i <= AppConstants.maxRating; i++) ...[
          _StarButton(
            filled: i <= value,
            onTap: onChanged == null ? null : () => onChanged!(i),
          ),
          if (i != AppConstants.maxRating) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _StarButton extends StatelessWidget {
  final bool filled;
  final VoidCallback? onTap;
  const _StarButton({required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 30,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: 40,
          color: filled
              ? AppColors.warning
              : AppColors.muted.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
