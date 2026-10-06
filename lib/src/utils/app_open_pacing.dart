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
    this.preloadLead = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Minimum gap between two app-open impressions.
  Duration cooldown;

  /// No app-open ad before this cold launch.
  int minSessions;

  /// The current cold launch (1 = first). 0 means the app didn't say, and
  /// [minSessions] is not enforced.
  int sessionNumber;

  DateTime? lastShownAt;

  /// How long before the cooldown ends the next ad may be loaded, so it is
  /// already cached on the first resume after it. Must stay shorter than
  /// the gap between [cooldown] and AdMob's own cap on the unit, or the
  /// preload is refused as frequency-capped.
  Duration preloadLead;

  final DateTime Function() _clock;

  bool get inCooldown {
    final last = lastShownAt;
    return last != null && _clock().difference(last) < cooldown;
  }

  /// Whether a load may start: outside the cooldown, or inside its last
  /// [preloadLead].
  bool get canLoad => timeUntilPreload == Duration.zero;

  /// How long until a load may start; zero when it may start now.
  Duration get timeUntilPreload {
    final last = lastShownAt;
    if (last == null) return Duration.zero;
    final wait = cooldown - preloadLead - _clock().difference(last);
    return wait.isNegative ? Duration.zero : wait;
  }

  /// Why an app-open ad must not show now, or null.
  String? get skipReason {
    if (sessionNumber > 0 && sessionNumber < minSessions) return 'min_sessions';
    if (inCooldown) return 'cooldown';
    return null;
  }

  void recordShown() => lastShownAt = _clock();
}

/// A show request that found nothing cached and is waiting for a load.
/// The ad may still be shown only until [deadline] and only while the user
/// is on the screen they resumed to; a later arrival stays cached for the
/// next resume instead of landing on whatever they are doing by then.
class AwaitedAppOpenShow {
  AwaitedAppOpenShow({required this.deadline, this.stillEligible});

  final DateTime deadline;
  final bool Function()? stillEligible;

  /// Why an ad that finished loading at [now] must not show, or null.
  String? skipReasonAt(DateTime now) {
    if (now.isAfter(deadline)) return 'timeout';
    if (!(stillEligible?.call() ?? true)) return 'screen';
    return null;
  }
}
