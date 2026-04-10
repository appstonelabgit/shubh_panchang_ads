import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/utils/badged_banner.dart';
import 'package:flutter/material.dart';

/// A widget that displays a banner ad with automatic loading and error handling.
///
/// This widget automatically manages the lifecycle of banner ads, including
/// loading, displaying, and error handling. It supports configurable retry
/// behavior and loading placeholders.
///
/// Example:
/// ```dart
/// ApslBannerAd(
///   adNetwork: AdNetwork.admob,
///   adSize: AdSize.banner,
///   config: BannerAdConfig(
///     retryDelay: Duration(seconds: 10),
///     maxRetries: 3,
///     loadingWidget: CircularProgressIndicator(),
///   ),
/// )
/// ```
class ApslBannerAd extends StatefulWidget {
  /// The ad network to use for the banner ad
  final AdNetwork adNetwork;

  /// The size of the banner ad
  final AdSize adSize;

  /// Optional configuration for retry behavior and loading settings
  final BannerAdConfig? config;

  /// Optional onAdFailedToLoad callback
  final ApslAdCallback? onAdFailedToLoad;

  /// Optional onAdShowed callback
  final ApslAdCallback? onAdShowed;

  /// Creates a new [ApslBannerAd] widget
  const ApslBannerAd({
    this.adNetwork = AdNetwork.admob,
    this.adSize = AdSize.banner,
    this.config,
    this.onAdFailedToLoad,
    this.onAdShowed,
    super.key,
  });

  @override
  State<ApslBannerAd> createState() => _ApslBannerAdState();
}

class _ApslBannerAdState extends State<ApslBannerAd> {
  ApslAdBase? _bannerAd;
  late AdNetwork _currentNetwork;
  late AdSize _currentSize;
  BannerAdConfig? _currentConfig;

  @override
  void initState() {
    super.initState();
    _currentNetwork = widget.adNetwork;
    _currentSize = widget.adSize;
    _currentConfig = widget.config;
    _initBanner();
  }

  @override
  void didUpdateWidget(covariant ApslBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.adNetwork != _currentNetwork ||
        widget.adSize != _currentSize ||
        widget.config != _currentConfig) {
      _currentNetwork = widget.adNetwork;
      _currentSize = widget.adSize;
      _currentConfig = widget.config;
      _initBanner();
    }
  }

  /// Initializes the banner ad with the current configuration.
  ///
  /// User callbacks (`widget.onAdFailedToLoad` / `widget.onAdShowed`) are
  /// attached inside [ApslAds.createBanner] via the multicast listener API,
  /// so we only register our internal "ready to setState" hook here.
  void _initBanner() {
    _bannerAd?.dispose();
    _bannerAd = ApslAds.instance.createBanner(
      adNetwork: _currentNetwork,
      adSize: _currentSize,
      config: _currentConfig,
      onAdFailedToLoad: widget.onAdFailedToLoad,
      onAdShowed: widget.onAdShowed,
    );

    _bannerAd?.addOnAdLoaded(_onBannerAdReady);
    _bannerAd?.addOnBannerAdReadyForSetState(_onBannerAdReady);

    _bannerAd?.load();
  }

  /// Callback when the banner ad is ready for display
  void _onBannerAdReady(
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
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adWidget = _bannerAd?.show();

    if (ApslAds.instance.showAdBadge) {
      return BadgedBanner(child: adWidget, adSize: widget.adSize);
    }

    return adWidget ?? SizedBox(height: 0); // Prevent layout shift
  }
}
