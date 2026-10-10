import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/material.dart';

/// Widget for displaying native ads in sequence with configurable retry and loading behavior.
class ApslSequenceNativeAd extends StatefulWidget {
  final List<AdNetwork> orderOfAdNetworks;
  final NativeTemplateStyle? nativeTemplateStyle;
  final TemplateType templateType;
  final ApslAdCallback? onAdShowed;
  final ApslAdCallback? onAdFailedToLoad;
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
    this.recoveryDelay = const Duration(seconds: 45),
  });

  @override
  State<ApslSequenceNativeAd> createState() => _ApslSequenceNativeAdState();
}

class _ApslSequenceNativeAdState extends State<ApslSequenceNativeAd> {
  int _currentADNetworkIndex = 0;
  bool _exhausted = false;
  StreamSubscription? _streamSubscription;
  Timer? _recoveryTimer;

  @override
  void dispose() {
    _cancelStream();
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

  void _subscribeToAdEvent(AdNetwork priorityAdNetwork) {
    _cancelStream();
    _streamSubscription = ApslAds.instance.onEvent.listen((event) {
      if (event.adNetwork == priorityAdNetwork &&
          event.adUnitType == AdUnitType.native &&
          (event.type == AdEventType.adFailedToLoad ||
              event.type == AdEventType.adFailedToShow)) {
        _cancelStream();
        _currentADNetworkIndex++;
        if (mounted) setState(() {});
      } else if (event.adNetwork == priorityAdNetwork &&
          event.adUnitType == AdUnitType.native &&
          (event.type == AdEventType.adShowed ||
              event.type == AdEventType.adLoaded)) {
        _cancelStream();
      }
    });
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
    _subscribeToAdEvent(priorityAdNetwork);
    return ApslNativeAd(
      adNetwork: priorityAdNetwork,
      nativeTemplateStyle: widget.nativeTemplateStyle,
      templateType: widget.templateType,
      config: widget.config,
      customHeight: widget.customHeight,
      factoryId: widget.factoryId,
      customOptions: widget.customOptions,
      onAdShowed: widget.onAdShowed,
      onAdFailedToLoad: widget.onAdFailedToLoad,
    );
  }

  void _cancelStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }
}
