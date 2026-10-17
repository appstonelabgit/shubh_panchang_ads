import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Builds the per-network banner child. Overridable in tests only.
@visibleForTesting
typedef ApslSequenceBannerChildBuilder = Widget Function(
  AdNetwork adNetwork,
  ApslAdCallback onAdLoaded,
  ApslAdCallback onAdFailedToLoad,
);

class ApslSequenceBannerAd extends StatefulWidget {
  final List<AdNetwork> orderOfAdNetworks;
  final AdSize adSize;

  final ApslAdCallback? onAdFailedToLoad;
  final ApslAdCallback? onAdShowed;

  /// Fired when this instance's banner loads (never for another instance).
  final ApslAdCallback? onAdLoaded;

  /// Duration before retrying after all networks are exhausted.
  /// Defaults to 45 seconds.
  final Duration recoveryDelay;

  /// Replaces the [ApslBannerAd] child so tests can drive load/fail
  /// callbacks without the platform SDK.
  @visibleForTesting
  static ApslSequenceBannerChildBuilder? debugChildBuilder;

  const ApslSequenceBannerAd({
    super.key,
    this.orderOfAdNetworks = const [
      AdNetwork.adManager,
      AdNetwork.admob,
    ],
    this.adSize = AdSize.banner,
    this.onAdFailedToLoad,
    this.onAdShowed,
    this.onAdLoaded,
    this.recoveryDelay = const Duration(seconds: 45),
  });

  @override
  State<ApslSequenceBannerAd> createState() => _ApslSequenceBannerAdState();
}

class _ApslSequenceBannerAdState extends State<ApslSequenceBannerAd> {
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
    final debugBuilder = ApslSequenceBannerAd.debugChildBuilder;
    if (debugBuilder != null) {
      return debugBuilder(priorityAdNetwork, _onAdLoaded, _onAdFailedToLoad);
    }
    return ApslBannerAd(
      adNetwork: priorityAdNetwork,
      adSize: widget.adSize,
      onAdFailedToLoad: _onAdFailedToLoad,
      onAdShowed: widget.onAdShowed,
      onAdLoaded: _onAdLoaded,
    );
  }
}
