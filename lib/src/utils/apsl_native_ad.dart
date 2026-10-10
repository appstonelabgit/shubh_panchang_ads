import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/material.dart';

/// Widget for displaying a native ad with configurable retry and loading behavior.
///
/// Supports both template-based (using [nativeTemplateStyle] and [templateType])
/// and custom factory-based ([factoryId] and [customOptions]) rendering.
/// When [factoryId] is provided, the template parameters are ignored.
class ApslNativeAd extends StatefulWidget {
  /// The ad network to use (defaults to AdMob)
  final AdNetwork adNetwork;

  /// Optional template style for the native ad
  final NativeTemplateStyle? nativeTemplateStyle;

  /// The type of template to use (small, medium, or custom)
  final TemplateType? templateType;

  /// Optional configuration for retry, loading, and placeholder behavior
  final NativeAdConfig? config;

  /// Optional height for the native ad
  final double? customHeight;

  /// Optional factoryId for custom native ad layout.
  /// When provided, uses the factory layout instead of [nativeTemplateStyle].
  final String? factoryId;

  /// Optional custom options for the factory layout.
  final Map<String, Object>? customOptions;

  /// Optional onAdShowed callback
  final ApslAdCallback? onAdShowed;

  /// Optional onAdFailedToLoad callback
  final ApslAdCallback? onAdFailedToLoad;

  const ApslNativeAd({
    this.adNetwork = AdNetwork.admob,
    this.nativeTemplateStyle,
    this.templateType,
    this.config,
    this.customHeight,
    this.factoryId,
    this.customOptions,
    this.onAdShowed,
    this.onAdFailedToLoad,
    super.key,
  });

  @override
  State<ApslNativeAd> createState() => _ApslNativeAdState();
}

class _ApslNativeAdState extends State<ApslNativeAd> {
  ApslAdBase? _nativeAd;
  late AdNetwork _currentNetwork;
  late TemplateType _currentTemplateType;
  NativeAdConfig? _currentConfig;

  @override
  void initState() {
    super.initState();
    _currentNetwork = widget.adNetwork;
    _currentTemplateType = widget.templateType ?? TemplateType.small;
    _currentConfig = widget.config;
    _initNative();
  }

  @override
  void didUpdateWidget(covariant ApslNativeAd oldWidget) {
    super.didUpdateWidget(oldWidget);

    final updatedTemplate = widget.templateType ?? TemplateType.small;

    if (widget.adNetwork != _currentNetwork ||
        updatedTemplate != _currentTemplateType ||
        widget.config != _currentConfig) {
      _currentNetwork = widget.adNetwork;
      _currentTemplateType = updatedTemplate;
      _currentConfig = widget.config;
      _initNative();
    }
  }

  /// Initializes the native ad with the current configuration.
  ///
  /// User callbacks (`widget.onAdFailedToLoad` / `widget.onAdShowed`) are
  /// attached inside [ApslAds.createNative] via the multicast listener API,
  /// so we only register our internal "ready to setState" hook here.
  void _initNative() {
    _nativeAd?.dispose();

    _nativeAd = ApslAds.instance.createNative(
      adNetwork: _currentNetwork,
      nativeTemplateStyle: widget.nativeTemplateStyle,
      templateType: _currentTemplateType,
      config: _currentConfig,
      customHeight: widget.customHeight,
      factoryId: widget.factoryId,
      customOptions: widget.customOptions,
      onAdFailedToLoad: widget.onAdFailedToLoad,
      onAdShowed: widget.onAdShowed,
    );

    _nativeAd?.addOnAdLoaded(_onNativeAdReady);
    _nativeAd?.addOnNativeAdReadyForSetState(_onNativeAdReady);

    _nativeAd?.load();
  }

  void _onNativeAdReady(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    _nativeAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get the ad widget from the native ad instance
    // The show() method always returns a widget:
    // - Loading widget (custom or default) when loading
    // - Actual ad widget when loaded
    // - SizedBox.shrink() when max retries reached
    return _nativeAd?.show() ?? const SizedBox.shrink();
  }
}
