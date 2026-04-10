import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/interstitial_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A class that encapsulates the logic for AdMob's Interstitial Ads.
///
/// This class handles the creation, loading, and display of AdMob interstitial
/// ads. It includes configurable retry logic with exponential backoff,
/// error-code-based classification, and timeout support. Stale callbacks
/// from a load that has already been cancelled by a timeout are ignored via
/// a generation token.
class ApslAdmobInterstitialAd extends ApslAdBase {
  final AdRequest _adRequest;
  final InterstitialAdConfig _config;

  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;

  /// Monotonically increasing token used to identify the current in-flight
  /// load. Stale callbacks from a previous load (e.g. one that was already
  /// timed out) check this and bail out instead of clobbering newer state.
  int _loadGeneration = 0;

  /// Creates a new [ApslAdmobInterstitialAd] instance
  ApslAdmobInterstitialAd(
    super.adUnitId, {
    AdRequest? adRequest,
    InterstitialAdConfig? config,
  })  : _adRequest = adRequest ?? const AdRequest(),
        _config = config ?? const InterstitialAdConfig();

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  AdUnitType get adUnitType => AdUnitType.interstitial;

  @override
  bool get isAdLoaded => _isAdLoaded;

  /// Gets the current retry count
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
    _loadGeneration++; // invalidate any in-flight callbacks
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

    // Setup timeout if configured
    final timeout = _config.loadTimeout;
    if (timeout != null) {
      _loadTimeoutTimer = Timer(timeout, () {
        if (generation != _loadGeneration || _isAdLoaded) return;
        _isLoading = false;
        _handleError(
          AdErrorType.timeout,
          errorMessage: 'Interstitial ad load timed out',
        );
      });
    }

    try {
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: _adRequest,
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            // Ignore late callbacks for a load that was superseded.
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

  /// Handles ad load errors, retrying with exponential backoff if enabled
  /// and under [InterstitialAdConfig.maxRetries].
  void _handleError(AdErrorType errorType, {String? errorMessage}) {
    fireAdFailedToLoad(null, errorMessage ?? errorType.message);

    if (!_config.enableAutoRetry || !isErrorRetryable(errorType)) return;
    if (_retryCount >= _config.maxRetries) return;

    final delay = _config.useExponentialBackoff
        ? nextBackoff(
            _retryCount,
            base: _config.retryDelay,
            maxDelay: _config.maxRetryDelay,
          )
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
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        fireAdShowed(ad);
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        fireAdDismissed(ad);
        _cleanAndReload(ad);
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        fireAdFailedToShow(ad, error.toString());
        _cleanAndReload(ad);
      },
    );

    ad.setImmersiveMode(_config.immersiveModeEnabled);
    ad.show();

    _interstitialAd = null;
    _isAdLoaded = false;
  }

  /// Cleans up the ad and optionally reloads for next use
  void _cleanAndReload(InterstitialAd ad) {
    ad.dispose();
    _interstitialAd = null;
    _isAdLoaded = false;
    _isLoading = false;

    if (_config.autoReloadAfterShow) {
      load(); // Preload next ad
    }
  }

  /// Manually triggers a retry of the ad load.
  ///
  /// Resets the retry counter so the user-initiated retry gets a fresh
  /// budget of [InterstitialAdConfig.maxRetries] attempts.
  Future<void> retry() async {
    _retryCount = 0;
    await load();
  }

  /// Gets the current configuration
  InterstitialAdConfig get config => _config;
}
