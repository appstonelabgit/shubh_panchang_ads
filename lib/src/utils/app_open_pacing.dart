/// When app-open ads may show, shared by every app-open unit.
///
/// The app passes its session number and the last impression it persisted;
/// the package has no storage of its own and tracks impressions within the
/// process from there.
class AppOpenPacing {
  AppOpenPacing({
    this.cooldown = const Duration(hours: 4),
    this.minSessions = 3,
    this.sessionNumber = 0,
    this.lastShownAt,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// AdMob caps app-open at once per 4 hours.
  Duration cooldown;

  /// No app-open ad before this cold launch.
  int minSessions;

  /// The current cold launch (1 = first). 0 means the app didn't say, and
  /// [minSessions] is not enforced.
  int sessionNumber;

  DateTime? lastShownAt;

  final DateTime Function() _clock;

  bool get inCooldown {
    final last = lastShownAt;
    return last != null && _clock().difference(last) < cooldown;
  }

  /// Why an app-open ad must not show now, or null.
  String? get skipReason {
    if (sessionNumber > 0 && sessionNumber < minSessions) return 'min_sessions';
    if (inCooldown) return 'cooldown';
    return null;
  }

  void recordShown() => lastShownAt = _clock();
}
