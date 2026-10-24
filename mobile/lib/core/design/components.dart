import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'traffic_theme.dart';

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TrafficCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

/// Primary actions across all features use Forui, including legacy form flows.
class TrafficPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final bool secondary;
  const TrafficPrimaryButton({super.key, this.onPressed, required this.child})
    : icon = null,
      secondary = false;
  const TrafficPrimaryButton.tonal({
    super.key,
    this.onPressed,
    required this.child,
  }) : icon = null,
       secondary = true;
  const TrafficPrimaryButton.icon({
    super.key,
    this.onPressed,
    required this.icon,
    required Widget label,
  }) : child = label,
       secondary = false;
  @override
  Widget build(BuildContext context) => TrafficDesignScope(
    child: FButton(
      variant: secondary ? FButtonVariant.secondary : FButtonVariant.primary,
      size: FButtonSizeVariant.lg,
      style: const FButtonStyleDelta.delta(
        tappableStyle: FTappableStyleDelta.delta(
          pressedEnterDuration: Duration.zero,
          pressedExitDuration: Duration.zero,
        ),
      ),
      mainAxisSize: MainAxisSize.min,
      onPress: onPressed,
      builder: (context, style, text, icons, progress, child) =>
          Flexible(child: child!),
      child: icon == null
          ? child
          : Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [icon!, child],
            ),
    ),
  );
}

class TrafficButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool secondary;
  const TrafficButton({
    super.key,
    required this.label,
    this.onPressed,
    this.secondary = false,
  });
  @override
  Widget build(BuildContext context) => TrafficDesignScope(
    child: FButton(
      variant: secondary ? FButtonVariant.outline : FButtonVariant.primary,
      size: FButtonSizeVariant.lg,
      style: const FButtonStyleDelta.delta(
        tappableStyle: FTappableStyleDelta.delta(
          pressedEnterDuration: Duration.zero,
          pressedExitDuration: Duration.zero,
        ),
      ),
      onPress: onPressed,
      builder: (context, style, text, icons, progress, child) =>
          Flexible(child: child!),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

class TrafficCard extends StatelessWidget {
  final Widget child;
  const TrafficCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TrafficDesignScope(
    child: FCard(
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
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
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

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
  Widget build(BuildContext context) => TrafficCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message),
      ],
    ),
  );
}
