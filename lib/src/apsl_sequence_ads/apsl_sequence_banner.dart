import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/material.dart';

class ApslSequenceBannerAd extends StatefulWidget {
  final List<AdNetwork> orderOfAdNetworks;
  final AdSize adSize;

  final ApslAdCallback? onAdFailedToLoad;
  final ApslAdCallback? onAdShowed;

  /// Duration before retrying after all networks are exhausted.
  /// Defaults to 45 seconds.
  final Duration recoveryDelay;

  const ApslSequenceBannerAd({
    super.key,
    this.orderOfAdNetworks = const [
      AdNetwork.adManager,
      AdNetwork.admob,
    ],
    this.adSize = AdSize.banner,
    this.onAdFailedToLoad,
    this.onAdShowed,
    this.recoveryDelay = const Duration(seconds: 45),
  });

  @override
  State<ApslSequenceBannerAd> createState() => _ApslSequenceBannerAdState();
}

class _ApslSequenceBannerAdState extends State<ApslSequenceBannerAd> {
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
      if (_isBannerIdAvailable(
          widget.orderOfAdNetworks[_currentADNetworkIndex])) {
        return _showBannerAd(widget.orderOfAdNetworks[_currentADNetworkIndex]);
      }

      _currentADNetworkIndex++;
    }

    // All networks exhausted — schedule a recovery attempt instead of
    // dying permanently. This is the key fix for the "ads stop loading
    // on most iOS devices" bug: if all networks no-fill during ATT prompt
    // or on poor connectivity, they get another chance after the delay.
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
          event.adUnitType == AdUnitType.banner &&
          (event.type == AdEventType.adFailedToLoad ||
              event.type == AdEventType.adFailedToShow)) {
        _cancelStream();
        _currentADNetworkIndex++;
        if (mounted) setState(() {});
      } else if (event.adNetwork == priorityAdNetwork &&
          event.adUnitType == AdUnitType.banner &&
          (event.type == AdEventType.adShowed ||
              event.type == AdEventType.adLoaded)) {
        _cancelStream();
      }
    });
  }

  bool _isBannerIdAvailable(AdNetwork adNetwork) {
    final adIdManager = ApslAds.instance.adIdManager;
    return adIdManager.appAdIds.any(
      (adIds) =>
          adIds.adNetwork == adNetwork &&
          adIds.bannerId != null &&
          adIds.bannerId!.isNotEmpty,
    );
  }

  Widget _showBannerAd(AdNetwork priorityAdNetwork) {
    _subscribeToAdEvent(priorityAdNetwork);
    return ApslBannerAd(
      adNetwork: priorityAdNetwork,
      adSize: widget.adSize,
      onAdFailedToLoad: widget.onAdFailedToLoad,
      onAdShowed: widget.onAdShowed,
    );
  }

  void _cancelStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }
}
