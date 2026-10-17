import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/apsl_admob/apsl_admob_interstitial_ad.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdmobAd extends Fake implements InterstitialAd {
  int disposed = 0;
  int shown = 0;

  @override
  FullScreenContentCallback<InterstitialAd>? fullScreenContentCallback;

  @override
  Future<void> setImmersiveMode(bool immersiveModeEnabled) async {}

  @override
  Future<void> show() async => shown++;

  @override
  Future<void> dispose() async => disposed++;
}

class _FakeGamAd extends Fake implements AdManagerInterstitialAd {
  int disposed = 0;

  @override
  Future<void> dispose() async => disposed++;
}

class _UnloadedInterstitial extends ApslAdBase {
  _UnloadedInterstitial() : super('ca-app-pub-1/9');

  int loads = 0;

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  AdUnitType get adUnitType => AdUnitType.interstitial;

  @override
  bool get isAdLoaded => false;

  @override
  Future<void> load() async => loads++;

  @override
  void show() {}

  @override
  void dispose() => clearListeners();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // A malformed id makes the reload fail before any platform call, and the
  // failure is how a test sees that the reload ran.
  const badId = 'not-a-unit';
  const age = Duration(milliseconds: 40);
  const config = InterstitialAdConfig(maxCacheAge: age, enableAutoRetry: false);
  const pastAge = Duration(milliseconds: 120);

  setUp(() {
    DisabledAdUnits.reset();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(DisabledAdUnits.reset);

  List<String?> loadFailures(ApslAdBase ad) {
    final failures = <String?>[];
    ad.addOnAdFailedToLoad(
      (network, type, data, {errorMessage, rewardType, rewardAmount}) =>
          failures.add(errorMessage),
    );
    return failures;
  }

  test('admob: an unshown ad expires on time and reloads', () async {
    final ad = ApslAdmobInterstitialAd(badId, config: config);
    final failures = loadFailures(ad);
    final cached = _FakeAdmobAd();
    ad.debugOnLoaded(cached);
    expect(ad.isAdLoaded, isTrue);

    await Future<void>.delayed(pastAge);
    expect(ad.isAdLoaded, isFalse);
    expect(cached.disposed, 1);
    expect(failures, hasLength(1));
    ad.dispose();
  });

  test('admob: in the background it drops without loading', () async {
    final ad = ApslAdmobInterstitialAd(badId, config: config);
    final failures = loadFailures(ad);
    final cached = _FakeAdmobAd();
    ad.debugOnLoaded(cached);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    await Future<void>.delayed(pastAge);
    expect(ad.isAdLoaded, isFalse);
    expect(cached.disposed, 1);
    expect(failures, isEmpty);
    ad.dispose();
  });

  test('admob: a show cancels the expiry', () async {
    final ad = ApslAdmobInterstitialAd(
      badId,
      config: config.copyWith(autoReloadAfterShow: false),
    );
    final failures = loadFailures(ad);
    final cached = _FakeAdmobAd();
    ad.debugOnLoaded(cached);
    ad.show();
    expect(cached.shown, 1);

    await Future<void>.delayed(pastAge);
    expect(cached.disposed, 0);
    expect(failures, isEmpty);
    ad.dispose();
  });

  test('admob: dispose cancels the expiry', () async {
    final ad = ApslAdmobInterstitialAd(badId, config: config);
    final cached = _FakeAdmobAd();
    ad.debugOnLoaded(cached);
    ad.dispose();
    final failures = loadFailures(ad);

    await Future<void>.delayed(pastAge);
    expect(cached.disposed, 1);
    expect(failures, isEmpty);
  });

  test('gam: an unshown ad expires on time and reloads', () async {
    final ad = ApslGamInterstitialAd(badId, config: config);
    final failures = loadFailures(ad);
    final cached = _FakeGamAd();
    ad.debugOnLoaded(cached);
    expect(ad.isAdLoaded, isTrue);

    await Future<void>.delayed(pastAge);
    expect(ad.isAdLoaded, isFalse);
    expect(cached.disposed, 1);
    expect(failures, hasLength(1));
    ad.dispose();
  });

  test('showAd with nothing loaded reports not_loaded', () async {
    final unit = _UnloadedInterstitial();
    ApslAds.instance.debugRegister(unit);
    final events = <AdEvent>[];
    final sub = ApslAds.instance.onEvent.listen(events.add);

    expect(ApslAds.instance.showAd(AdUnitType.interstitial), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(unit.loads, 1);
    final skip = events.singleWhere((e) => e.type == AdEventType.adShowSkipped);
    expect(skip.adUnitType, AdUnitType.interstitial);
    expect(skip.error, 'not_loaded');
    await sub.cancel();
  });
}
