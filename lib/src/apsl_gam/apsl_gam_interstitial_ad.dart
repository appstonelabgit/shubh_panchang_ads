import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/interstitial_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google Ad Manager (GAM) implementation of interstitial ads.
///
/// Uses [AdManagerInterstitialAd] and [AdManagerAdRequest] instead of
/// [InterstitialAd] and [AdRequest]. Otherwise identical to
/// [ApslAdmobInterstitialAd] in behavior and retry logic.
class ApslGamInterstitialAd extends ApslAdBase {
  final InterstitialAdConfig _config;

  AdManagerInterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;
  int _loadGeneration = 0;

  ApslGamInterstitialAd(
    super.adUnitId, {
    InterstitialAdConfig? config,
  }) : _config = config ?? const InterstitialAdConfig();

  @override
  AdNetwork get adNetwork => AdNetwork.adManager;

  @override
  AdUnitType get adUnitType => AdUnitType.interstitial;

  @override
  bool get isAdLoaded => _isAdLoaded;

  int get retryCount => _retryCount;

  @override
  void dispose() {
    _isAdLoaded = false;
    _isLoading = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _retryCount = 0;
    _loadGeneration++;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    clearListeners();
  }

  @override
  Future<void> load() async {
    if (_isAdLoaded || _isLoading) return;

    _isLoading = true;
    _loadTimeoutTimer?.cancel();
    _retryTimer?.cancel();

    final generation = ++_loadGeneration;

    final timeout = _config.loadTimeout;
    if (timeout != null) {
      _loadTimeoutTimer = Timer(timeout, () {
        if (generation != _loadGeneration || _isAdLoaded) return;
        _isLoading = false;
        _handleError(
          AdErrorType.timeout,
          errorMessage: 'GAM interstitial ad load timed out',
        );
      });
    }

    try {
      await AdManagerInterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdManagerAdRequest(),
        adLoadCallback: AdManagerInterstitialAdLoadCallback(
          onAdLoaded: (AdManagerInterstitialAd ad) {
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _interstitialAd?.dispose();
            _interstitialAd = ad;
            _isAdLoaded = true;
            _isLoading = false;
            _retryCount = 0;
            _loadTimeoutTimer?.cancel();
            fireAdLoaded(ad);
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (generation != _loadGeneration) return;
            _interstitialAd = null;
            _isAdLoaded = false;
            _isLoading = false;
            _loadTimeoutTimer?.cancel();
            _handleError(
              mapLoadAdError(error),
              errorMessage: error.toString(),
            );
          },
        ),
      );
    } catch (e) {
      if (generation != _loadGeneration) return;
      _isLoading = false;
      _loadTimeoutTimer?.cancel();
      _handleError(AdErrorType.unknown, errorMessage: e.toString());
    }
  }

  void _handleError(AdErrorType errorType, {String? errorMessage}) {
    fireAdFailedToLoad(null, errorMessage ?? errorType.message);

    if (!_config.enableAutoRetry || !isErrorRetryable(errorType)) return;
    if (_retryCount >= _config.maxRetries) return;

    final delay = _config.useExponentialBackoff
        ? nextBackoff(_retryCount,
            base: _config.retryDelay, maxDelay: _config.maxRetryDelay)
        : _config.retryDelay;
    _retryCount++;
    _retryTimer = Timer(delay, () {
      if (!_isAdLoaded && !_isLoading) load();
    });
  }

  @override
  void show() {
    final ad = _interstitialAd;
    if (ad == null || !_isAdLoaded) return;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (AdManagerInterstitialAd ad) {
        fireAdShowed(ad);
      },
      onAdDismissedFullScreenContent: (AdManagerInterstitialAd ad) {
        fireAdDismissed(ad);
        _cleanAndReload(ad);
      },
      onAdFailedToShowFullScreenContent:
          (AdManagerInterstitialAd ad, AdError error) {
        fireAdFailedToShow(ad, error.toString());
        _cleanAndReload(ad);
      },
    );

    ad.setImmersiveMode(_config.immersiveModeEnabled);
    ad.show();

    _interstitialAd = null;
    _isAdLoaded = false;
  }

  void _cleanAndReload(AdManagerInterstitialAd ad) {
    ad.dispose();
    _interstitialAd = null;
    _isAdLoaded = false;
    _isLoading = false;

    if (_config.autoReloadAfterShow) {
      load();
    }
  }

  Future<void> retry() async {
    _retryCount = 0;
    await load();
  }

  InterstitialAdConfig get config => _config;
}
