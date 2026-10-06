import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/app_open_pacing.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 10, 6, 10);
    DisabledAdUnits.reset();
  });

  LoadRetryGovernor governor([String id = 'ca-app-pub-1/2']) =>
      LoadRetryGovernor(
        adUnitId: id,
        adNetwork: AdNetwork.admob,
        adUnitType: AdUnitType.interstitial,
        capCooldown: const Duration(minutes: 15),
        clock: clock,
      );

  group('LoadRetryGovernor', () {
    test('frequency cap blocks every load until the cooldown passes', () {
      final g = governor();
      final d = g.onFailure(AdErrorType.frequencyCapped);
      expect(d.retryAfter, isNull);
      expect(g.canLoad, isFalse);
      now = now.add(const Duration(minutes: 14, seconds: 59));
      expect(g.canLoad, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(g.canLoad, isTrue);
    });

    test('no fill retries once after 60 s, then waits', () {
      final g = governor();
      expect(
        g.onFailure(AdErrorType.noFill).retryAfter,
        const Duration(seconds: 60),
      );
      expect(g.onFailure(AdErrorType.noFill).retryAfter, isNull);
      expect(g.onFailure(AdErrorType.timeout).retryAfter, isNull);
      expect(g.canLoad, isTrue);
    });

    test('a natural load or a success gives back the single retry', () {
      final g = governor();
      g.onFailure(AdErrorType.timeout);
      g.onNaturalLoad();
      expect(g.onFailure(AdErrorType.timeout).retryAfter, isNotNull);
      g.onLoaded();
      expect(g.onFailure(AdErrorType.noFill).retryAfter, isNotNull);
    });

    test('invalid or wrong-format unit is disabled, reported once', () {
      final g = governor();
      expect(g.onFailure(AdErrorType.wrongFormat).disabledNow, isTrue);
      expect(g.onFailure(AdErrorType.wrongFormat).disabledNow, isFalse);
      expect(g.canLoad, isFalse);
      expect(governor().isDisabled, isTrue);
    });

    test('a malformed id is disabled before any request', () {
      final g = governor('ca-app-pub-1~2');
      expect(g.validateFormat(), contains('malformed'));
      expect(g.validateFormat(), isNull);
      expect(g.canLoad, isFalse);
    });
  });

  group('adUnitIdProblem', () {
    test('AdMob ids', () {
      expect(
          adUnitIdProblem(
              'ca-app-pub-3940256099942544/1033173712', AdNetwork.admob),
          isNull);
      expect(adUnitIdProblem('', AdNetwork.admob), 'empty id');
      expect(
          adUnitIdProblem(
              'ca-app-pub-3940256099942544~3347511713', AdNetwork.admob),
          isNotNull);
    });

    test('Ad Manager ids', () {
      expect(adUnitIdProblem('/6499/example/interstitial', AdNetwork.adManager),
          isNull);
      expect(adUnitIdProblem('ca-app-pub-1/2', AdNetwork.adManager), isNotNull);
    });
  });

  group('silenceDeadUnit', () {
    test('only invalid/wrong-format errors disable a banner unit', () {
      expect(
        silenceDeadUnit('u', AdUnitType.banner, AdErrorType.noFill, 'x'),
        isFalse,
      );
      expect(DisabledAdUnits.isDisabled('u'), isFalse);
      expect(
        silenceDeadUnit('u', AdUnitType.banner, AdErrorType.invalidAdUnit, 'x'),
        isFalse,
      );
      expect(
        silenceDeadUnit('u', AdUnitType.banner, AdErrorType.invalidAdUnit, 'x'),
        isTrue,
      );
    });
  });

  group('errorTypeFromMessage', () {
    test('recognises frequency cap and format mismatch', () {
      expect(
        errorTypeFromMessage('Ad request was throttled: frequency cap reached'),
        AdErrorType.frequencyCapped,
      );
      expect(
        errorTypeFromMessage(
          "Ad unit doesn't match format. <https://support.google.com/>",
        ),
        AdErrorType.wrongFormat,
      );
      expect(errorTypeFromMessage('No fill.'), isNull);
      expect(isErrorRetryable(AdErrorType.frequencyCapped), isFalse);
      expect(isErrorRetryable(AdErrorType.wrongFormat), isFalse);
    });
  });

  group('AppOpenPacing', () {
    test('waits for the minimum session', () {
      final p = AppOpenPacing(sessionNumber: 2, clock: clock);
      expect(p.skipReason, 'min_sessions');
      p.sessionNumber = 3;
      expect(p.skipReason, isNull);
      p.sessionNumber = 0;
      expect(p.skipReason, isNull);
    });

    test('once per 4 hours, from the persisted time or this process', () {
      final p = AppOpenPacing(
        sessionNumber: 5,
        lastShownAt: now.subtract(const Duration(hours: 3)),
        clock: clock,
      );
      expect(p.skipReason, 'cooldown');
      now = now.add(const Duration(hours: 1));
      expect(p.skipReason, isNull);
      p.recordShown();
      expect(p.inCooldown, isTrue);
    });

    test('loads again only in the last half hour of the cooldown', () {
      final p = AppOpenPacing(sessionNumber: 5, clock: clock);
      expect(p.canLoad, isTrue);
      p.recordShown();
      expect(p.canLoad, isFalse);
      expect(p.timeUntilPreload, const Duration(hours: 3, minutes: 30));

      now = now.add(const Duration(hours: 3, minutes: 29));
      expect(p.canLoad, isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(p.canLoad, isTrue);
      expect(p.timeUntilPreload, Duration.zero);
      // Loadable, still not showable.
      expect(p.skipReason, 'cooldown');

      now = now.add(const Duration(minutes: 30));
      expect(p.canLoad, isTrue);
      expect(p.skipReason, isNull);
    });

    test('the preload lead follows the configured cooldown', () {
      final p = AppOpenPacing(
        cooldown: const Duration(hours: 2),
        preloadLead: const Duration(minutes: 10),
        lastShownAt: now,
        clock: clock,
      );
      expect(p.timeUntilPreload, const Duration(hours: 1, minutes: 50));
    });
  });

  group('AwaitedAppOpenShow', () {
    test('shows an ad that arrives inside the window', () {
      final a = AwaitedAppOpenShow(
        deadline: now.add(const Duration(seconds: 3)),
      );
      expect(a.skipReasonAt(now.add(const Duration(seconds: 2))), isNull);
      expect(a.skipReasonAt(now.add(const Duration(seconds: 3))), isNull);
    });

    test('never shows one that arrives late', () {
      final a = AwaitedAppOpenShow(
        deadline: now.add(const Duration(seconds: 3)),
      );
      expect(
        a.skipReasonAt(now.add(const Duration(milliseconds: 3001))),
        'timeout',
      );
    });

    test('skips when the user has moved to another screen', () {
      var onSameScreen = true;
      final a = AwaitedAppOpenShow(
        deadline: now.add(const Duration(seconds: 3)),
        stillEligible: () => onSameScreen,
      );
      expect(a.skipReasonAt(now.add(const Duration(seconds: 1))), isNull);
      onSameScreen = false;
      expect(a.skipReasonAt(now.add(const Duration(seconds: 1))), 'screen');
    });
  });

  group('app-open frequency cap', () {
    test('a cap error does not block the next natural load', () {
      final g = LoadRetryGovernor(
        adUnitId: 'ca-app-pub-1/3',
        adNetwork: AdNetwork.admob,
        adUnitType: AdUnitType.appOpen,
        capCooldown: Duration.zero,
        clock: clock,
      );
      final d = g.onFailure(AdErrorType.frequencyCapped);
      expect(d.retryAfter, isNull);
      expect(g.canLoad, isTrue);
    });
  });
}
