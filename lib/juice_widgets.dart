import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'rank_utils.dart';

class RollingEloCounter extends StatefulWidget {
  final int value;
  final TextStyle style;
  final Duration duration;

  const RollingEloCounter({
    super.key,
    required this.value,
    this.style = const TextStyle(
      fontSize: 100,
      fontWeight: FontWeight.w900,
      height: 0.9,
      color: Colors.white,
    ),
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<RollingEloCounter> createState() => _RollingEloCounterState();
}

class _RollingEloCounterState extends State<RollingEloCounter> {
  late int _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
  }

  @override
  void didUpdateWidget(RollingEloCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousValue = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _previousValue.toDouble(), end: widget.value.toDouble()),
      duration: widget.duration,
      curve: Curves.outSoap,
      builder: (context, val, child) {
        return Text(RankUtils.formatElo(val.toInt()), style: widget.style);
      },
    );
  }
}

// Custom curve for a more "mechanical" rolling feel
class Curves {
  static const Curve outSoap = _OutSoapCurve();
}

class _OutSoapCurve extends Curve {
  const _OutSoapCurve();
  @override
  double transformInternal(double t) {
    // A bouncy, rapid deceleration curve
    return 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t);
  }
}

class RankUpCelebration extends StatefulWidget {
  final Rank newRank;
  final VoidCallback onDismiss;

  const RankUpCelebration({
    super.key,
    required this.newRank,
    required this.onDismiss,
  });

  @override
  State<RankUpCelebration> createState() => _RankUpCelebrationState();
}

class _RankUpCelebrationState extends State<RankUpCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _blurAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.outSoap,
    );

    _blurAnimation = Tween<double>(begin: 0, end: 20).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5)),
    );

    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.3)),
    );

    _controller.forward();

    // Provide haptic feedback on Rank Up
    HapticFeedback.heavyImpact();
    Future.delayed(
      const Duration(milliseconds: 100),
      () => HapticFeedback.heavyImpact(),
    );
    Future.delayed(
      const Duration(milliseconds: 200),
      () => HapticFeedback.heavyImpact(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Background Blur
          AnimatedBuilder(
            animation: _blurAnimation,
            builder: (context, child) {
              return BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _blurAnimation.value,
                  sigmaY: _blurAnimation.value,
                ),
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              );
            },
          ),

          // Celebration Card
          Center(
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "NEW RANK ACHIEVED",
                      style: TextStyle(
                        color: Colors.white54,
                        letterSpacing: 4,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 30,
                      ),
                      decoration: BoxDecoration(
                        color: widget.newRank.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(
                          color: widget.newRank.color.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.newRank.color.withValues(alpha: 0.2),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium,
                            size: 80,
                            color: widget.newRank.color,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            widget.newRank.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: widget.newRank.color,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 50),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "CONTINUE YOUR ENDEAVOUR",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
