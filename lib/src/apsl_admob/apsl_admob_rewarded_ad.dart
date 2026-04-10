import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/rewarded_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A class that encapsulates the logic for AdMob's Rewarded Ads.
///
/// Includes configurable retry logic with exponential backoff, error-code-
/// based classification, timeout support, and a generation token to discard
/// stale callbacks from a load that has already been cancelled.
class ApslAdmobRewardedAd extends ApslAdBase {
  final AdRequest _adRequest;
  final RewardedAdConfig _config;

  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;
  int _loadGeneration = 0;

  /// Creates a new [ApslAdmobRewardedAd] instance
  ApslAdmobRewardedAd(
    super.adUnitId, {
    AdRequest? adRequest,
    RewardedAdConfig? config,
  })  : _adRequest = adRequest ?? const AdRequest(),
        _config = config ?? const RewardedAdConfig();

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  AdUnitType get adUnitType => AdUnitType.rewarded;

  @override
  bool get isAdLoaded => _isAdLoaded;

  /// Gets the current retry count
  int get retryCount => _retryCount;

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdLoaded = false;
    _isLoading = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _retryCount = 0;
    _loadGeneration++;
    clearListeners();
  }

  @override
  Future<void> load() async {
    if (_isLoading || _isAdLoaded) return;

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
          errorMessage: 'Rewarded ad load timed out',
        );
      });
    }

    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: _adRequest,
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _rewardedAd?.dispose();
            _rewardedAd = ad;
            _isAdLoaded = true;
            _isLoading = false;
            _retryCount = 0;
            _loadTimeoutTimer?.cancel();
            fireAdLoaded(ad);
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (generation != _loadGeneration) return;
            _rewardedAd = null;
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
  /// and under [RewardedAdConfig.maxRetries].
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
  dynamic show() {
    final ad = _rewardedAd;
    if (ad == null || !_isAdLoaded) return;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        fireAdShowed(ad);
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        fireAdDismissed(ad);
        _cleanAndReload(ad);
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        fireAdFailedToShow(ad, error.toString());
        _cleanAndReload(ad);
      },
    );

    ad.setImmersiveMode(_config.immersiveModeEnabled);

    ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      fireEarnedReward(
        reward.type,
        rewardType: reward.type,
        rewardAmount: reward.amount,
      );
    });

    _rewardedAd = null;
    _isAdLoaded = false;
  }

  /// Cleans up the ad and optionally reloads for next use.
  ///
  /// The reload is gated only on [RewardedAdConfig.autoReloadAfterShow]
  /// — `preLoadRewardedAds` controls whether the *initial* preload happens
  /// at app start, but post-show preloading is what gives the next user tap
  /// an instant ad and is the single biggest revenue lever for rewarded.
  void _cleanAndReload(RewardedAd ad) {
    ad.dispose();
    _rewardedAd = null;
    _isAdLoaded = false;

    if (_config.autoReloadAfterShow) {
      load();
    }
  }

  /// Manually triggers a retry of the ad load.
  ///
  /// Resets the retry counter so the user-initiated retry gets a fresh
  /// budget of [RewardedAdConfig.maxRetries] attempts.
  Future<void> retry() async {
    _retryCount = 0;
    await load();
  }

  /// Gets the current configuration
  RewardedAdConfig get config => _config;
}
