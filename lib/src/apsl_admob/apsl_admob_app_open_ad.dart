import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/app_open_pacing.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';

/// AdMob implementation of App Open ads.
///
/// Never shows late: [show] uses a cached, unexpired ad or shows nothing and
/// refreshes silently for the next time; [showWithin] waits a few seconds
/// for a load and gives up after that. [AppOpenPacing] holds the 4 h
/// cooldown and the minimum session; the next ad is preloaded in the
/// cooldown's last half hour while the app is in the foreground.
/// Load failures go through [LoadRetryGovernor]; a frequency-cap error
/// blocks loads for `capCooldown` (the app's `appOpenCapCooldown`).
class ApslAdmobAppOpenAd extends ApslAdBase {
  /// Maximum age of a cached app open ad before AdMob considers it stale.
  static const Duration maxCacheDuration = Duration(hours: 4);

  final AdRequest adRequest;
  final AppOpenPacing pacing;
  final LoadRetryGovernor _governor;

  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadTime;

  bool _isShowingAd = false;
  bool _isLoading = false;
  Timer? _retryTimer;
  Timer? _preloadTimer;
  Timer? _awaitedTimer;
  AwaitedAppOpenShow? _awaited;
  int _loadGeneration = 0;

  ApslAdmobAppOpenAd(
    super.adUnitId,
    this.adRequest, {
    AppOpenPacing? pacing,
    Duration capCooldown = Duration.zero,
  })  : pacing = pacing ?? AppOpenPacing(),
        _governor = LoadRetryGovernor(
          adUnitId: adUnitId,
          adNetwork: AdNetwork.admob,
          adUnitType: AdUnitType.appOpen,
          capCooldown: capCooldown,
        ) {
    _schedulePreload();
  }

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  AdUnitType get adUnitType => AdUnitType.appOpen;

  @override
  DateTime? get loadBlockedUntil => _governor.blockedUntil;

  @override
  void blockLoadsUntil(DateTime until) => _governor.blockUntil(until);

  @override
  bool get isAdLoaded => _appOpenAd != null && !_isExpired;

  /// Whether a cached ad has exceeded [maxCacheDuration].
  bool get _isExpired {
    final loadedAt = _appOpenLoadTime;
    if (loadedAt == null) return false;
    return DateTime.now().difference(loadedAt) > maxCacheDuration;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _preloadTimer?.cancel();
    _preloadTimer = null;
    _awaitedTimer?.cancel();
    _awaitedTimer = null;
    _awaited = null;
    _loadGeneration++;
    _dropCached();
    _isShowingAd = false;
    _isLoading = false;
    clearListeners();
  }

  void _dropCached() {
    _appOpenAd?.dispose();
    _appOpenAd = null;
    _appOpenLoadTime = null;
  }

  /// Silently preloads an app open ad. Never shows on its own.
  @override
  Future<void> load() => _load(isRetry: false);

  Future<void> _load({required bool isRetry}) async {
    if (_isExpired) _dropCached();
    if (isAdLoaded || forceStopToLoadAds || _isLoading) return;
    // No point holding an ad through a cooldown it would expire inside;
    // the last half hour of it is the preload window.
    if (!pacing.canLoad) return;

    final String? malformed = _governor.validateFormat();
    if (malformed != null) {
      fireAdFailedToLoad(null, malformed);
      return;
    }
    if (!_governor.canLoad) return;
    if (!isRetry) _governor.onNaturalLoad();

    _isLoading = true;
    _retryTimer?.cancel();
    final generation = ++_loadGeneration;

    try {
      await AppOpenAd.load(
        adUnitId: adUnitId,
        request: adRequest,
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (AppOpenAd ad) {
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _appOpenAd?.dispose();
            _appOpenAd = ad;
            _appOpenLoadTime = DateTime.now();
            _isLoading = false;
            _governor.onLoaded();
            fireAdLoaded(ad);
            _resolveAwaited(loaded: true);
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (generation != _loadGeneration) return;
            _appOpenAd = null;
            _isLoading = false;
            _handleError(mapLoadAdError(error), error.toString());
          },
        ),
      );
    } catch (e) {
      if (generation != _loadGeneration) return;
      _isLoading = false;
      _handleError(AdErrorType.unknown, e.toString());
    }
  }

  void _handleError(AdErrorType type, String message) {
    final decision = _governor.onFailure(type, message: message);
    _resolveAwaited(loaded: false);
    fireAdFailedToLoad(
      null,
      decision.disabledNow
          ? 'Unit disabled for this session: '
              '${DisabledAdUnits.reasonFor(adUnitId)}'
          : message,
    );
    final retryAfter = decision.retryAfter;
    if (retryAfter == null) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryAfter, () {
      if (!isAdLoaded && !_isLoading) _load(isRetry: true);
    });
  }

  /// Loads the next ad once the cooldown reaches its preload window, if the
  /// app is in the foreground then; otherwise the next resume's show request
  /// starts the load.
  void _schedulePreload() {
    _preloadTimer?.cancel();
    _preloadTimer = null;
    if (!pacing.inCooldown) return;
    _preloadTimer = Timer(pacing.timeUntilPreload, () {
      _preloadTimer = null;
      if (isAppInForeground) load();
    });
  }

  /// Shows a cached ad now. With nothing cached, starts a load and shows
  /// the ad only if it arrives within [timeout] and [stillEligible] still
  /// holds; otherwise this request gets no ad and a late arrival stays
  /// cached for the next one.
  void showWithin(Duration timeout, {bool Function()? stillEligible}) {
    if (isAdLoaded ||
        pacing.skipReason != null ||
        _isShowingAd ||
        !isAppInForeground) {
      return show();
    }
    if (_awaited != null) return;
    load();
    if (!_isLoading) return fireAdShowSkipped(_notLoadedReason);
    _awaited = AwaitedAppOpenShow(
      deadline: DateTime.now().add(timeout),
      stillEligible: stillEligible,
    );
    _awaitedTimer?.cancel();
    _awaitedTimer = Timer(timeout, () {
      if (_awaited == null) return;
      _awaited = null;
      fireAdShowSkipped('timeout');
    });
  }

  void _resolveAwaited({required bool loaded}) {
    final awaited = _awaited;
    if (awaited == null) return;
    _awaited = null;
    _awaitedTimer?.cancel();
    _awaitedTimer = null;
    if (!loaded) return fireAdShowSkipped('not_loaded');
    final String? skip = awaited.skipReasonAt(DateTime.now());
    if (skip != null) return fireAdShowSkipped(skip);
    show();
  }

  /// `cap` while AdMob's frequency cap holds the unit, so the app can tell
  /// a capped resume from a plain miss.
  String get _notLoadedReason =>
      _governor.blockedUntil != null ? 'cap' : 'not_loaded';

  @override
  void show() {
    final String? paced = pacing.skipReason;
    if (paced != null) {
      // A return inside the preload window caches the ad for the next one.
      if (pacing.inCooldown) load();
      return fireAdShowSkipped(paced);
    }
    if (_isShowingAd) return fireAdShowSkipped('showing');
    if (!isAppInForeground) return fireAdShowSkipped('background');

    if (!isAdLoaded) {
      // Refresh for next time; this resume gets no ad. Showing whatever
      // loads in a few seconds would put it over the screen the user has
      // already started using.
      if (_isExpired) _dropCached();
      fireAdShowSkipped(_notLoadedReason);
      load();
      return;
    }

    // Mark "showing" BEFORE the actual show() call to close the race
    // window where two foreground events can both pass the guard.
    _isShowingAd = true;

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (AppOpenAd ad) {
        pacing.recordShown();
        _schedulePreload();
        fireAdShowed(ad);
      },
      onAdDismissedFullScreenContent: (AppOpenAd ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        fireAdDismissed(ad);
        // No reload here: the cooldown that just started outlasts any ad
        // loaded now. The next resume after it refreshes.
      },
      onAdFailedToShowFullScreenContent: (AppOpenAd ad, AdError error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        fireAdFailedToShow(ad, error.toString());
      },
    );

    _appOpenAd!.show();
  }
}
