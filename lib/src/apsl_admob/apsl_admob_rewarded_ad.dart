import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/rewarded_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A class that encapsulates the logic for AdMob's Rewarded Ads.
///
/// Loads only on demand, with a timeout and a generation token to discard
/// stale callbacks from a load that has already been cancelled. Never
/// preloads, retries in the background, or reloads after a show.
class ApslAdmobRewardedAd extends ApslAdBase {
  final AdRequest _adRequest;
  final RewardedAdConfig _config;
  final LoadRetryGovernor _governor;
  bool _isShowing = false;

  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  Timer? _loadTimeoutTimer;
  int _loadGeneration = 0;

  /// Creates a new [ApslAdmobRewardedAd] instance
  ApslAdmobRewardedAd(
    super.adUnitId, {
    AdRequest? adRequest,
    RewardedAdConfig? config,
  })  : _adRequest = adRequest ?? const AdRequest(),
        _config = config ?? const RewardedAdConfig(),
        _governor = LoadRetryGovernor(
          adUnitId: adUnitId,
          adNetwork: AdNetwork.admob,
          adUnitType: AdUnitType.rewarded,
        );

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  AdUnitType get adUnitType => AdUnitType.rewarded;

  @override
  bool get isAdLoaded => _isAdLoaded;

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdLoaded = false;
    _isLoading = false;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _loadGeneration++;
    clearListeners();
  }

  @override
  Future<void> load() async {
    if (_isLoading || _isAdLoaded) return;
    final String? malformed = _governor.validateFormat();
    if (malformed != null) {
      fireAdFailedToLoad(null, malformed);
      return;
    }
    if (!_governor.canLoad) return;

    _isLoading = true;
    _loadTimeoutTimer?.cancel();

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
            _governor.onLoaded();
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

  /// Rewarded ads load only on demand ([ApslAds.loadAndShowRewardedAd]),
  /// whose caller is waiting with a timeout — so a failure is reported and
  /// never retried in the background. A unit that can never load is
  /// disabled for the session with one clear event.
  void _handleError(AdErrorType errorType, {String? errorMessage}) {
    final decision = _governor.onFailure(errorType, message: errorMessage);
    fireAdFailedToLoad(
      null,
      decision.disabledNow
          ? 'Unit disabled for this session: '
              '${DisabledAdUnits.reasonFor(adUnitId)}'
          : errorMessage ?? errorType.message,
    );
  }

  @override
  dynamic show() {
    final ad = _rewardedAd;
    if (_isShowing) return fireAdShowSkipped('showing');
    if (!isAppInForeground) return fireAdShowSkipped('background');
    if (ad == null || !_isAdLoaded) return fireAdShowSkipped('not_loaded');
    _isShowing = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        fireAdShowed(ad);
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        _isShowing = false;
        fireAdDismissed(ad);
        _cleanAndReload(ad);
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        _isShowing = false;
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

  /// Cleans up the shown ad. No reload: the next one loads when the user
  /// asks for it.
  void _cleanAndReload(RewardedAd ad) {
    ad.dispose();
    _rewardedAd = null;
    _isAdLoaded = false;
  }

  /// Gets the current configuration
  RewardedAdConfig get config => _config;
}
