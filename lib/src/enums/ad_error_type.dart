/// Enum representing different types of ad loading errors
enum AdErrorType {
  /// Network connectivity issues
  networkError,

  /// Invalid or malformed ad unit ID
  invalidAdUnit,

  /// Ad request timeout
  timeout,

  /// No fill - no ad available to serve
  noFill,

  /// Internal SDK error
  internalError,

  /// Unknown or unspecified error
  unknown,

  /// AdMob refused the request because the unit's frequency cap is reached.
  /// Every retry inside the cap window is another refused request.
  frequencyCapped,

  /// The unit exists but is set up for a different format (a banner id
  /// used for a native, say). It will never load as this format.
  wrongFormat,
}

/// Extension to provide user-friendly error messages
extension AdErrorTypeExtension on AdErrorType {
  /// Returns a user-friendly error message for the error type
  String get message {
    switch (this) {
      case AdErrorType.networkError:
        return 'Network error occurred while loading ad';
      case AdErrorType.invalidAdUnit:
        return 'Invalid ad unit ID provided';
      case AdErrorType.timeout:
        return 'Ad request timed out';
      case AdErrorType.noFill:
        return 'No ad available to serve';
      case AdErrorType.internalError:
        return 'Internal SDK error occurred';
      case AdErrorType.unknown:
        return 'Unknown error occurred while loading ad';
      case AdErrorType.frequencyCapped:
        return 'Ad unit frequency cap reached';
      case AdErrorType.wrongFormat:
        return "Ad unit doesn't match the requested format";
    }
  }
}
