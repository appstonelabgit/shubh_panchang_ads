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

  /// After a frequency-cap error, no load until this much time has passed.
  /// Pass the app's interstitial cooldown; AdMob caps at 2 per 30 minutes.
  final Duration capCooldown;

  /// After no fill / timeout / network error: one retry after this delay,
  /// then wait for the next natural trigger.
  final Duration noFillRetryDelay;

  /// A cached ad older than this is dropped and loaded fresh. AdMob keeps an
  /// interstitial valid for about an hour.
  final Duration maxCacheAge;

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
    this.capCooldown = const Duration(minutes: 15),
    this.noFillRetryDelay = const Duration(seconds: 60),
    this.maxCacheAge = const Duration(minutes: 55),
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
    Duration? capCooldown,
    Duration? noFillRetryDelay,
    Duration? maxCacheAge,
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
      capCooldown: capCooldown ?? this.capCooldown,
      noFillRetryDelay: noFillRetryDelay ?? this.noFillRetryDelay,
      maxCacheAge: maxCacheAge ?? this.maxCacheAge,
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
          autoReloadAfterShow == other.autoReloadAfterShow &&
          capCooldown == other.capCooldown &&
          noFillRetryDelay == other.noFillRetryDelay &&
          maxCacheAge == other.maxCacheAge;

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
        capCooldown,
        noFillRetryDelay,
        maxCacheAge,
      );
}
