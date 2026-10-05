import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/banner_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob implementation of banner ads.
///
/// This class handles the creation, loading, and display of AdMob banner ads.
/// It includes configurable retry logic with exponential backoff, error-code-
/// based classification, support for loading placeholders, and a generation
/// token to discard stale callbacks from a load that has already been
/// cancelled.
class ApslAdmobBannerAd extends ApslAdBase {
  final AdRequest _adRequest;
  final AdSize adSize;
  final BannerAdConfig _config;

  /// The banner ad instance
  BannerAd? _bannerAd;

  /// Whether the ad is currently loaded
  bool _isAdLoaded = false;

  /// Whether the ad is currently loading
  bool _isLoading = false;

  /// Number of retry attempts made
  int _retryCount = 0;

  /// Whether max retries have been reached
  bool _maxRetriesReached = false;

  /// Timer for retry delay
  Timer? _retryTimer;

  /// Timer for load timeout
  Timer? _loadTimeoutTimer;

  /// Monotonically increasing token used to discard stale callbacks.
  int _loadGeneration = 0;

  /// Creates a new [ApslAdmobBannerAd] instance
  ApslAdmobBannerAd(
    super.adUnitId, {
    AdRequest? adRequest,
    this.adSize = AdSize.banner,
    BannerAdConfig? config,
  })  : _adRequest = adRequest ?? const AdRequest(),
        _config = config ?? const BannerAdConfig();

  @override
  AdUnitType get adUnitType => AdUnitType.banner;

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  bool get isAdLoaded => _isAdLoaded;

  /// Gets the current retry count
  int get retryCount => _retryCount;

  /// Gets whether the ad is currently loading
  bool get isLoading => _isLoading;

  /// Gets whether max retries have been reached
  bool get maxRetriesReached => _maxRetriesReached;

  @override
  void dispose() {
    _cancelTimers();
    _isAdLoaded = false;
    _isLoading = false;
    _retryCount = 0;
    _maxRetriesReached = false;
    _loadGeneration++;
    _bannerAd?.dispose();
    _bannerAd = null;
    clearListeners();
  }

  /// Cancels any active timers
  void _cancelTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  /// Single entry point for handling any load failure (SDK error or timeout).
  ///
  /// Schedules an exponential-backoff retry when applicable; otherwise marks
  /// the slot as exhausted and notifies the widget to rebuild.
  void _handleLoadFailure(
    AdErrorType errorType, {
    required String errorMessage,
    Ad? ad,
  }) {
    _isAdLoaded = false;
    _isLoading = false;
    _cancelTimers();

    if (!silenceDeadUnit(adUnitId, adUnitType, errorType, errorMessage)) {
      fireAdFailedToLoad(ad, errorMessage);
    }

    ad?.dispose();

    final canRetry = _config.enableAutoRetry &&
        isErrorRetryable(errorType) &&
        _retryCount < _config.maxRetries;

    if (canRetry) {
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
    } else {
      // Max retries reached or error not retryable - notify widget to rebuild.
      _maxRetriesReached = true;
      _retryCount = 0;
      fireBannerAdReadyForSetState(ad);
    }
  }

  @override
  Future<void> load() async {
    if (_isLoading) return;
    if (_isAdLoaded && _bannerAd != null) return;
    if (DisabledAdUnits.isDisabled(adUnitId)) {
      _maxRetriesReached = true;
      fireBannerAdReadyForSetState(null);
      return;
    }
    final String? malformed = checkUnitShape(adUnitId, adNetwork, adUnitType);
    if (malformed != null) {
      _maxRetriesReached = true;
      fireAdFailedToLoad(null, malformed);
      fireBannerAdReadyForSetState(null);
      return;
    }

    _isLoading = true;
    _cancelTimers();

    final generation = ++_loadGeneration;

    // Dispose existing ad if any
    await _bannerAd?.dispose();
    _bannerAd = null;
    _isAdLoaded = false;

    // Set up load timeout if configured
    final timeout = _config.loadTimeout;
    if (timeout != null) {
      _loadTimeoutTimer = Timer(timeout, () {
        if (generation != _loadGeneration || !_isLoading) return;
        _handleLoadFailure(
          AdErrorType.timeout,
          errorMessage:
              'Banner ad load timeout after ${timeout.inSeconds} seconds',
        );
      });
    }

    try {
      _bannerAd = BannerAd(
        size: adSize,
        adUnitId: adUnitId,
        listener: BannerAdListener(
          onAdLoaded: (Ad ad) {
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _cancelTimers();
            _bannerAd = ad as BannerAd;
            _isAdLoaded = true;
            _isLoading = false;
            _retryCount = 0;
            _maxRetriesReached = false;

            fireAdLoaded(ad);
            fireBannerAdReadyForSetState(ad);
          },
          onAdFailedToLoad: (Ad ad, LoadAdError error) {
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _handleLoadFailure(
              mapLoadAdError(error),
              errorMessage:
                  '${mapLoadAdError(error).message} (${error.message})',
              ad: ad,
            );
          },
          onAdOpened: (Ad ad) => fireAdClicked(ad),
          onAdClosed: (Ad ad) => fireAdDismissed(ad),
          onAdImpression: (Ad ad) => fireAdShowed(ad),
        ),
        request: _adRequest,
      )..load();
    } catch (e) {
      if (generation != _loadGeneration) return;
      _handleLoadFailure(AdErrorType.unknown, errorMessage: e.toString());
    }
  }

  @override
  Widget show() {
    // If max retries have been reached, return zero-height widget
    if (_maxRetriesReached) {
      return const SizedBox.shrink();
    }

    // If ad is not loaded, trigger load and show loading widget.
    // The load() call is internally guarded by _isLoading so reentrant
    // build() invocations don't stack up requests.
    if (_bannerAd == null || !_isAdLoaded) {
      if (!_isLoading) {
        load();
      }

      // Collapse to zero height while loading (or after a failure that will
      // retry): reserving adSize.height for an ad that may never fill leaves a
      // blank band in the layout. Hosts that WANT a placeholder can opt in via
      // _config.loadingWidget. Once the ad fills, show() returns the sized
      // Container below and the space appears only when there's real fill.
      return _config.loadingWidget ?? const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      height: adSize.height.toDouble(),
      width: adSize.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  /// Manually triggers a retry of the ad load.
  Future<void> retry() async {
    _retryCount = 0;
    _maxRetriesReached = false;
    await load();
  }

  /// Gets the current configuration
  BannerAdConfig get config => _config;
}
