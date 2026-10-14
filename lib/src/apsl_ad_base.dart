import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';
import 'package:flutter/foundation.dart';

/// Base class for every ad implementation in the package.
///
/// Provides a multicast listener model: multiple consumers can subscribe to
/// the same event (e.g. the [ApslEventController] AND a widget), and all of
/// them will be invoked. The previous design used single-field callbacks
/// (`ApslAdCallback? onAdLoaded;`) which silently broke whenever two
/// subsystems tried to attach to the same ad.
abstract class ApslAdBase {
  final String adUnitId;

  ApslAdBase(this.adUnitId);

  AdNetwork get adNetwork;
  AdUnitType get adUnitType;
  bool get isAdLoaded;

  /// Releases native resources held by this ad. Subclasses must call
  /// [clearListeners] from their override (or chain to `super.dispose()`).
  void dispose();

  /// Loads the ad. No-op if already loading or loaded.
  Future<void> load();

  dynamic show();

  /// Until when a frequency-cap error stops this unit loading; null when it
  /// may load. Only full-screen formats that obey a cap report one.
  DateTime? get loadBlockedUntil => null;

  /// Starts a cap block persisted by an earlier run, so a relaunch does not
  /// ask a capped unit again. No-op for formats without a cap.
  void blockLoadsUntil(DateTime until) {}

  // ─── Listener storage ──────────────────────────────────────────────────
  // Each event is backed by an unordered list of callbacks. We use a
  // List instead of a Set so a consumer can register the same callback
  // twice if they really want to (rare, but cheap to support).

  final List<ApslAdCallback> _onAdLoadedListeners = [];
  final List<ApslAdCallback> _onAdShowedListeners = [];
  final List<ApslAdCallback> _onAdClickedListeners = [];
  final List<ApslAdCallback> _onAdFailedToLoadListeners = [];
  final List<ApslAdCallback> _onAdFailedToShowListeners = [];
  final List<ApslAdCallback> _onAdDismissedListeners = [];
  final List<ApslAdCallback> _onBannerAdReadyListeners = [];
  final List<ApslAdCallback> _onNativeAdReadyListeners = [];
  final List<ApslAdCallback> _onEarnedRewardListeners = [];
  final List<ApslAdCallback> _onAdShowSkippedListeners = [];

  // ─── Listener registration ────────────────────────────────────────────
  // Each `addOn*` method appends to the corresponding list. This is the
  // ONLY supported way to subscribe — there are no public single-field
  // setters anymore, so there's no way to accidentally clobber another
  // subscriber.

  /// Adds a listener for ad-loaded events.
  void addOnAdLoaded(ApslAdCallback cb) => _onAdLoadedListeners.add(cb);

  /// Adds a listener for ad-shown events.
  void addOnAdShowed(ApslAdCallback cb) => _onAdShowedListeners.add(cb);

  /// Adds a listener for ad-clicked events.
  void addOnAdClicked(ApslAdCallback cb) => _onAdClickedListeners.add(cb);

  /// Adds a listener for ad-load-failure events.
  void addOnAdFailedToLoad(ApslAdCallback cb) =>
      _onAdFailedToLoadListeners.add(cb);

  /// Adds a listener for ad-show-failure events.
  void addOnAdFailedToShow(ApslAdCallback cb) =>
      _onAdFailedToShowListeners.add(cb);

  /// Adds a listener for ad-dismissed events.
  void addOnAdDismissed(ApslAdCallback cb) => _onAdDismissedListeners.add(cb);

  /// Adds a listener for "banner ad ready, please call setState" events.
  /// Used by [ApslBannerAd] to know when to rebuild.
  void addOnBannerAdReadyForSetState(ApslAdCallback cb) =>
      _onBannerAdReadyListeners.add(cb);

  /// Adds a listener for "native ad ready, please call setState" events.
  /// Used by [ApslNativeAd] to know when to rebuild.
  void addOnNativeAdReadyForSetState(ApslAdCallback cb) =>
      _onNativeAdReadyListeners.add(cb);

  /// Adds a listener for rewarded-ad earned-reward events.
  void addOnEarnedReward(ApslAdCallback cb) => _onEarnedRewardListeners.add(cb);

  void addOnAdShowSkipped(ApslAdCallback cb) =>
      _onAdShowSkippedListeners.add(cb);

  /// Removes all registered listeners. Subclasses should call this from
  /// [dispose] to release closure references and avoid leaks.
  void clearListeners() {
    _onAdLoadedListeners.clear();
    _onAdShowedListeners.clear();
    _onAdClickedListeners.clear();
    _onAdFailedToLoadListeners.clear();
    _onAdFailedToShowListeners.clear();
    _onAdDismissedListeners.clear();
    _onBannerAdReadyListeners.clear();
    _onNativeAdReadyListeners.clear();
    _onEarnedRewardListeners.clear();
    _onAdShowSkippedListeners.clear();
  }

  // ─── Dispatchers (used by subclasses) ─────────────────────────────────
  // These iterate over a defensive copy of the listener list so a
  // listener that mutates the list (e.g. by calling clearListeners() in
  // its handler) doesn't cause a ConcurrentModificationError.

  @protected
  void fireAdLoaded(Object? data) => _fanOut(_onAdLoadedListeners, data);

  @protected
  void fireAdShowed(Object? data) => _fanOut(_onAdShowedListeners, data);

  @protected
  void fireAdClicked(Object? data) => _fanOut(_onAdClickedListeners, data);

  @protected
  void fireAdFailedToLoad(Object? data, String errorMessage) =>
      _fanOut(_onAdFailedToLoadListeners, data, errorMessage: errorMessage);

  @protected
  void fireAdFailedToShow(Object? data, String errorMessage) =>
      _fanOut(_onAdFailedToShowListeners, data, errorMessage: errorMessage);

  /// A show request declined before reaching the SDK; [reason] is a short
  /// code such as `cooldown`, `showing`, `background`, `not_loaded`.
  @protected
  void fireAdShowSkipped(String reason) =>
      _fanOut(_onAdShowSkippedListeners, null, errorMessage: reason);

  @protected
  void fireAdDismissed(Object? data) => _fanOut(_onAdDismissedListeners, data);

  @protected
  void fireBannerAdReadyForSetState(Object? data) =>
      _fanOut(_onBannerAdReadyListeners, data);

  @protected
  void fireNativeAdReadyForSetState(Object? data) =>
      _fanOut(_onNativeAdReadyListeners, data);

  @protected
  void fireEarnedReward(Object? data,
          {String? rewardType, num? rewardAmount}) =>
      _fanOut(
        _onEarnedRewardListeners,
        data,
        rewardType: rewardType,
        rewardAmount: rewardAmount,
      );

  void _fanOut(
    List<ApslAdCallback> listeners,
    Object? data, {
    String? errorMessage,
    String? rewardType,
    num? rewardAmount,
  }) {
    if (listeners.isEmpty) return;
    for (final cb in List.of(listeners)) {
      cb(
        adNetwork,
        adUnitType,
        data,
        errorMessage: errorMessage,
        rewardType: rewardType,
        rewardAmount: rewardAmount,
      );
    }
  }
}

typedef ApslAdNetworkInitialized = void Function(
    AdNetwork adNetwork, bool isInitialized, Object? data);

typedef ApslAdCallback = void Function(
  AdNetwork adNetwork,
  AdUnitType adUnitType,
  Object? data, {
  String? errorMessage,
  String? rewardType,
  num? rewardAmount,
});
