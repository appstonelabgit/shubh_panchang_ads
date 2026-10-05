import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/foundation.dart';

/// Bridges per-ad multicast listeners into a single application-wide
/// broadcast [Stream] of [AdEvent].
///
/// Every ad created via [ApslAds.createBanner], [ApslAds.createNative], or
/// the cold-start preload path is registered here so that any subscriber
/// to [ApslAds.instance.onEvent] sees a unified, ordered timeline of ad
/// activity.
class ApslEventController {
  final bool debugLogging;

  ApslEventController({this.debugLogging = false});

  final _onEventController = StreamController<AdEvent>.broadcast();
  Stream<AdEvent> get onEvent => _onEventController.stream;

  /// Closes the underlying broadcast stream. Called from
  /// [ApslAds.destroyAds] so re-initializing doesn't leak listeners.
  void dispose() {
    if (!_onEventController.isClosed) {
      _onEventController.close();
    }
  }

  void fireNetworkInitializedEvent(AdNetwork adNetwork, bool status) {
    _addEvent(AdEvent(
      type: AdEventType.adNetworkInitialized,
      adNetwork: adNetwork,
      data: status,
    ));
  }

  /// Subscribes to the lifecycle events of [ad] and forwards them onto
  /// the broadcast stream. Uses the multicast `addOn*` listener API so
  /// that registering here does NOT clobber any other subscribers (e.g.
  /// the widget-level callbacks set by [ApslBannerAd]).
  void setupEvents(ApslAdBase ad) {
    ad.addOnAdLoaded(_onAdLoadedMethod);
    ad.addOnAdFailedToLoad(_onAdFailedToLoadMethod);
    ad.addOnAdShowed(_onAdShowedMethod);
    ad.addOnAdFailedToShow(_onAdFailedToShowMethod);
    ad.addOnAdDismissed(_onAdDismissedMethod);
    ad.addOnEarnedReward(_onEarnedRewardMethod);
    ad.addOnAdShowSkipped(_onAdShowSkippedMethod);
  }

  void _onAdShowSkippedMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.adShowSkipped,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      error: errorMessage,
    ));
  }

  void _addEvent(AdEvent event) {
    if (!_onEventController.isClosed) {
      _onEventController.sink.add(event);
      if (debugLogging) {
        debugPrint(
            '[ApslEventController] => ${event.type} (${event.adNetwork})');
      }
    }
  }

  void _onAdLoadedMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.adLoaded,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      data: data,
    ));
  }

  void _onAdShowedMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.adShowed,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      data: data,
    ));
  }

  void _onAdFailedToLoadMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.adFailedToLoad,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      data: data,
      error: errorMessage,
    ));
  }

  void _onAdFailedToShowMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.adFailedToShow,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      data: data,
      error: errorMessage,
    ));
  }

  void _onAdDismissedMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.adDismissed,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      data: data,
    ));
  }

  void _onEarnedRewardMethod(
    AdNetwork adNetwork,
    AdUnitType adUnitType,
    Object? data, {
    String? rewardType,
    String? errorMessage,
    num? rewardAmount,
  }) {
    _addEvent(AdEvent(
      type: AdEventType.earnedReward,
      adNetwork: adNetwork,
      adUnitType: adUnitType,
      data: {
        'rewardType': rewardType,
        'rewardAmount': rewardAmount,
      },
    ));
  }
}
