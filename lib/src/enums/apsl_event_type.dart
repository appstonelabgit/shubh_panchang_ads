enum AdEventType {
  /// When ad network is initialized and ready to load ad units this will be triggered
  /// In case of [adNetworkInitialized], [AdEvent.data] will have a boolean value indicating status of initialization
  adNetworkInitialized,

  /// When ad unit is loaded, this will be triggered
  adLoaded,

  /// When user clicks cross button and close the ad, this will be triggered
  adDismissed,
  adShowed,
  adFailedToLoad,
  adFailedToShow,
  earnedReward,

  /// A show request was declined without asking the SDK — cooldown, already
  /// showing, app in the background, nothing cached. [AdEvent.error] holds
  /// the reason. Not a failure: nothing was requested.
  adShowSkipped,
}

extension AdEventTypeExtension on AdEventType {
  String get value => name;
}
