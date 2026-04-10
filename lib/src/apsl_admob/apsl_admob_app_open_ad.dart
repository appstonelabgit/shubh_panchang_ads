import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';

/// AdMob implementation of App Open ads.
///
/// Handles the load → show → reload cycle with bounded exponential backoff,
/// expiry-aware caching (AdMob app-open ads expire after 4 hours), and a
/// cancellable retry timer that is properly torn down on [dispose].
class ApslAdmobAppOpenAd extends ApslAdBase {
  /// Maximum age of a cached app open ad before AdMob considers it stale.
  static const Duration maxCacheDuration = Duration(hours: 4);

  /// Default max retry attempts on load failure.
  static const int defaultMaxRetries = 5;

  final AdRequest adRequest;
  final int maxRetries;

  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadTime;

  bool _isShowingAd = false;
  bool _isLoading = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  int _loadGeneration = 0;

  ApslAdmobAppOpenAd(
    super.adUnitId,
    this.adRequest, {
    this.maxRetries = defaultMaxRetries,
  });

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

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
    _appOpenAd?.dispose();
    _appOpenAd = null;
    _appOpenLoadTime = null;
    _isShowingAd = false;
    _isLoading = false;
    _retryCount = 0;
    clearListeners();
  }

  /// Silently preloads an app open ad. Use this for background warming
  /// (cold start, post-dismiss). Does NOT auto-show on success.
  @override
  Future<void> load() => _load(showAdOnLoad: false);

  /// Loads the app open ad and shows it as soon as it is ready.
  ///
  /// Use this when you want a "load and show now" flow (e.g. an explicit
  /// user-initiated splash). For background preloading at app start, use
  /// [load] instead.
  Future<void> loadAndShow() => _load(showAdOnLoad: true);

  Future<void> _load({bool showAdOnLoad = false}) async {
    if (isAdLoaded) {
      if (showAdOnLoad) show();
      return;
    }
    if (forceStopToLoadAds || _isLoading) return;

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
            _retryCount = 0;
            fireAdLoaded(ad);

            if (showAdOnLoad) show();
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (generation != _loadGeneration) return;
            _appOpenAd = null;
            _isLoading = false;
            fireAdFailedToLoad(error, error.toString());
            _scheduleRetry(error, showAdOnLoad: showAdOnLoad);
          },
        ),
      );
    } catch (e) {
      if (generation != _loadGeneration) return;
      _isLoading = false;
      fireAdFailedToLoad(null, e.toString());
    }
  }

  /// Schedules a bounded, exponentially-backed-off retry. Errors that
  /// can't recover (invalid ad unit / missing app id) are not retried.
  void _scheduleRetry(LoadAdError error, {required bool showAdOnLoad}) {
    final type = mapLoadAdError(error);
    if (!isErrorRetryable(type)) return;
    if (_retryCount >= maxRetries) return;

    final delay = nextBackoff(_retryCount);
    _retryCount++;
    _retryTimer = Timer(delay, () {
      if (!isAdLoaded && !_isLoading) _load(showAdOnLoad: showAdOnLoad);
    });
  }

  @override
  void show() {
    // Expired cache → refresh and auto-show on success.
    if (_appOpenAd != null && _isExpired) {
      _appOpenAd?.dispose();
      _appOpenAd = null;
      _appOpenLoadTime = null;
      fireAdFailedToShow(null, 'Cached ad expired. Loading a fresh one.');
      _load(showAdOnLoad: true);
      return;
    }

    if (!isAdLoaded) {
      fireAdFailedToShow(
        null,
        'No ad loaded. Triggered load and will auto-show if successful.',
      );
      _load(showAdOnLoad: true);
      return;
    }

    if (_isShowingAd) {
      fireAdFailedToShow(null, 'Ad is already being shown.');
      return;
    }

    // Mark "showing" BEFORE the actual show() call to close the race
    // window where two foreground events can both pass the guard.
    _isShowingAd = true;

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (AppOpenAd ad) {
        fireAdShowed(ad);
      },
      onAdDismissedFullScreenContent: (AppOpenAd ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        fireAdDismissed(ad);
        // Pre-warm the next ad so the next foreground is instant.
        _load(showAdOnLoad: false);
      },
      onAdFailedToShowFullScreenContent: (AppOpenAd ad, AdError error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        fireAdFailedToShow(ad, error.toString());
        // Try again so the slot doesn't stay dead.
        _load(showAdOnLoad: false);
      },
    );

    _appOpenAd!.show();
  }
}
