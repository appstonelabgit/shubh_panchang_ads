import 'package:flutter/material.dart';

/// Configuration class for native ad settings.
class NativeAdConfig {
  /// Base delay for the first retry. Subsequent retries use exponential
  /// backoff (2s → 4s → 8s → …) capped at [defaultMaxRetryDelay].
  static const Duration defaultRetryDelay = Duration(seconds: 2);

  /// Cap for exponential backoff between retries.
  static const Duration defaultMaxRetryDelay = Duration(seconds: 64);

  /// Maximum number of retry attempts before giving up.
  static const int defaultMaxRetries = 5;

  /// Default load timeout — abort the load attempt if the SDK doesn't
  /// call back within this window.
  static const Duration defaultLoadTimeout = Duration(seconds: 20);

  /// Default loading placeholder widget
  static const Widget defaultLoadingWidget = SizedBox(
    height: 200,
    width: 320,
    child: Center(
      child: CircularProgressIndicator(),
    ),
  );

  /// Base delay for the first retry. Used as the seed for exponential
  /// backoff when [useExponentialBackoff] is true; used as a fixed delay
  /// when it is false.
  final Duration retryDelay;

  /// Upper bound on the exponential backoff delay between retries.
  final Duration maxRetryDelay;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Whether to use exponential backoff between retries.
  final bool useExponentialBackoff;

  /// Widget to show while ad is loading
  final Widget? loadingWidget;

  /// Whether to enable automatic retry on failure
  final bool enableAutoRetry;

  /// Timeout duration for ad loading
  final Duration? loadTimeout;

  /// Creates a new [NativeAdConfig] instance
  const NativeAdConfig({
    this.retryDelay = defaultRetryDelay,
    this.maxRetryDelay = defaultMaxRetryDelay,
    this.maxRetries = defaultMaxRetries,
    this.useExponentialBackoff = true,
    this.loadingWidget,
    this.enableAutoRetry = true,
    this.loadTimeout = defaultLoadTimeout,
  });

  /// Creates a copy of this config with the given fields replaced
  NativeAdConfig copyWith({
    Duration? retryDelay,
    Duration? maxRetryDelay,
    int? maxRetries,
    bool? useExponentialBackoff,
    Widget? loadingWidget,
    bool? enableAutoRetry,
    Duration? loadTimeout,
  }) {
    return NativeAdConfig(
      retryDelay: retryDelay ?? this.retryDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      maxRetries: maxRetries ?? this.maxRetries,
      useExponentialBackoff:
          useExponentialBackoff ?? this.useExponentialBackoff,
      loadingWidget: loadingWidget ?? this.loadingWidget,
      enableAutoRetry: enableAutoRetry ?? this.enableAutoRetry,
      loadTimeout: loadTimeout ?? this.loadTimeout,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeAdConfig &&
          retryDelay == other.retryDelay &&
          maxRetryDelay == other.maxRetryDelay &&
          maxRetries == other.maxRetries &&
          useExponentialBackoff == other.useExponentialBackoff &&
          loadingWidget == other.loadingWidget &&
          enableAutoRetry == other.enableAutoRetry &&
          loadTimeout == other.loadTimeout;

  @override
  int get hashCode => Object.hash(
        retryDelay,
        maxRetryDelay,
        maxRetries,
        useExponentialBackoff,
        loadingWidget,
        enableAutoRetry,
        loadTimeout,
      );
}
