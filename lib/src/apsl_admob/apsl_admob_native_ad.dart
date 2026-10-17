import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/utils/ad_error_mapper.dart';
import 'package:apsl_ads/src/utils/native_template_size.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:apsl_ads/src/utils/retry_policy.dart';
import 'package:flutter/material.dart';

/// A class encapsulating the logic for AdMob's Native Ads.
///
/// Supports two rendering paths:
/// * **Template path (default)**: Uses [nativeTemplateStyle] and [templateType]
///   for Google's built-in templates (small, medium). See [getTemplate()].
/// * **Custom factory path**: When [factoryId] is provided, creates a
///   [NativeAd] with custom [factoryId] and [customOptions] instead of
///   [nativeTemplateStyle]. The two paths are mutually exclusive in the
///   underlying SDK; the template path is used when [factoryId] is null.
class ApslAdmobNativeAd extends ApslAdBase {
  final AdRequest _adRequest;
  final NativeTemplateStyle? nativeTemplateStyle;
  final TemplateType _templateType;
  final NativeAdConfig _config;
  final double? customHeight;
  final String? factoryId;
  final Map<String, Object>? customOptions;

  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  int _retryCount = 0;
  bool _maxRetriesReached = false;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;
  int _loadGeneration = 0;

  /// Set once per loaded ad instance to make sure `onAdShowed` fires
  /// exactly one time, regardless of how many widget rebuilds happen.
  bool _impressionFired = false;

  /// Creates a new [ApslAdmobNativeAd] instance.
  ///
  /// Either supply [nativeTemplateStyle] / [templateType] for Google's built-in
  /// templates, OR supply [factoryId] / [customOptions] for a custom factory
  /// layout. The two paths are mutually exclusive.
  ApslAdmobNativeAd(
    super.adUnitId, {
    AdRequest? adRequest,
    this.nativeTemplateStyle,
    TemplateType? templateType,
    NativeAdConfig? config,
    this.customHeight,
    this.factoryId,
    this.customOptions,
  })  : _adRequest = adRequest ?? const AdRequest(),
        _templateType = templateType ?? TemplateType.medium,
        _config = config ?? const NativeAdConfig();

  @override
  AdUnitType get adUnitType => AdUnitType.native;

  @override
  AdNetwork get adNetwork => AdNetwork.admob;

  @override
  bool get isAdLoaded => _isAdLoaded;

  /// Gets the current retry count
  int get retryCount => _retryCount;

  /// Gets whether max retries have been reached
  bool get maxRetriesReached => _maxRetriesReached;

  @override
  void dispose() {
    _isAdLoaded = false;
    _isLoading = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    _retryCount = 0;
    _maxRetriesReached = false;
    _impressionFired = false;
    _loadGeneration++;
    if (_nativeAd != null) {
      _nativeAd!.dispose();
      _nativeAd = null;
    }
    clearListeners();
  }

  /// Loads the native ad with retry and timeout logic.
  @override
  Future<void> load() async {
    if (_isLoading || _isAdLoaded) return;
    if (DisabledAdUnits.isDisabled(adUnitId)) {
      _maxRetriesReached = true;
      // Hosts reserving space wait for an answer; stay silent and they never
      // collapse.
      fireAdFailedToLoad(null, 'unit disabled');
      fireNativeAdReadyForSetState(null);
      return;
    }
    final String? malformed = checkUnitShape(adUnitId, adNetwork, adUnitType);
    if (malformed != null) {
      _maxRetriesReached = true;
      fireAdFailedToLoad(null, malformed);
      return;
    }
    _isLoading = true;
    _impressionFired = false;
    _loadTimeoutTimer?.cancel();
    _retryTimer?.cancel();

    final generation = ++_loadGeneration;

    if (_nativeAd != null) {
      await _nativeAd!.dispose();
      _nativeAd = null;
    }
    _isAdLoaded = false;

    final timeout = _config.loadTimeout;
    if (timeout != null) {
      _loadTimeoutTimer = Timer(timeout, () {
        if (generation != _loadGeneration || _isAdLoaded) return;
        _isLoading = false;
        _handleError(
          AdErrorType.timeout,
          errorMessage: 'Native ad load timed out',
        );
      });
    }

    try {
      // Build the NativeAd with either template or factory layout.
      // When factoryId is provided, use factoryId + customOptions instead
      // of nativeTemplateStyle (they are mutually exclusive in google_mobile_ads).
      if (factoryId != null) {
        _nativeAd = NativeAd(
          adUnitId: adUnitId,
          listener: _buildListener(generation),
          factoryId: factoryId,
          customOptions: customOptions,
          request: _adRequest,
        )..load();
      } else {
        _nativeAd = NativeAd(
          adUnitId: adUnitId,
          listener: _buildListener(generation),
          nativeTemplateStyle: nativeTemplateStyle ?? getTemplate(),
          request: _adRequest,
        )..load();
      }
    } catch (e) {
      if (generation != _loadGeneration) return;
      _isLoading = false;
      _loadTimeoutTimer?.cancel();
      _handleError(AdErrorType.unknown, errorMessage: e.toString());
    }
  }

  /// Builds the [NativeAdListener] for both template and factory paths.
  NativeAdListener _buildListener(int generation) {
    return NativeAdListener(
      onAdLoaded: (ad) {
        if (generation != _loadGeneration) {
          ad.dispose();
          return;
        }
        _isAdLoaded = true;
        _isLoading = false;
        _retryCount = 0;
        _maxRetriesReached = false;
        _loadTimeoutTimer?.cancel();
        _nativeAd = ad as NativeAd?;
        fireAdLoaded(ad);
        fireNativeAdReadyForSetState(ad);
      },
      onAdFailedToLoad: (ad, error) {
        if (generation != _loadGeneration) {
          ad.dispose();
          return;
        }
        _isAdLoaded = false;
        _isLoading = false;
        _nativeAd = null;
        ad.dispose();
        _loadTimeoutTimer?.cancel();
        _handleError(
          mapLoadAdError(error),
          errorMessage: error.toString(),
        );
      },
      onAdImpression: (ad) {
        // Fire impression callback exactly once per loaded ad. The
        // SDK guarantees this is called when the ad is actually
        // visible to the user, which is the right signal for analytics.
        if (_impressionFired) return;
        _impressionFired = true;
        fireAdShowed(ad);
      },
      onAdClicked: (ad) => fireAdClicked(ad),
    );
  }

  /// Handles ad load errors, retrying with exponential backoff if enabled
  /// and under [NativeAdConfig.maxRetries].
  void _handleError(AdErrorType errorType, {String? errorMessage, Object? ad}) {
    if (!silenceDeadUnit(
        adUnitId, adUnitType, errorType, errorMessage ?? errorType.message)) {
      fireAdFailedToLoad(ad, errorMessage ?? errorType.message);
    }

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
      _maxRetriesReached = true;
      _retryCount = 0;
      fireNativeAdReadyForSetState(ad);
    }
  }

  /// Returns the template style for the native ad
  NativeTemplateStyle getTemplate() {
    return NativeTemplateStyle(
      templateType: _templateType,
      mainBackgroundColor: Colors.transparent,
      cornerRadius: 10.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: Colors.white,
        backgroundColor: Colors.blue,
        style: NativeTemplateFontStyle.normal,
        size: 16.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.blue,
        style: NativeTemplateFontStyle.normal,
        size: 16.0,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.black,
        style: NativeTemplateFontStyle.bold,
        size: 16.0,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.brown,
        backgroundColor: Colors.transparent,
        style: NativeTemplateFontStyle.normal,
        size: 16.0,
      ),
    );
  }

  /// Displays the loaded native ad, or a loading/placeholder widget if not
  /// ready. Note: this method is intentionally side-effect-free with respect
  /// to analytics — `onAdShowed` is fired by the SDK's `onAdImpression`
  /// listener exactly once, not on every rebuild.
  @override
  Widget show() {
    if (_maxRetriesReached) {
      return const SizedBox.shrink();
    }

    if (_nativeAd == null || !_isAdLoaded) {
      if (!_isLoading) load();
      return _config.loadingWidget ?? const SizedBox.shrink();
    }
    return Center(
      child: SizedBox(
        width: double.infinity,
        height: customHeight ??
            (_templateType == TemplateType.small
                ? smallNativeTemplateHeight
                : mediumNativeTemplateHeight),
        child: AdWidget(ad: _nativeAd!),
      ),
    );
  }

  /// Manually triggers a retry of the ad load.
  Future<void> retry() async {
    _retryCount = 0;
    _maxRetriesReached = false;
    await load();
  }

  /// Gets the current configuration
  NativeAdConfig get config => _config;
}
