# Changelog

## 1.4.0

Frequency caps that outlive a launch, rewarded warm-up, no background shows.

- `initialize(appOpenCapCooldown:)`: after "frequency cap reached" an
  app-open unit is not requested again for this long (default zero, the
  1.2.2 behaviour). Interstitials already used `interstitialCooldown`.
- `initialize(loadBlockedUntil:)` and `loadBlockedUntilFor(type)`: the app
  reads a unit's cap block after a failed load, persists it, and hands it
  back on the next launch, so a relaunch does not ask a capped unit again.
- App open: a show refused while the unit is capped reports `cap` instead
  of `not_loaded`.
- `loadRewardedAd()`: warms a rewarded ad without showing it, for when an
  offer to watch one appears. Still never preloaded at start or after a
  dismiss.
- Rewarded: a loaded ad older than 55 minutes is dropped (AdMob expires
  them after an hour).
- `loadAndShowRewardedAd` returns false instead of showing when the app is
  not resumed, including when the load lands after the user left.

## 1.3.0

Native ad custom factory layout path.

- Add `factoryId` and `customOptions` parameters to `ApslAdmobNativeAd`,
  `ApslGamNativeAd`, `ApslSequenceNativeAd`, and `ApslAds.createNative()` to
  support custom native ad layouts registered via platform-specific factory
  methods. When `factoryId` is provided, it takes precedence over
  `nativeTemplateStyle` (the two rendering paths are mutually exclusive in the
  underlying Google Mobile Ads SDK).
- The existing template path (with `nativeTemplateStyle` and `templateType`)
  remains the default and works unchanged when no `factoryId` is specified.
- Custom factory layouts can pass theme colours and other options via
  `customOptions` as a Map.
- The `customHeight` parameter is available on both paths to set the box
  height for the rendered ad (existing for templates, now also applicable
  to factory layouts).

## 1.2.2

App open: back to one ad per cooldown without late ads.

- The next ad is preloaded in the last `appOpenPreloadLead` (default
  30 min) of the cooldown while the app is in the foreground, so the first
  resume after the cooldown has one cached. This needs AdMob's own cap on
  the unit to be shorter than the cooldown minus the lead (e.g. a 3 h cap
  under a 4 h cooldown).
- `ApslAds.showAppOpenWithin(timeout, stillEligible:)`: shows a cached ad,
  or loads one and shows it only if it arrives within the timeout while
  `stillEligible` holds. Otherwise `adShowSkipped` with `timeout`, `screen`
  or `not_loaded`; a late ad stays cached for the next request.
- A frequency-cap error no longer blocks app-open loads for four hours; the
  next natural trigger tries again.

## 1.2.1

- The small native template's box is 108 pt high (was 100). On iOS its
  media view is square and up to a quarter of the ad's width, about 101 pt
  on a Pro Max, so a 100 pt box cut it off and AdMob's validator reported
  "advertiser assets outside native ad view". The validator's "MediaView is
  too small for video" warning remains: the template's media view can't
  reach 120 pt; a custom layout is planned.

## 1.2.0

Load and show pacing for AdMob's frequency caps.

- Interstitial: a failed load no longer retries up to 5 times. A
  frequency-cap error blocks loading until `interstitialCooldown` (from
  `initialize()`) has passed; no fill / timeout retries once after 60 s, then
  waits for the next natural trigger. The single reload after a dismissed ad
  is kept. A cached ad older than 55 min is dropped and loaded fresh.
- App open: never shown late or automatically after a load. `show()` checks
  `appOpenCooldown` (default 4 h) and `appOpenMinSessions` (default 3,
  against `sessionNumber`); `appOpenLastShownAt` carries the last impression
  across launches. No load during the cooldown, no reload after dismiss.
- Rewarded: never preloaded and not touched by the resume/reconnect reloader.
  `loadAndShowRewardedAd(waitTimeout:)` loads on demand. No retry loop.
- Full-screen `show()` skips while another ad is showing or the app is in
  the background, and emits `AdEventType.adShowSkipped` with the reason
  (`showing`, `background`, `not_loaded`, `cooldown`, `min_sessions`).
- An invalid, malformed or wrong-format unit (any format) reports one clear
  failure and is not requested again for the session (`DisabledAdUnits`).
- New error types `frequencyCapped` and `wrongFormat`, recognised from the
  SDK message on both platforms; neither is retryable.
- `initialize(enableAdManager: false)` skips every Google Ad Manager unit.

## 1.1.0

- Per-platform `LoadAdError` code mapping; Next-Gen GMA SDK.
