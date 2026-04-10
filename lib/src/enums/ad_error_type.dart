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
    }
  }
}
