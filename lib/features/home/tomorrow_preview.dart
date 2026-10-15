import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/rewards.dart';
import '../../widgets/hash_image.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The daily puzzle dated the day after [now] (local time), or null when the
/// catalogue does not have it yet: the next month's pack stays hidden until
/// its first day, so on the last day of a month there is nothing to show.
Puzzle? tomorrowsDaily(Iterable<Puzzle> puzzles, DateTime now) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  for (final p in puzzles) {
    final d = p.date;
    if (d != null && d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day) return p;
  }
  return null;
}

/// Tomorrow's daily puzzle as its BlurHash only (the picture itself is never
/// loaded, so nothing is spoiled), with the time left until it opens at
/// local midnight. Home shows it once today's daily puzzle is solved.
class TomorrowPreview extends StatefulWidget {
  const TomorrowPreview({super.key, required this.puzzle, this.clock = DateTime.now});
  final Puzzle puzzle;
  final DateTime Function() clock;

  @override
  State<TomorrowPreview> createState() => _TomorrowPreviewState();
}

class _TomorrowPreviewState extends State<TomorrowPreview> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = widget.clock();
    final left = Goals.nextDailyReset(now).difference(now);
    final hash = widget.puzzle.blurhash;
    return SoftCard(
      key: const ValueKey('home-tomorrow'),
      padding: Insets.cardCompact,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: hash == null || hash.isEmpty ? ColoredBox(color: c.boardBackground) : HashImage(hash: hash, color: c.boardBackground),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Tomorrow's daily puzzle", style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                const SizedBox(height: 2),
                Text('Opens in ${Goals.formatLeft(left)}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote)),
              ],
            ),
          ),
          Icon(AppIcons.lock, size: 16, color: c.textTertiary),
        ],
      ),
    );
  }
}
