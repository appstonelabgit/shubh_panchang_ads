import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/app_open_pacing.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';

/// Google Ad Manager (GAM) implementation of App Open ads.
///
/// Never shows late: [show] uses a cached, unexpired ad or shows nothing and
/// refreshes silently for the next time. [AppOpenPacing] holds the 4 h
/// cooldown and the minimum session; no load starts inside the cooldown.
/// Load failures go through [LoadRetryGovernor].
class ApslGamAppOpenAd extends ApslAdBase {
  /// Maximum age of a cached app open ad before AdMob considers it stale.
  static const Duration maxCacheDuration = Duration(hours: 4);

  final AppOpenPacing pacing;
  final LoadRetryGovernor _governor;

  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadTime;

  bool _isShowingAd = false;
  bool _isLoading = false;
  Timer? _retryTimer;
  int _loadGeneration = 0;

  ApslGamAppOpenAd(
    super.adUnitId, {
    AppOpenPacing? pacing,
    Duration capCooldown = const Duration(hours: 4),
  })  : pacing = pacing ?? AppOpenPacing(),
        _governor = LoadRetryGovernor(
          adUnitId: adUnitId,
          adNetwork: AdNetwork.adManager,
          adUnitType: AdUnitType.appOpen,
          capCooldown: capCooldown,
        );

  @override
  AdNetwork get adNetwork => AdNetwork.adManager;

  @override
  AdUnitType get adUnitType => AdUnitType.appOpen;

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
    // No point holding an ad through a cooldown it would expire inside.
    if (pacing.inCooldown) return;

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
      await AppOpenAd.loadWithAdManagerAdRequest(
        adUnitId: adUnitId,
        adManagerAdRequest: const AdManagerAdRequest(),
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

  @override
  void show() {
    final String? paced = pacing.skipReason;
    if (paced != null) return fireAdShowSkipped(paced);
    if (_isShowingAd) return fireAdShowSkipped('showing');
    if (!isAppInForeground) return fireAdShowSkipped('background');

    if (!isAdLoaded) {
      // Refresh for next time; this resume gets no ad. Showing whatever
      // loads in a few seconds would put it over the screen the user has
      // already started using.
      if (_isExpired) _dropCached();
      fireAdShowSkipped('not_loaded');
      load();
      return;
    }

    // Mark "showing" BEFORE the actual show() call to close the race
    // window where two foreground events can both pass the guard.
    _isShowingAd = true;

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (AppOpenAd ad) {
        pacing.recordShown();
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
