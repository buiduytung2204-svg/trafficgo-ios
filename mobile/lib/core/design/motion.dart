import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:animated_toggle_switch/animated_toggle_switch.dart';

abstract final class TrafficMotion {
  static const tap = Duration(milliseconds: 140);
  static const content = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
  static bool reduced(BuildContext c) =>
      MediaQuery.disableAnimationsOf(c) || MediaQuery.accessibleNavigationOf(c);
  static Duration duration(BuildContext c, [Duration value = content]) =>
      reduced(c) ? Duration.zero : value;
}

/// Animates only its first mount. Updates to GPS, ETA or countdown do not restart it.
class TrafficEntrance extends StatefulWidget {
  final Widget child;
  const TrafficEntrance({super.key, required this.child});
  @override
  State<TrafficEntrance> createState() => _TrafficEntranceState();
}

class _TrafficEntranceState extends State<TrafficEntrance>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: TrafficMotion.content,
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TrafficMotion.reduced(context)) {
      controller.stop();
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Animate(
    controller: controller,
    autoPlay: false,
    effects: const [
      FadeEffect(begin: 0, end: 1, duration: TrafficMotion.content),
      SlideEffect(
        begin: Offset(0, .035),
        duration: TrafficMotion.content,
        end: Offset.zero,
        curve: TrafficMotion.curve,
      ),
    ],
    child: widget.child,
  );
}

/// Pointer feedback without replacing the child's gestures, focus or semantics.
class TrafficPress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const TrafficPress({super.key, required this.child, this.enabled = true});
  @override
  State<TrafficPress> createState() => _TrafficPressState();
}

class _TrafficPressState extends State<TrafficPress> {
  bool down = false;
  void press(bool value) {
    if (down != value && mounted) setState(() => down = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => press(true) : null,
    onPointerUp: (_) => press(false),
    onPointerCancel: (_) => press(false),
    child: AnimatedScale(
      scale: down && widget.enabled && !TrafficMotion.reduced(context)
          ? .975
          : 1,
      duration: TrafficMotion.duration(context, TrafficMotion.tap),
      curve: TrafficMotion.curve,
      child: widget.child,
    ),
  );
}

class TrafficToggle<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T) label;
  final IconData Function(T) icon;
  final ValueChanged<T>? onChanged;
  const TrafficToggle({
    super.key,
    required this.value,
    required this.values,
    required this.label,
    required this.icon,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final large = MediaQuery.textScalerOf(context).scale(16) > 21;
    // Material keeps full multi-line labels legible for accessibility sizes.
    if (large) {
      return SegmentedButton<T>(
        segments: [
          for (final v in values)
            ButtonSegment(value: v, label: Text(label(v)), icon: Icon(icon(v))),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null
            ? null
            : (v) => onChanged!(v.first),
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = bounds.maxWidth.isFinite ? bounds.maxWidth : 300.0;
        return Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent || onChanged == null) {
              return KeyEventResult.ignored;
            }
            final delta = event.logicalKey == LogicalKeyboardKey.arrowRight
                ? 1
                : event.logicalKey == LogicalKeyboardKey.arrowLeft
                ? -1
                : 0;
            if (delta == 0) return KeyEventResult.ignored;
            onChanged!(values[(values.indexOf(value) + delta) % values.length]);
            return KeyEventResult.handled;
          },
          canRequestFocus: onChanged != null,
          child: AnimatedToggleSwitch<T>.size(
            current: value,
            values: values,
            height: 56,
            indicatorSize: Size.fromWidth((width - 8) / values.length),
            borderWidth: 4,
            selectedIconScale: 1,
            iconOpacity: 1,
            animationDuration: TrafficMotion.duration(context),
            iconAnimationDuration: TrafficMotion.duration(context),
            indicatorAppearingDuration: TrafficMotion.duration(context),
            animationCurve: TrafficMotion.curve,
            inactiveOpacityDuration: TrafficMotion.duration(
              context,
              TrafficMotion.tap,
            ),
            active: onChanged != null,
            style: ToggleStyle(
              backgroundColor: colors.surfaceContainerHighest.withValues(
                alpha: .55,
              ),
              indicatorColor: colors.primaryContainer,
              borderColor: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              indicatorBorderRadius: BorderRadius.circular(14),
            ),
            onChanged: onChanged,
            iconBuilder: (v) => Semantics(
              button: true,
              enabled: onChanged != null,
              selected: v == value,
              label: label(v),
              onTap: onChanged == null ? null : () => onChanged!(v),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon(v),
                      size: 20,
                      color: v == value
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label(v),
                        style: TextStyle(
                          fontWeight: v == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: v == value
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

IconData placeIcon(String name) {
  final text = name.toLowerCase();
  if (text.contains('nhà')) return Icons.home_rounded;
  if (text.contains('trường') || text.contains('đại học')) {
    return Icons.school_rounded;
  }
  if (text.contains('công ty') || text.contains('văn phòng')) {
    return Icons.work_rounded;
  }
  return Icons.place_rounded;
}
