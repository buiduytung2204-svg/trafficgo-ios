import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'traffic_theme.dart';
import 'motion.dart';
export 'motion.dart';

String formatVnd(int amount) =>
    '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} VNĐ';

class MetricPanel extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const MetricPanel({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = title == 'Hôm nay'
        ? TrafficTokens.blue(context)
        : title == 'Tuần này'
        ? TrafficTokens.amber(context)
        : colors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TrafficCard(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
            ),
          ],
        ),
      ),
    );
  }
}

enum TrafficButtonPhase { idle, loading, success, error }

/// One async gate for touch, keyboard and accessibility activation.
/// Success is opt-in: callbacks that catch domain errors must supply their own state.
class TrafficPrimaryButton extends StatefulWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget child;
  final Widget? icon;
  final bool secondary, successFeedback;
  final TrafficButtonPhase phase;
  const TrafficPrimaryButton({
    super.key,
    this.onPressed,
    required this.child,
    this.successFeedback = false,
    this.phase = TrafficButtonPhase.idle,
  }) : icon = null,
       secondary = false;
  const TrafficPrimaryButton.tonal({
    super.key,
    this.onPressed,
    required this.child,
    this.successFeedback = false,
    this.phase = TrafficButtonPhase.idle,
  }) : icon = null,
       secondary = true;
  const TrafficPrimaryButton.icon({
    super.key,
    this.onPressed,
    required this.icon,
    required Widget label,
    this.successFeedback = false,
    this.phase = TrafficButtonPhase.idle,
  }) : child = label,
       secondary = false;
  @override
  State<TrafficPrimaryButton> createState() => _TrafficPrimaryButtonState();
}

class _TrafficPrimaryButtonState extends State<TrafficPrimaryButton> {
  bool running = false;
  TrafficButtonPhase result = TrafficButtonPhase.idle;
  Timer? reset;
  bool get busy => running || widget.phase == TrafficButtonPhase.loading;
  TrafficButtonPhase get phase => busy
      ? TrafficButtonPhase.loading
      : widget.phase != TrafficButtonPhase.idle
      ? widget.phase
      : result;
  Future<void> runAction() async {
    if (busy || widget.onPressed == null) return;
    reset?.cancel();
    setState(() => running = true);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      unawaited(HapticFeedback.selectionClick().catchError((_) {}));
    }
    try {
      await widget.onPressed!();
      if (mounted && widget.successFeedback) {
        setState(() => result = TrafficButtonPhase.success);
      }
    } catch (_) {
      if (mounted) {
        setState(() => result = TrafficButtonPhase.error);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Thao tác chưa hoàn tất. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => running = false);
        if (result != TrafficButtonPhase.idle) {
          reset = Timer(const Duration(milliseconds: 1400), () {
            if (mounted) setState(() => result = TrafficButtonPhase.idle);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final feedback = phase == TrafficButtonPhase.loading
        ? 'Đang xử lý'
        : phase == TrafficButtonPhase.success
        ? 'Đã hoàn tất'
        : phase == TrafficButtonPhase.error
        ? 'Chưa hoàn tất'
        : null;
    final visual = phase == TrafficButtonPhase.idle
        ? null
        : phase == TrafficButtonPhase.loading
        ? (TrafficMotion.reduced(context)
              ? const Icon(Icons.hourglass_top_rounded)
              : SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: colors.onSurface,
                  ),
                ))
        : Icon(
            phase == TrafficButtonPhase.success
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 24,
          );
    return Semantics(
      liveRegion: feedback != null,
      label: feedback == null
          ? null
          : '$feedback ${widget.child is Text ? (widget.child as Text).data ?? '' : ''}'
                .trim(),
      child: TrafficPress(
        enabled: widget.onPressed != null && !busy,
        child: AnimatedContainer(
          duration: TrafficMotion.duration(context, TrafficMotion.tap),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (widget.onPressed != null && !widget.secondary)
                BoxShadow(
                  color: colors.primary.withValues(alpha: busy ? .06 : .18),
                  blurRadius: busy ? 4 : 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: TrafficDesignScope(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: FButton(
                variant: widget.secondary
                    ? FButtonVariant.secondary
                    : FButtonVariant.primary,
                size: FButtonSizeVariant.lg,
                style: FButtonStyleDelta.delta(
                  tappableStyle: FTappableStyleDelta.delta(
                    // TrafficPress owns the visual motion; Forui delays use uncancellable timers.
                    pressedEnterDuration: Duration.zero,
                    pressedExitDuration: Duration.zero,
                  ),
                ),
                mainAxisSize: MainAxisSize.min,
                onPress: widget.onPressed == null || busy ? null : runAction,
                builder: (context, style, text, icons, progress, child) =>
                    Flexible(
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontFamily: TrafficTokens.fontFamily,
                          fontWeight: FontWeight.w700,
                        ),
                        child: child!,
                      ),
                    ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: visual == null ? 1 : 0,
                      child: widget.icon == null
                          ? widget.child
                          : Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [widget.icon!, widget.child],
                            ),
                    ),
                    if (visual != null)
                      Positioned.fill(
                        child: Center(child: ExcludeSemantics(child: visual)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrafficButton extends StatelessWidget {
  final FutureOr<void> Function()? onPressed;
  final String label;
  final bool secondary;
  const TrafficButton({
    super.key,
    required this.label,
    this.onPressed,
    this.secondary = false,
  });
  @override
  Widget build(BuildContext context) => secondary
      ? TrafficPrimaryButton.tonal(
          onPressed: onPressed,
          child: Text(label, textAlign: TextAlign.center),
        )
      : TrafficPrimaryButton(
          onPressed: onPressed,
          child: Text(label, textAlign: TextAlign.center),
        );
}

class TrafficCard extends StatelessWidget {
  final Widget child;
  final Color? color, accent;
  final bool selected;
  const TrafficCard({
    super.key,
    required this.child,
    this.color,
    this.accent,
    this.selected = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TrafficDesignScope(
      child: FCard(
        style: FCardStyle(
          decoration: BoxDecoration(
            color: color ?? colors.surface,
            borderRadius: BorderRadius.circular(TrafficTokens.radius),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : accent?.withValues(alpha: .25) ??
                        colors.outlineVariant.withValues(alpha: .55),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              if (theme.brightness == Brightness.light)
                BoxShadow(
                  color: const Color(0xff20252b).withValues(alpha: .035),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          titleTextStyle: theme.textTheme.titleLarge!,
          subtitleTextStyle: theme.textTheme.bodyMedium!,
          padding: EdgeInsets.zero,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(TrafficTokens.page),
            child: child,
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  const SectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => TrafficEntrance(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.6),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Original vector illustration; no remote asset, Rive runtime, or license dependency.
class EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title, message;
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => TrafficEntrance(
    child: TrafficCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 92,
            width: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 4,
                  top: 8,
                  child: Transform.rotate(
                    angle: -.12,
                    child: Container(
                      width: 80,
                      height: 66,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 4,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: TrafficTokens.amber(context)
                          .withValues(alpha: .15),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

void showTrafficSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: TrafficEntrance(
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xffc6f36b)),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}
