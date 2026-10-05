import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:flutter/widgets.dart';

/// What to do after a failed load.
class LoadFailureDecision {
  const LoadFailureDecision._({
    this.retryAfter,
    this.disabledNow = false,
  });

  /// Retry once after this delay; null means wait for the next natural
  /// trigger (a show request, a resume, a reconnect).
  final Duration? retryAfter;

  /// True the first time this unit is disabled, so the caller emits ONE
  /// clear event for it and nothing after.
  final bool disabledNow;

  static const LoadFailureDecision none = LoadFailureDecision._();
}

/// Decides when a full-screen ad may load again after a failure.
///
/// Replaces the old "5 retries with exponential backoff" loop, which kept
/// hammering AdMob after a frequency-cap error (each retry is another
/// capped request) and after no-fill (which rarely clears within a minute).
///
/// * Frequency cap → no load at all until [capCooldown] has passed; the app
///   passes its own interstitial cooldown, which matches AdMob's cap.
/// * No fill / timeout / network → one retry after [noFillRetryDelay], then
///   nothing until the next natural trigger.
/// * Invalid or wrong-format unit → disabled for the session.
class LoadRetryGovernor {
  LoadRetryGovernor({
    required this.adUnitId,
    required this.adNetwork,
    required this.adUnitType,
    this.capCooldown = const Duration(minutes: 15),
    this.noFillRetryDelay = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String adUnitId;
  final AdNetwork adNetwork;
  final AdUnitType adUnitType;
  final Duration capCooldown;
  final Duration noFillRetryDelay;
  final DateTime Function() _clock;

  DateTime? _blockedUntil;
  bool _retryUsed = false;

  bool get isDisabled => DisabledAdUnits.isDisabled(adUnitId);

  /// Whether a load may start now.
  bool get canLoad {
    if (isDisabled) return false;
    final until = _blockedUntil;
    return until == null || !_clock().isBefore(until);
  }

  /// When the frequency-cap block ends, or null when not blocked.
  DateTime? get blockedUntil => _blockedUntil;

  /// A load the app asked for (not one of our own retries) gets a fresh
  /// single retry.
  void onNaturalLoad() => _retryUsed = false;

  void onLoaded() {
    _blockedUntil = null;
    _retryUsed = false;
  }

  LoadFailureDecision onFailure(AdErrorType type, {String? message}) {
    switch (type) {
      case AdErrorType.frequencyCapped:
        _blockedUntil = _clock().add(capCooldown);
        return LoadFailureDecision.none;
      case AdErrorType.invalidAdUnit:
      case AdErrorType.wrongFormat:
        final bool first = DisabledAdUnits.disable(
          adUnitId,
          reason:
              '${adUnitType.name} unit ${type.name}: ${message ?? type.message}',
        );
        return LoadFailureDecision._(disabledNow: first);
      case AdErrorType.noFill:
      case AdErrorType.timeout:
      case AdErrorType.networkError:
      case AdErrorType.internalError:
      case AdErrorType.unknown:
        if (_retryUsed) return LoadFailureDecision.none;
        _retryUsed = true;
        return LoadFailureDecision._(retryAfter: noFillRetryDelay);
    }
  }

  /// Checks the unit id's shape before any request is made. A malformed id
  /// is disabled; returns the reason the first time, null otherwise.
  String? validateFormat() => checkUnitShape(adUnitId, adNetwork, adUnitType);
}

/// Disables a malformed unit before any request. Returns the reason the
/// first time, so the caller reports it once; null otherwise.
String? checkUnitShape(String adUnitId, AdNetwork network, AdUnitType type) {
  final String? problem = adUnitIdProblem(adUnitId, network);
  if (problem == null) return null;
  final reason = '${type.name} unit malformed: $problem';
  return DisabledAdUnits.disable(adUnitId, reason: reason) ? reason : null;
}

/// For banner and native units, which keep their own retry policy: an
/// invalid or wrong-format unit is disabled for the session. Returns true
/// when this failure was already reported for the unit and should stay
/// quiet.
bool silenceDeadUnit(
  String adUnitId,
  AdUnitType type,
  AdErrorType error,
  String message,
) {
  if (error != AdErrorType.invalidAdUnit && error != AdErrorType.wrongFormat) {
    return false;
  }
  return !DisabledAdUnits.disable(
    adUnitId,
    reason: '${type.name} unit ${error.name}: $message',
  );
}

/// Why [adUnitId] cannot be a real unit for [network], or null when its shape
/// is fine. AdMob ids look like `ca-app-pub-<pub>/<unit>`; Ad Manager ids are
/// paths starting with `/`.
String? adUnitIdProblem(String adUnitId, AdNetwork network) {
  final id = adUnitId.trim();
  if (id.isEmpty) return 'empty id';
  switch (network) {
    case AdNetwork.admob:
      return RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(id)
          ? null
          : 'expected ca-app-pub-<publisher>/<unit>, got "$id"';
    case AdNetwork.adManager:
      return id.startsWith('/')
          ? null
          : 'expected a /network/path id, got "$id"';
    case AdNetwork.any:
      return null;
  }
}

/// Units switched off for the rest of the session because they can never
/// load: malformed, unknown to AdMob, or configured for another format.
class DisabledAdUnits {
  DisabledAdUnits._();

  static final Map<String, String> _reasons = {};

  static bool isDisabled(String adUnitId) => _reasons.containsKey(adUnitId);

  static String? reasonFor(String adUnitId) => _reasons[adUnitId];

  /// Returns true only the first time, so a caller emits one event per unit.
  static bool disable(String adUnitId, {required String reason}) {
    if (_reasons.containsKey(adUnitId)) return false;
    _reasons[adUnitId] = reason;
    return true;
  }

  @visibleForTesting
  static void reset() => _reasons.clear();
}

/// Full-screen ads must not start while the app is in the background: the
/// SDK reports "app not in foreground" and the slot is wasted.
bool get isAppInForeground {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}
