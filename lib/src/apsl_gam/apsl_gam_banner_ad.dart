import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/config/banner_ad_config.dart';
import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google Ad Manager (GAM) implementation of banner ads.
///
/// Mirrors [ApslAdmobBannerAd] but uses [AdManagerBannerAd] and
/// [AdManagerAdRequest] instead of [BannerAd] and [AdRequest].
/// GAM handles consent server-side, so no `nonPersonalizedAds` flag is needed.
class ApslGamBannerAd extends ApslAdBase {
  final AdSize adSize;
  final BannerAdConfig _config;

  AdManagerBannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  int _retryCount = 0;
  bool _maxRetriesReached = false;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;
  int _loadGeneration = 0;

  ApslGamBannerAd(
    super.adUnitId, {
    this.adSize = AdSize.banner,
    BannerAdConfig? config,
  }) : _config = config ?? const BannerAdConfig();

  @override
  AdUnitType get adUnitType => AdUnitType.banner;

  @override
  AdNetwork get adNetwork => AdNetwork.adManager;

  @override
  bool get isAdLoaded => _isAdLoaded;

  int get retryCount => _retryCount;
  bool get isLoading => _isLoading;
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

  void _cancelTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  void _handleLoadFailure(
    AdErrorType errorType, {
    required String errorMessage,
    Ad? ad,
  }) {
    _isAdLoaded = false;
    _isLoading = false;
    _cancelTimers();

    fireAdFailedToLoad(ad, errorMessage);
    ad?.dispose();

    final canRetry = _config.enableAutoRetry &&
        isErrorRetryable(errorType) &&
        _retryCount < _config.maxRetries;

    if (canRetry) {
      final delay = _config.useExponentialBackoff
          ? nextBackoff(_retryCount,
              base: _config.retryDelay, maxDelay: _config.maxRetryDelay)
          : _config.retryDelay;
      _retryCount++;
      _retryTimer = Timer(delay, () {
        if (!_isAdLoaded && !_isLoading) load();
      });
    } else {
      _maxRetriesReached = true;
      _retryCount = 0;
      fireBannerAdReadyForSetState(ad);
    }
  }

  @override
  Future<void> load() async {
    if (_isLoading) return;
    if (_isAdLoaded && _bannerAd != null) return;

    _isLoading = true;
    _cancelTimers();

    final generation = ++_loadGeneration;

    await _bannerAd?.dispose();
    _bannerAd = null;
    _isAdLoaded = false;

    final timeout = _config.loadTimeout;
    if (timeout != null) {
      _loadTimeoutTimer = Timer(timeout, () {
        if (generation != _loadGeneration || !_isLoading) return;
        _handleLoadFailure(
          AdErrorType.timeout,
          errorMessage:
              'GAM banner ad load timeout after ${timeout.inSeconds} seconds',
        );
      });
    }

    try {
      _bannerAd = AdManagerBannerAd(
        sizes: [adSize],
        adUnitId: adUnitId,
        listener: AdManagerBannerAdListener(
          onAdLoaded: (Ad ad) {
            if (generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _cancelTimers();
            _bannerAd = ad as AdManagerBannerAd;
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
        request: const AdManagerAdRequest(),
      )..load();
    } catch (e) {
      if (generation != _loadGeneration) return;
      _handleLoadFailure(AdErrorType.unknown, errorMessage: e.toString());
    }
  }

  @override
  Widget show() {
    if (_maxRetriesReached) return const SizedBox.shrink();

    if (_bannerAd == null || !_isAdLoaded) {
      if (!_isLoading) load();
      return _config.loadingWidget ??
          SizedBox(
            height: adSize.height.toDouble(),
            width: adSize.width.toDouble(),
            child: const Center(child: CircularProgressIndicator()),
          );
    }

    return Container(
      alignment: Alignment.center,
      height: adSize.height.toDouble(),
      width: adSize.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  Future<void> retry() async {
    _retryCount = 0;
    _maxRetriesReached = false;
    await load();
  }

  BannerAdConfig get config => _config;
}
