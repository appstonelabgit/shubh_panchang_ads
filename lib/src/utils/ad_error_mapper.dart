import 'package:apsl_ads/src/enums/ad_error_type.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Maps a [LoadAdError] from `google_mobile_ads` to an [AdErrorType].
///
/// Uses the SDK's numeric error codes (which are stable across versions and
/// locales) instead of substring-matching `error.toString()`. The codes
/// follow Google's published constants:
///
/// * 0 — internal error
/// * 1 — invalid request
/// * 2 — network error
/// * 3 — no fill
/// * 8 — app id missing
AdErrorType mapLoadAdError(LoadAdError error) {
  switch (error.code) {
    case 0:
      return AdErrorType.internalError;
    case 1:
    case 8:
      return AdErrorType.invalidAdUnit;
    case 2:
      return AdErrorType.networkError;
    case 3:
      return AdErrorType.noFill;
    default:
      return AdErrorType.unknown;
  }
}

/// Returns whether a given error type should be retried at all.
///
/// Misconfiguration errors (invalid ad unit / missing app id) will never
/// recover on their own and we should stop hammering the network — surface
/// the failure to the developer instead.
bool isErrorRetryable(AdErrorType type) {
  switch (type) {
    case AdErrorType.invalidAdUnit:
      return false;
    case AdErrorType.networkError:
    case AdErrorType.noFill:
    case AdErrorType.internalError:
    case AdErrorType.timeout:
    case AdErrorType.unknown:
      return true;
  }
}
