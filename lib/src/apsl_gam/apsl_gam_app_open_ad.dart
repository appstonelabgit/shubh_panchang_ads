import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';

/// Google Ad Manager (GAM) implementation of App Open ads.
///
/// Uses [AppOpenAd.loadWithAdManagerAdRequest] and [AdManagerAdRequest]
/// instead of [AppOpenAd.load] and [AdRequest]. Otherwise identical to
/// [ApslAdmobAppOpenAd] in behavior and retry logic.
class ApslGamAppOpenAd extends ApslAdBase {
  static const Duration maxCacheDuration = Duration(hours: 4);
  static const int defaultMaxRetries = 5;

  final int maxRetries;

  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadTime;

  bool _isShowingAd = false;
  bool _isLoading = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  int _loadGeneration = 0;

  ApslGamAppOpenAd(
    super.adUnitId, {
    this.maxRetries = defaultMaxRetries,
  });

  @override
  AdNetwork get adNetwork => AdNetwork.adManager;

  @override
  AdUnitType get adUnitType => AdUnitType.appOpen;

  @override
  bool get isAdLoaded => _appOpenAd != null && !_isExpired;

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

  @override
  Future<void> load() => _load(showAdOnLoad: false);

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
          null, 'No ad loaded. Triggered load and will auto-show.');
      _load(showAdOnLoad: true);
      return;
    }

    if (_isShowingAd) {
      fireAdFailedToShow(null, 'Ad is already being shown.');
      return;
    }

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
        _load(showAdOnLoad: false);
      },
      onAdFailedToShowFullScreenContent: (AppOpenAd ad, AdError error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        fireAdFailedToShow(ad, error.toString());
        _load(showAdOnLoad: false);
      },
    );

    _appOpenAd!.show();
  }
}
