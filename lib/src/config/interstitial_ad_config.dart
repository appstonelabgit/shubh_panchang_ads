/// Configuration class for interstitial ad settings.
class InterstitialAdConfig {
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

  /// Whether to enable automatic retry on failure
  final bool enableAutoRetry;

  /// Timeout duration for ad loading
  final Duration? loadTimeout;

  /// Whether to enable immersive mode for the ad
  final bool immersiveModeEnabled;

  /// Whether to auto-reload after the ad is shown
  final bool autoReloadAfterShow;

  /// Creates a new [InterstitialAdConfig] instance
  const InterstitialAdConfig({
    this.retryDelay = defaultRetryDelay,
    this.maxRetryDelay = defaultMaxRetryDelay,
    this.maxRetries = defaultMaxRetries,
    this.useExponentialBackoff = true,
    this.enableAutoRetry = true,
    this.loadTimeout = defaultLoadTimeout,
    this.immersiveModeEnabled = true,
    this.autoReloadAfterShow = true,
  });

  /// Creates a copy of this config with the given fields replaced
  InterstitialAdConfig copyWith({
    Duration? retryDelay,
    Duration? maxRetryDelay,
    int? maxRetries,
    bool? useExponentialBackoff,
    bool? enableAutoRetry,
    Duration? loadTimeout,
    bool? immersiveModeEnabled,
    bool? autoReloadAfterShow,
  }) {
    return InterstitialAdConfig(
      retryDelay: retryDelay ?? this.retryDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      maxRetries: maxRetries ?? this.maxRetries,
      useExponentialBackoff:
          useExponentialBackoff ?? this.useExponentialBackoff,
      enableAutoRetry: enableAutoRetry ?? this.enableAutoRetry,
      loadTimeout: loadTimeout ?? this.loadTimeout,
      immersiveModeEnabled: immersiveModeEnabled ?? this.immersiveModeEnabled,
      autoReloadAfterShow: autoReloadAfterShow ?? this.autoReloadAfterShow,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterstitialAdConfig &&
          retryDelay == other.retryDelay &&
          maxRetryDelay == other.maxRetryDelay &&
          maxRetries == other.maxRetries &&
          useExponentialBackoff == other.useExponentialBackoff &&
          enableAutoRetry == other.enableAutoRetry &&
          loadTimeout == other.loadTimeout &&
          immersiveModeEnabled == other.immersiveModeEnabled &&
          autoReloadAfterShow == other.autoReloadAfterShow;

  @override
  int get hashCode => Object.hash(
        retryDelay,
        maxRetryDelay,
        maxRetries,
        useExponentialBackoff,
        enableAutoRetry,
        loadTimeout,
        immersiveModeEnabled,
        autoReloadAfterShow,
      );
}
