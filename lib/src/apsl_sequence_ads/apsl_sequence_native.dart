import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Builds the per-network native child. Overridable in tests only.
@visibleForTesting
typedef ApslSequenceNativeChildBuilder = Widget Function(
  AdNetwork adNetwork,
  ApslAdCallback onAdLoaded,
  ApslAdCallback onAdFailedToLoad,
);

/// Widget for displaying native ads in sequence with configurable retry and loading behavior.
class ApslSequenceNativeAd extends StatefulWidget {
  final List<AdNetwork> orderOfAdNetworks;
  final NativeTemplateStyle? nativeTemplateStyle;
  final TemplateType templateType;
  final ApslAdCallback? onAdShowed;
  final ApslAdCallback? onAdFailedToLoad;

  /// Fired when this instance's native ad loads (never for another instance).
  final ApslAdCallback? onAdLoaded;
  final NativeAdConfig? config;

  /// Optional fixed height for the rendered native ad. Forwarded to the
  /// underlying network ad so callers can tighten the band around the
  /// template content instead of the package default.
  final double? customHeight;

  /// Optional factoryId for custom native ad layout (see [ApslAdmobNativeAd]).
  /// When provided, the factory layout is used instead of [nativeTemplateStyle].
  final String? factoryId;

  /// Optional custom options for the factory layout.
  final Map<String, Object>? customOptions;

  /// Duration before retrying after all networks are exhausted.
  final Duration recoveryDelay;

  /// Replaces the [ApslNativeAd] child so tests can drive load/fail
  /// callbacks without the platform SDK.
  @visibleForTesting
  static ApslSequenceNativeChildBuilder? debugChildBuilder;

  const ApslSequenceNativeAd({
    super.key,
    this.orderOfAdNetworks = const [
      AdNetwork.adManager,
      AdNetwork.admob,
    ],
    this.nativeTemplateStyle,
    this.templateType = TemplateType.medium,
    this.config,
    this.customHeight,
    this.factoryId,
    this.customOptions,
    this.onAdShowed,
    this.onAdFailedToLoad,
    this.onAdLoaded,
    this.recoveryDelay = const Duration(seconds: 45),
  });

  @override
  State<ApslSequenceNativeAd> createState() => _ApslSequenceNativeAdState();
}

class _ApslSequenceNativeAdState extends State<ApslSequenceNativeAd> {
  int _currentADNetworkIndex = 0;
  bool _exhausted = false;
  Timer? _recoveryTimer;

  @override
  void dispose() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_exhausted) return const SizedBox();

    final length = widget.orderOfAdNetworks.length;

    while (_currentADNetworkIndex < length) {
      if (_isNativeIdAvailable(
          widget.orderOfAdNetworks[_currentADNetworkIndex])) {
        return _showNativeAd(widget.orderOfAdNetworks[_currentADNetworkIndex]);
      }

      _currentADNetworkIndex++;
    }

    _exhausted = true;
    _startRecoveryTimer();
    return const SizedBox();
  }

  void _startRecoveryTimer() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(widget.recoveryDelay, () {
      if (!mounted) return;
      setState(() {
        _exhausted = false;
        _currentADNetworkIndex = 0;
      });
    });
  }

  AdNetwork? get _currentNetwork =>
      _currentADNetworkIndex < widget.orderOfAdNetworks.length
          ? widget.orderOfAdNetworks[_currentADNetworkIndex]
          : null;

  void _onAdLoaded(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    if (!mounted) return;
    widget.onAdLoaded?.call(
      adNetwork,
      adUnitType,
      data,
      errorMessage: errorMessage,
      rewardType: rewardType,
      rewardAmount: rewardAmount,
    );
  }

  void _onAdFailedToLoad(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    if (!mounted) return;
    widget.onAdFailedToLoad?.call(
      adNetwork,
      adUnitType,
      data,
      errorMessage: errorMessage,
      rewardType: rewardType,
      rewardAmount: rewardAmount,
    );
    // A late failure from a network this instance already moved past must
    // not skip the one now loading.
    if (adNetwork != _currentNetwork) return;
    _advance(adNetwork);
  }

  void _advance(AdNetwork failedNetwork) {
    // The child may fail synchronously from its initState, i.e. while this
    // widget is building; setState is illegal then.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && failedNetwork == _currentNetwork) {
          setState(() => _currentADNetworkIndex++);
        }
      });
      return;
    }
    setState(() => _currentADNetworkIndex++);
  }

  bool _isNativeIdAvailable(AdNetwork adNetwork) {
    final adIdManager = ApslAds.instance.adIdManager;
    return adIdManager.appAdIds.any(
      (adIds) =>
          adIds.adNetwork == adNetwork &&
          adIds.nativeId != null &&
          adIds.nativeId!.isNotEmpty,
    );
  }

  Widget _showNativeAd(AdNetwork priorityAdNetwork) {
    final debugBuilder = ApslSequenceNativeAd.debugChildBuilder;
    if (debugBuilder != null) {
      return debugBuilder(priorityAdNetwork, _onAdLoaded, _onAdFailedToLoad);
    }
    return ApslNativeAd(
      adNetwork: priorityAdNetwork,
      nativeTemplateStyle: widget.nativeTemplateStyle,
      templateType: widget.templateType,
      config: widget.config,
      customHeight: widget.customHeight,
      factoryId: widget.factoryId,
      customOptions: widget.customOptions,
      onAdShowed: widget.onAdShowed,
      onAdFailedToLoad: _onAdFailedToLoad,
      onAdLoaded: _onAdLoaded,
    );
  }
}
