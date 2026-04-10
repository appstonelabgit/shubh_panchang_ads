/// Configuration class for rewarded ad settings.
class RewardedAdConfig {
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

  /// Whether to preload rewarded ads automatically.
  ///
  /// Defaults to `true` because preloaded rewarded ads complete faster, have
  /// higher view rates, and earn more revenue. Set to `false` only if you
  /// want strict on-demand loading (e.g. for very memory-constrained apps).
  final bool preLoadRewardedAds;

  /// Whether to auto-reload after the ad is shown
  final bool autoReloadAfterShow;

  /// Creates a new [RewardedAdConfig] instance
  const RewardedAdConfig({
    this.retryDelay = defaultRetryDelay,
    this.maxRetryDelay = defaultMaxRetryDelay,
    this.maxRetries = defaultMaxRetries,
    this.useExponentialBackoff = true,
    this.enableAutoRetry = true,
    this.loadTimeout = defaultLoadTimeout,
    this.immersiveModeEnabled = true,
    this.preLoadRewardedAds = true,
    this.autoReloadAfterShow = true,
  });

  /// Creates a copy of this config with the given fields replaced
  RewardedAdConfig copyWith({
    Duration? retryDelay,
    Duration? maxRetryDelay,
    int? maxRetries,
    bool? useExponentialBackoff,
    bool? enableAutoRetry,
    Duration? loadTimeout,
    bool? immersiveModeEnabled,
    bool? preLoadRewardedAds,
    bool? autoReloadAfterShow,
  }) {
    return RewardedAdConfig(
      retryDelay: retryDelay ?? this.retryDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      maxRetries: maxRetries ?? this.maxRetries,
      useExponentialBackoff:
          useExponentialBackoff ?? this.useExponentialBackoff,
      enableAutoRetry: enableAutoRetry ?? this.enableAutoRetry,
      loadTimeout: loadTimeout ?? this.loadTimeout,
      immersiveModeEnabled: immersiveModeEnabled ?? this.immersiveModeEnabled,
      preLoadRewardedAds: preLoadRewardedAds ?? this.preLoadRewardedAds,
      autoReloadAfterShow: autoReloadAfterShow ?? this.autoReloadAfterShow,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardedAdConfig &&
          retryDelay == other.retryDelay &&
          maxRetryDelay == other.maxRetryDelay &&
          maxRetries == other.maxRetries &&
          useExponentialBackoff == other.useExponentialBackoff &&
          enableAutoRetry == other.enableAutoRetry &&
          loadTimeout == other.loadTimeout &&
          immersiveModeEnabled == other.immersiveModeEnabled &&
          preLoadRewardedAds == other.preLoadRewardedAds &&
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
        preLoadRewardedAds,
        autoReloadAfterShow,
      );
}
