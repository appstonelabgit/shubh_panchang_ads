# Changelog

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
