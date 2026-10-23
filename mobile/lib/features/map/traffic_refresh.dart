class TrafficRefreshPolicy {
  DateTime lastRefresh, lastInteraction;
  TrafficRefreshPolicy(DateTime now) : lastRefresh = now, lastInteraction = now;
  void interact(DateTime now) => lastInteraction = now;
  bool shouldRefresh(
    DateTime now, {
    required bool foreground,
    required bool enabled,
    required bool navigating,
    required bool blocked,
  }) =>
      foreground &&
      enabled &&
      !blocked &&
      now.difference(lastRefresh) >= const Duration(minutes: 2) &&
      now.difference(lastInteraction) >= const Duration(seconds: 2) &&
      (navigating ||
          now.difference(lastInteraction) <= const Duration(seconds: 45));
  void refreshed(DateTime now) => lastRefresh = now;
}
