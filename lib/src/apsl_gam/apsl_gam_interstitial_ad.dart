import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/interstitial_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google Ad Manager (GAM) interstitial ads.
///
/// Keeps at most one cached ad. It reloads once right after a show (the
/// next one is then ready well inside the app's cooldown) and otherwise only
/// when asked; failures go through [LoadRetryGovernor] instead of a backoff
/// loop. A cached ad older than [InterstitialAdConfig.maxCacheAge] is
/// dropped. Stale callbacks from a superseded load are ignored via a
/// generation token.
class ApslGamInterstitialAd extends ApslAdBase {
  final InterstitialAdConfig _config;
  final LoadRetryGovernor _governor;

  AdManagerInterstitialAd? _interstitialAd;
  DateTime? _loadedAt;
  bool _isLoading = false;
  bool _isShowing = false;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;

  /// Monotonically increasing token used to identify the current in-flight
  /// load. Stale callbacks from a previous load (e.g. one that was already
  /// timed out) check this and bail out instead of clobbering newer state.
  int _loadGeneration = 0;

  ApslGamInterstitialAd(
    super.adUnitId, {
    InterstitialAdConfig? config,
  })  : _config = config ?? const InterstitialAdConfig(),
        _governor = LoadRetryGovernor(
          adUnitId: adUnitId,
          adNetwork: AdNetwork.adManager,
          adUnitType: AdUnitType.interstitial,
          capCooldown: (config ?? const InterstitialAdConfig()).capCooldown,
          noFillRetryDelay:
              (config ?? const InterstitialAdConfig()).noFillRetryDelay,
        );

  @override
  AdNetwork get adNetwork => AdNetwork.adManager;

  @override
  AdUnitType get adUnitType => AdUnitType.interstitial;

  @override
  DateTime? get loadBlockedUntil => _governor.blockedUntil;

  @override
  void blockLoadsUntil(DateTime until) => _governor.blockUntil(until);

  @override
  bool get isAdLoaded => _interstitialAd != null && !_isStale;

  bool get _isStale {
    final loadedAt = _loadedAt;
    return loadedAt != null &&
        DateTime.now().difference(loadedAt) > _config.maxCacheAge;
  }

  @override
  void dispose() {
    _isLoading = false;
    _isShowing = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _loadGeneration++; // invalidate any in-flight callbacks
    _dropCached();
    clearListeners();
  }

  void _dropCached() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _loadedAt = null;
  }

  /// A load the app asked for. Our own retry goes through [_load] with
  /// `isRetry: true`, so it can't reset the retry budget.
  @override
  Future<void> load() => _load(isRetry: false);

  Future<void> _load({required bool isRetry}) async {
    if (_isStale) _dropCached();
    if (isAdLoaded || _isLoading) return;

    final String? malformed = _governor.validateFormat();
    if (malformed != null) {
      fireAdFailedToLoad(null, malformed);
      return;
    }
    if (!_governor.canLoad) return;
    if (!isRetry) _governor.onNaturalLoad();

    _isLoading = true;
    _loadTimeoutTimer?.cancel();
    _retryTimer?.cancel();

    final generation = ++_loadGeneration;

    final timeout = _config.loadTimeout;
    if (timeout != null) {
      _loadTimeoutTimer = Timer(timeout, () {
        if (generation != _loadGeneration || isAdLoaded) return;
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
            // Ignore late callbacks for a load that was superseded.
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _interstitialAd?.dispose();
            _interstitialAd = ad;
            _loadedAt = DateTime.now();
            _isLoading = false;
            _loadTimeoutTimer?.cancel();
            _governor.onLoaded();
            fireAdLoaded(ad);
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (generation != _loadGeneration) return;
            _interstitialAd = null;
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
    final decision = _governor.onFailure(errorType, message: errorMessage);
    fireAdFailedToLoad(
      null,
      decision.disabledNow
          ? 'Unit disabled for this session: '
              '${DisabledAdUnits.reasonFor(adUnitId)}'
          : errorMessage ?? errorType.message,
    );

    final retryAfter = decision.retryAfter;
    if (!_config.enableAutoRetry || retryAfter == null) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryAfter, () {
      if (!isAdLoaded && !_isLoading) _load(isRetry: true);
    });
  }

  @override
  void show() {
    if (_isShowing) return fireAdShowSkipped('showing');
    if (!isAppInForeground) return fireAdShowSkipped('background');
    if (_isStale) _dropCached();
    final ad = _interstitialAd;
    if (ad == null) return fireAdShowSkipped('not_loaded');

    _isShowing = true;
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
    _loadedAt = null;
  }

  /// Disposes the shown ad and loads the next one — the single load after a
  /// show that keeps an ad ready for the next allowed slot.
  void _cleanAndReload(AdManagerInterstitialAd ad) {
    ad.dispose();
    _isShowing = false;
    _isLoading = false;

    if (_config.autoReloadAfterShow) {
      load();
    }
  }

  /// Manually triggers a load with a fresh retry budget.
  Future<void> retry() => load();

  /// Gets the current configuration
  InterstitialAdConfig get config => _config;
}
