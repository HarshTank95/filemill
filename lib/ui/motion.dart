import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// Shared motion language: emphasized easing, fade-through page changes,
/// gentle staggered entrances.
class Motion {
  Motion._();

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 480);

  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve decelerate = Curves.easeOutCubic;

  static Route<T> fadeThrough<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: slow,
      reverseTransitionDuration: medium,
      pageBuilder: (_, a1, a2) => page,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      },
    );
  }

  static Route<T> sharedAxis<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: slow,
      reverseTransitionDuration: medium,
      pageBuilder: (_, a1, a2) => page,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        return SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.horizontal,
          child: child,
        );
      },
    );
  }
}

/// Slide+fade entrance used for list/grid items on first build.
class Entrance extends StatelessWidget {
  final Widget child;
  final int index;
  const Entrance({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + 60 * index.clamp(0, 8)),
      curve: Motion.decelerate,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
