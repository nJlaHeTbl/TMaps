import 'package:flutter/material.dart';

/// One small motion budget for interface elements, never for every map frame.
abstract final class AppMotion {
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 240);
  static const panel = Duration(milliseconds: 280);

  static bool enabled(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false);
  }

  static Duration duration(BuildContext context, [Duration value = standard]) =>
      enabled(context) ? value : Duration.zero;
}

/// Runs once when mounted, not on every GPS or weather rebuild.
class MotionEntrance extends StatelessWidget {
  const MotionEntrance({
    super.key,
    required this.child,
    this.duration = AppMotion.standard,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, animatedChild) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: animatedChild,
        ),
      ),
    );
  }
}

/// Fades a new keyed state in while making outgoing controls inert immediately.
/// Keep this widget mounted with a null child to animate a panel's dismissal.
class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.duration = AppMotion.standard,
  });

  final Widget? child;
  final AlignmentGeometry alignment;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child ?? const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: AppMotion.quick,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        clipBehavior: Clip.none,
        children: [
          for (final outgoing in previous)
            _MotionChild(key: outgoing.key, active: false, child: outgoing),
          if (current != null)
            _MotionChild(key: current.key, active: true, child: current),
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// Preserve the same focus boundary when an entry becomes an outgoing child.
// Inserting a new boundary only during dismissal can retain primary focus.
class _MotionChild extends StatelessWidget {
  const _MotionChild({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !active,
    child: ExcludeFocus(
      excluding: !active,
      child: ExcludeSemantics(excluding: !active, child: child),
    ),
  );
}
