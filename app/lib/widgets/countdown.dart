import 'dart:async';

import 'package:flutter/material.dart';

import '../util/format.dart';

/// Texte qui décompte jusqu'à [target] et appelle [onDone] une fois à zéro.
class Countdown extends StatefulWidget {
  const Countdown({
    super.key,
    required this.target,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.onDone,
  });

  final DateTime target;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final VoidCallback? onDone;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant Countdown old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _fired = false;
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (!_fired && !widget.target.isAfter(DateTime.now())) {
      _fired = true;
      // petite marge pour laisser le serveur basculer l'état
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) widget.onDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.target.difference(DateTime.now());
    return Text('${widget.prefix}${formatRemaining(left)}${widget.suffix}', style: widget.style);
  }
}
