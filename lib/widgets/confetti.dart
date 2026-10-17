import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../core/a11y.dart';
import '../core/theme/tokens.dart';

/// The confetti of a finished board (the game screen's burst: the same particles, forces and
/// colours) as a one-off over everything on screen, sheets included. The daily gift plays it when
/// a gift is claimed (owner, 2026-10-17). It starts at [from] (global coordinates; the top centre of
/// the screen when null) and takes no touches. Nothing with Reduce motion: it is decorative motion.
void showConfettiBurst(BuildContext context, {Offset? from}) {
  if (A11y.reduceMotionOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(builder: (context) => _ConfettiBurst(from: from, onDone: remove));
  overlay.insert(entry);
}

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst({required this.from, required this.onDone});
  final Offset? from;
  final VoidCallback onDone;

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst> {
  final _controller = ConfettiController(duration: const Duration(seconds: 2));
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    // The burst stops by itself once the last particle has fallen; the timer is a backstop.
    _controller.addListener(_changed);
    _fallback = Timer(const Duration(seconds: 8), widget.onDone);
    _controller.play();
  }

  void _changed() {
    if (_controller.state != ConfettiControllerState.playing) widget.onDone();
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final burst = ConfettiWidget(
      confettiController: _controller,
      blastDirectionality: BlastDirectionality.explosive,
      numberOfParticles: 24,
      maxBlastForce: 24,
      minBlastForce: 8,
      gravity: 0.25,
      emissionFrequency: 0.04,
      colors: const [Brand.accent, Brand.star, Brand.ticket, Color(0xFF94A3B8), Colors.white],
    );
    final from = widget.from;
    return IgnorePointer(
      child: from == null ? Align(alignment: Alignment.topCenter, child: burst) : Stack(children: [Positioned(left: from.dx, top: from.dy, child: burst)]),
    );
  }
}
