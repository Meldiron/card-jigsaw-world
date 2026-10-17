import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/rewards.dart';

/// "New picture in 6h 37m": the time until the next daily puzzle (local midnight), on Home's Today
/// card once today's picture is solved (owner, 2026-10-17; it replaced the "Tomorrow's daily
/// puzzle" row). Hours and minutes, read again every 30 seconds.
class NewPictureIn extends StatefulWidget {
  const NewPictureIn({super.key, required this.style, this.clock = DateTime.now});
  final TextStyle style;
  final DateTime Function() clock;

  @override
  State<NewPictureIn> createState() => _NewPictureInState();
}

class _NewPictureInState extends State<NewPictureIn> {
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
    final now = widget.clock();
    final left = Goals.nextDailyReset(now).difference(now);
    return Text(
      'New picture in ${Goals.formatLeft(left)}',
      key: const ValueKey('home-new-picture-in'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}
