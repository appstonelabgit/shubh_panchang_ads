import 'dart:async';

import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/apsl_admob/apsl_admob_interstitial_ad.dart';
import 'package:apsl_ads/src/apsl_admob/apsl_admob_native_ad.dart';
import 'package:apsl_ads/src/apsl_admob/apsl_admob_rewarded_ad.dart';
import 'package:apsl_ads/src/apsl_gam/apsl_gam_app_open_ad.dart'; // ignore: unnecessary_import
import 'package:apsl_ads/src/apsl_gam/apsl_gam_banner_ad.dart'; // ignore: unnecessary_import
import 'package:apsl_ads/src/apsl_gam/apsl_gam_interstitial_ad.dart'; // ignore: unnecessary_import
import 'package:apsl_ads/src/apsl_gam/apsl_gam_native_ad.dart'; // ignore: unnecessary_import
import 'package:apsl_ads/src/utils/ad_load_resumer.dart';
import 'package:apsl_ads/src/utils/apsl_event_controller.dart';
import 'package:apsl_ads/src/utils/apsl_logger.dart';
import 'package:apsl_ads/src/utils/auto_hiding_loader_dialogue.dart';
import 'package:apsl_ads/src/utils/extensions.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class ApslAds {
  ApslAds._apslAds();
  static final ApslAds instance = ApslAds._apslAds();

  /// Google admob's ad request
  AdRequest _adRequest = const AdRequest();
  late final AdsIdManager adIdManager;

  /// Optional — only created when [initialize] is called with
  /// `isShowAppOpenOnAppStateChange: true`.
  AppLifecycleReactor? _appLifecycleReactor;

  /// Re-arms ad loads when the device regains connectivity or the app
  /// returns to the foreground. Created lazily on first [initialize].
  AdLoadResumer? _loadResumer;

  final _eventController = ApslEventController();
  Stream<AdEvent> get onEvent => _eventController.onEvent;

  List<ApslAdBase> get _allAds =>
      [..._interstitialAds, ..._rewardedAds, ..._appOpenAds];

  /// All the App Open Ads ads will be stored in it
  final List<ApslAdBase> _appOpenAds = [];

  /// All the Interstitial ads will be stored in it
  final List<ApslAdBase> _interstitialAds = [];

  /// All the Rewarded ads will be stored in it
  final List<ApslAdBase> _rewardedAds = [];

  /// [_logger] is used to show Ad logs in the console
  final ApslLogger _logger = ApslLogger();

  /// On banner, ad badge will appear
  bool get showAdBadge => _showAdBadge;
  bool _showAdBadge = false;

  /// Configuration applied to interstitial ads created during [initialize].
  InterstitialAdConfig _interstitialAdConfig = const InterstitialAdConfig();

  /// Configuration applied to rewarded ads created during [initialize].
  RewardedAdConfig _rewardedAdConfig = const RewardedAdConfig();

  int _interstitialAdIndex = 0;
  int _rewardedAdIndex = 0;
  int _appOpenAdIndex = 0;

  int _navigationCount = 0;
  int _showNavigationAdAfterCount = 1;

  /// [_isMobileAdNetworkInitialized] is used to check if admob is initialized or not
  bool _isMobileAdNetworkInitialized = false;

  /// Initializes the Google Mobile Ads SDK and preloads ads.
  ///
  /// Call this method as early as possible after the app launches.
  ///
  /// * [adMobAdRequest] is reused for every AdMob request. Defaults to an
  ///   empty request.
  /// * [interstitialAdConfig] / [rewardedAdConfig] let consumers tune retry
  ///   policy, timeout, and immersive mode for the two highest-revenue ad
  ///   formats. If omitted, the package defaults are used.
  /// * Cold start: this future resolves as soon as the SDK reports
  ///   initialized. Ad preloads are kicked off in parallel and tracked in
  ///   the background — they do not block your `runApp` call.
  Future<void> initialize(
    AdsIdManager manager, {
    bool isShowAppOpenOnAppStateChange = false,
    AdRequest? adMobAdRequest,
    RequestConfiguration? admobConfiguration,
    bool enableLogger = true,
    bool showAdBadge = false,
    int showNavigationAdAfterCount = 1,
    InterstitialAdConfig? interstitialAdConfig,
    RewardedAdConfig? rewardedAdConfig,
  }) async {
    _showAdBadge = showAdBadge;
    _showNavigationAdAfterCount = showNavigationAdAfterCount;
    _interstitialAdConfig = interstitialAdConfig ?? const InterstitialAdConfig();
    _rewardedAdConfig = rewardedAdConfig ?? const RewardedAdConfig();
    if (enableLogger) _logger.enable(enableLogger);
    adIdManager = manager;
    if (adMobAdRequest != null) {
      _adRequest = adMobAdRequest;
    }

    if (admobConfiguration != null) {
      MobileAds.instance.updateRequestConfiguration(admobConfiguration);
    }

    for (var appAdId in manager.appAdIds) {
      if (appAdId.appId.isEmpty) continue;
      final adNetworkName = getAdNetworkFromString(appAdId.adNetwork.name);
      switch (adNetworkName) {
        case AdNetwork.admob:
          // Initialize the Mobile Ads SDK exactly once. We await this
          // because no ad load can succeed before the SDK is ready.
          if (!_isMobileAdNetworkInitialized) {
            final response = await MobileAds.instance.initialize();

            response.adapterStatuses.forEach((key, value) {
              _logger.logInfo(
                  'Google-mobile-ads Adapter status for $key: ${value.description}');
            });

            // The SDK is considered initialized if AT LEAST ONE adapter is
            // in the ready state. Picking the first adapter (as the previous
            // code did) was wrong because the iteration order over the
            // adapterStatuses map is not guaranteed to start with a
            // ready adapter — leading to a misleading "failed to initialize"
            // log even when ad loads subsequently succeeded.
            final anyAdapterReady = response.adapterStatuses.values
                .any((s) => s.state == AdapterInitializationState.ready);

            _eventController.fireNetworkInitializedEvent(
                AdNetwork.admob, anyAdapterReady);

            _isMobileAdNetworkInitialized = true;
          }

          // Wire up ad managers and kick off all preloads in parallel.
          // We intentionally do NOT await the individual ad loads here:
          // each ad's listener handles its own state, and blocking the
          // initialize() future on three sequential network round-trips
          // adds multiple seconds to cold start.
          _initAdmob(
            appOpenAdUnitId: appAdId.appOpenId,
            interstitialAdUnitId: appAdId.interstitialId,
            rewardedAdUnitId: appAdId.rewardedId,
            isShowAppOpenOnAppStateChange: isShowAppOpenOnAppStateChange,
          );
          break;

        case AdNetwork.adManager:
          // GAM uses the same Google Mobile Ads SDK — initialize once.
          if (!_isMobileAdNetworkInitialized) {
            final response = await MobileAds.instance.initialize();

            response.adapterStatuses.forEach((key, value) {
              _logger.logInfo(
                  'Google-mobile-ads Adapter status for $key: ${value.description}');
            });

            final anyAdapterReady = response.adapterStatuses.values
                .any((s) => s.state == AdapterInitializationState.ready);

            _eventController.fireNetworkInitializedEvent(
                AdNetwork.adManager, anyAdapterReady);

            _isMobileAdNetworkInitialized = true;
          }

          _initGam(
            appOpenAdUnitId: appAdId.appOpenId,
            interstitialAdUnitId: appAdId.interstitialId,
            isShowAppOpenOnAppStateChange: isShowAppOpenOnAppStateChange,
          );
          break;

        case AdNetwork.any:
          break;
      }
    }

    // Begin watching for connectivity / lifecycle signals so any ad that
    // exhausts its retry budget on a flaky network gets a fresh chance
    // when the network recovers — without users having to restart the app.
    _loadResumer ??= AdLoadResumer(adsProvider: () => _allAds)..start();
  }

  /// Creates a banner ad for the specified ad network.
  ///
  /// This method creates and returns a banner ad instance based on the provided [adNetwork].
  /// The banner ad can be customized using the following parameters:
  ///
  /// * [adSize] - The size of the banner ad (defaults to standard banner)
  /// * [config] - Optional configuration for retry behavior, loading settings, and placeholders
  ///
  /// Currently supported networks:
  /// * AdMob - Full support with all customization options
  ///
  /// Returns null if the ad network is not supported or if the banner ad ID is not configured.
  ///
  /// Example:
  /// ```dart
  /// final bannerAd = ApslAds.instance.createBanner(
  ///   adNetwork: AdNetwork.admob,
  ///   adSize: AdSize.banner,
  ///   config: BannerAdConfig(
  ///     retryDelay: Duration(seconds: 10),
  ///     maxRetries: 5,
  ///     loadingWidget: CircularProgressIndicator(),
  ///     loadTimeout: Duration(seconds: 30),
  ///   ),
  /// );
  /// ```
  ApslAdBase? createBanner({
    required AdNetwork adNetwork,
    AdSize adSize = AdSize.banner,
    BannerAdConfig? config,
    ApslAdCallback? onAdFailedToLoad,
    ApslAdCallback? onAdShowed,
  }) {
    ApslAdBase? ad;
    final bannerId = adIdManager.getAppIds(adNetwork).bannerId;

    switch (adNetwork) {
      case AdNetwork.admob:
        assert(bannerId != null,
            'You are trying to create a banner and Admob Banner id is null in ad id manager');
        if (bannerId != null) {
          ad = ApslAdmobBannerAd(
            bannerId,
            adSize: adSize,
            adRequest: _adRequest,
            config: config,
          );
          _eventController.setupEvents(ad);
          if (onAdFailedToLoad != null) ad.addOnAdFailedToLoad(onAdFailedToLoad);
          if (onAdShowed != null) ad.addOnAdShowed(onAdShowed);
        }
        break;

      case AdNetwork.adManager:
        if (bannerId != null && bannerId.isNotEmpty) {
          ad = ApslGamBannerAd(
            bannerId,
            adSize: adSize,
            config: config,
          );
          _eventController.setupEvents(ad);
          if (onAdFailedToLoad != null) ad.addOnAdFailedToLoad(onAdFailedToLoad);
          if (onAdShowed != null) ad.addOnAdShowed(onAdShowed);
        }
        break;

      default:
        ad = null;
    }
    return ad;
  }

  /// Creates a native ad for the specified ad network.
  ///
  /// This method creates and returns a native ad instance based on the provided [adNetwork].
  /// The native ad can be customized using the following parameters:
  ///
  /// * [nativeTemplateStyle] - Optional styling for the native ad template
  /// * [templateType] - The type of template to use (small, medium, or custom)
  /// * [config] - Optional configuration for retry, loading, and placeholder behavior
  ///
  /// Currently supported networks:
  /// * AdMob - Full support with all customization options
  ///
  /// Returns null if the ad network is not supported or if the native ad ID is not configured.
  ///
  /// Example:
  /// ```dart
  /// final nativeAd = ApslAds.instance.createNative(
  ///   adNetwork: AdNetwork.admob,
  ///   templateType: TemplateType.medium,
  ///   config: NativeAdConfig(
  ///     retryDelay: Duration(seconds: 10),
  ///     maxRetries: 5,
  ///     loadingWidget: CircularProgressIndicator(),
  ///     loadTimeout: Duration(seconds: 30),
  ///   ),
  /// );
  /// ```
  ApslAdBase? createNative({
    required AdNetwork adNetwork,
    NativeTemplateStyle? nativeTemplateStyle,
    TemplateType? templateType,
    NativeAdConfig? config,
    ApslAdCallback? onAdFailedToLoad,
    ApslAdCallback? onAdShowed,
  }) {
    ApslAdBase? ad;
    final nativeId = adIdManager.getAppIds(adNetwork).nativeId;

    switch (adNetwork) {
      case AdNetwork.admob:
        assert(nativeId != null,
            'You are trying to create a native ad and Admob Native id is null in ad id manager');
        if (nativeId != null) {
          ad = ApslAdmobNativeAd(
            nativeId,
            nativeTemplateStyle: nativeTemplateStyle,
            templateType: templateType,
            config: config,
          );
          _eventController.setupEvents(ad);
          if (onAdFailedToLoad != null) ad.addOnAdFailedToLoad(onAdFailedToLoad);
          if (onAdShowed != null) ad.addOnAdShowed(onAdShowed);
        }
        break;

      case AdNetwork.adManager:
        if (nativeId != null && nativeId.isNotEmpty) {
          ad = ApslGamNativeAd(
            nativeId,
            nativeTemplateStyle: nativeTemplateStyle,
            templateType: templateType,
            config: config,
          );
          _eventController.setupEvents(ad);
          if (onAdFailedToLoad != null) ad.addOnAdFailedToLoad(onAdFailedToLoad);
          if (onAdShowed != null) ad.addOnAdShowed(onAdShowed);
        }
        break;

      default:
        ad = null;
    }
    return ad;
  }

  /// Wires up AdMob ad managers and triggers preloads in parallel.
  ///
  /// All `load()` calls are intentionally fire-and-forget so that cold
  /// start isn't blocked on three sequential network round-trips.
  void _initAdmob({
    String? appOpenAdUnitId,
    String? interstitialAdUnitId,
    String? rewardedAdUnitId,
    bool isShowAppOpenOnAppStateChange = true,
  }) {
    // Interstitial
    if (interstitialAdUnitId != null &&
        _interstitialAds.doesNotContain(
          AdNetwork.admob,
          AdUnitType.interstitial,
          interstitialAdUnitId,
        )) {
      final ad = ApslAdmobInterstitialAd(
        interstitialAdUnitId,
        adRequest: _adRequest,
        config: _interstitialAdConfig,
      );
      _interstitialAds.add(ad);
      _eventController.setupEvents(ad);
      ad.load();
    }

    // Rewarded
    if (rewardedAdUnitId != null &&
        _rewardedAds.doesNotContain(
          AdNetwork.admob,
          AdUnitType.rewarded,
          rewardedAdUnitId,
        )) {
      final ad = ApslAdmobRewardedAd(
        rewardedAdUnitId,
        adRequest: _adRequest,
        config: _rewardedAdConfig,
      );
      _rewardedAds.add(ad);
      _eventController.setupEvents(ad);
      if (_rewardedAdConfig.preLoadRewardedAds) {
        ad.load();
      }
    }

    // App Open
    if (!forceStopToLoadAds &&
        appOpenAdUnitId != null &&
        _appOpenAds.doesNotContain(
          AdNetwork.admob,
          AdUnitType.appOpen,
          appOpenAdUnitId,
        )) {
      final appOpenAdManager = ApslAdmobAppOpenAd(
        appOpenAdUnitId,
        _adRequest,
      );

      // Silent preload — do NOT auto-show on first load (that bug used to
      // pop an app-open ad over the splash screen during cold start).
      appOpenAdManager.load();

      if (isShowAppOpenOnAppStateChange) {
        _appLifecycleReactor =
            AppLifecycleReactor(appOpenAdManager: appOpenAdManager);
        _appLifecycleReactor!.listenToAppStateChanges();
      }
      _appOpenAds.add(appOpenAdManager);
      _eventController.setupEvents(appOpenAdManager);
    }
  }

  /// Wires up Google Ad Manager ad managers and triggers preloads.
  void _initGam({
    String? appOpenAdUnitId,
    String? interstitialAdUnitId,
    bool isShowAppOpenOnAppStateChange = true,
  }) {
    // Interstitial
    if (interstitialAdUnitId != null &&
        _interstitialAds.doesNotContain(
          AdNetwork.adManager,
          AdUnitType.interstitial,
          interstitialAdUnitId,
        )) {
      final ad = ApslGamInterstitialAd(
        interstitialAdUnitId,
        config: _interstitialAdConfig,
      );
      _interstitialAds.add(ad);
      _eventController.setupEvents(ad);
      ad.load();
    }

    // App Open
    if (!forceStopToLoadAds &&
        appOpenAdUnitId != null &&
        _appOpenAds.doesNotContain(
          AdNetwork.adManager,
          AdUnitType.appOpen,
          appOpenAdUnitId,
        )) {
      final appOpenAdManager = ApslGamAppOpenAd(appOpenAdUnitId);
      appOpenAdManager.load();

      if (isShowAppOpenOnAppStateChange && _appLifecycleReactor == null) {
        _appLifecycleReactor =
            AppLifecycleReactor(appOpenAdManager: appOpenAdManager);
        _appLifecycleReactor!.listenToAppStateChanges();
      }
      _appOpenAds.add(appOpenAdManager);
      _eventController.setupEvents(appOpenAdManager);
    }
  }

  /// Displays [adUnitType] ad from [adNetwork]. It will check if first ad it found from list is loaded,
  /// it will be displayed if [adNetwork] is not mentioned otherwise it will load the ad.
  ///
  /// Returns bool indicating whether ad has been successfully displayed or not
  ///
  /// [adUnitType] should be mentioned here, only interstitial or rewarded should be mentioned here
  /// if [adNetwork] is provided, only that network's ad would be displayed
  /// if [shouldShowLoader] before interstitial. If it's true, you have to provide build context.
  bool showAd(
    AdUnitType adUnitType, {
    AdNetwork adNetwork = AdNetwork.any,
    bool shouldShowLoader = false,
    BuildContext? context,
  }) {
    try {
      if (adNetwork != AdNetwork.any) {
        // Specific network requested — use original behavior.
        final ad = _fetchAdByTypeAndNetwork(adUnitType, adNetwork);
        if (ad == null) {
          _logger.logInfo("No ad found for $adUnitType from $adNetwork");
          return false;
        }
        if (ad.isAdLoaded) {
          if (shouldShowLoader && context != null) {
            showLoaderDialog(context);
          }
          _updateAdIndex(adUnitType);
          ad.show();
          return true;
        } else {
          _logger.logInfo("Ad not loaded for $adUnitType from $adNetwork");
          ad.load();
          return false;
        }
      }

      // AdNetwork.any — try ALL ads of this type, starting from the
      // current round-robin index. If the current one isn't loaded,
      // try the next one instead of giving up immediately.
      final ads = _adsForType(adUnitType);
      if (ads.isEmpty) {
        _logger.logInfo("No ad found for $adUnitType");
        return false;
      }

      final startIndex = _indexForType(adUnitType);
      for (var i = 0; i < ads.length; i++) {
        final index = (startIndex + i) % ads.length;
        final ad = ads[index];

        if (ad.isAdLoaded) {
          if (shouldShowLoader && context != null) {
            showLoaderDialog(context);
          }
          _setIndexForType(adUnitType, (index + 1) % ads.length);
          ad.show();
          return true;
        }
      }

      // None loaded — trigger load on all unloaded ads.
      _logger.logInfo("No loaded ad for $adUnitType, reloading all");
      for (final ad in ads) {
        if (!ad.isAdLoaded) ad.load();
      }
      _updateAdIndex(adUnitType);
      return false;
    } catch (e) {
      _logger.logInfo("Error in showing ad: $e");
      return false;
    }
  }

  List<ApslAdBase> _adsForType(AdUnitType type) {
    switch (type) {
      case AdUnitType.interstitial:
        return _interstitialAds;
      case AdUnitType.rewarded:
        return _rewardedAds;
      case AdUnitType.appOpen:
        return _appOpenAds;
      default:
        return [];
    }
  }

  int _indexForType(AdUnitType type) {
    switch (type) {
      case AdUnitType.interstitial:
        return _interstitialAdIndex;
      case AdUnitType.rewarded:
        return _rewardedAdIndex;
      case AdUnitType.appOpen:
        return _appOpenAdIndex;
      default:
        return 0;
    }
  }

  void _setIndexForType(AdUnitType type, int index) {
    switch (type) {
      case AdUnitType.interstitial:
        _interstitialAdIndex = index;
        break;
      case AdUnitType.rewarded:
        _rewardedAdIndex = index;
        break;
      case AdUnitType.appOpen:
        _appOpenAdIndex = index;
        break;
      default:
        break;
    }
  }

  /// Loads and shows a rewarded ad, displaying a loading dialog while the
  /// load is in flight.
  ///
  /// Behavior:
  /// * If the ad is already loaded, shows it immediately with no dialog.
  /// * Otherwise shows a blocking loader, kicks off a load, and waits for
  ///   the matching `adLoaded` / `adFailedToLoad` event.
  /// * If neither event arrives within [waitTimeout], the loader is
  ///   dismissed and `false` is returned so the caller can react.
  ///
  /// Returns a future that resolves to `true` if the ad was successfully
  /// shown, `false` otherwise (no ad available, load failed, or timeout).
  Future<bool> loadAndShowRewardedAd({
    required BuildContext context,
    AdNetwork adNetwork = AdNetwork.any,
    Duration waitTimeout = const Duration(seconds: 10),
  }) async {
    final ad = _fetchAdByTypeAndNetwork(AdUnitType.rewarded, adNetwork);
    if (ad == null) {
      _logger.logInfo("No rewarded ad configured for $adNetwork");
      return false;
    }

    // Fast path: cache hit. Show immediately, no loader, no subscription.
    if (ad.isAdLoaded) {
      ad.show();
      _updateAdIndex(AdUnitType.rewarded);
      return true;
    }

    final completer = Completer<bool>();
    late StreamSubscription<AdEvent> subscription;
    Timer? timeoutTimer;

    void finish(bool result) {
      if (completer.isCompleted) return;
      timeoutTimer?.cancel();
      subscription.cancel();
      hideLoaderDialog();
      completer.complete(result);
    }

    // Subscribe BEFORE the load() call so we can't miss a synchronous
    // adLoaded event from a cache that warmed up between the isAdLoaded
    // check and now.
    subscription = onEvent.listen((event) {
      if (event.adUnitType != AdUnitType.rewarded) return;
      if (event.adNetwork != ad.adNetwork) return;

      if (event.type == AdEventType.adLoaded) {
        ad.show();
        _updateAdIndex(AdUnitType.rewarded);
        finish(true);
      } else if (event.type == AdEventType.adFailedToLoad) {
        finish(false);
      }
    });

    timeoutTimer = Timer(waitTimeout, () {
      _logger.logInfo("Rewarded ad load wait timed out after $waitTimeout");
      finish(false);
    });

    try {
      showLoaderDialog(context);
      // Fire the load — listener will react to its outcome.
      // ignore: unawaited_futures
      ad.load();
    } catch (e) {
      _logger.logInfo("Error in showing rewarded ad: $e");
      finish(false);
    }

    return completer.future;
  }

  ApslAdBase? _fetchAdByTypeAndNetwork(
      AdUnitType adUnitType, AdNetwork adNetwork) {
    final mapForAds = {
      AdUnitType.rewarded: _rewardedAds,
      AdUnitType.interstitial: _interstitialAds,
      AdUnitType.appOpen: _appOpenAds,
    };
    final mapForIndexes = {
      AdUnitType.rewarded: _rewardedAdIndex,
      AdUnitType.interstitial: _interstitialAdIndex,
      AdUnitType.appOpen: _appOpenAdIndex,
    };

    final ads = mapForAds[adUnitType];
    final index = mapForIndexes[adUnitType];

    return adNetwork != AdNetwork.any
        ? ads?.firstWhereOrNull((e) => adNetwork == e.adNetwork)
        : ads != null && ads.isNotEmpty
            ? ads[index!]
            : null;
  }

  /// Triggers a load on every interstitial / rewarded / app-open ad that
  /// isn't already loaded.
  ///
  /// You normally do not need to call this — ads are loaded at startup
  /// and automatically reloaded after each show. Use it to force-warm
  /// the cache after the user takes an action you know will trigger an
  /// ad request soon.
  ///
  /// If [adNetwork] is provided, only that network's ads are loaded.
  /// If omitted, every configured network is loaded.
  void loadAd({AdNetwork? adNetwork}) {
    for (final ad in _allAds) {
      if (ad.isAdLoaded) continue;
      if (adNetwork != null && ad.adNetwork != adNetwork) continue;
      ad.load();
    }
  }

  void _updateAdIndex(AdUnitType adUnitType) {
    switch (adUnitType) {
      case AdUnitType.interstitial:
        _interstitialAdIndex =
            (_interstitialAdIndex + 1) % _interstitialAds.length;
        break;
      case AdUnitType.rewarded:
        _rewardedAdIndex = (_rewardedAdIndex + 1) % _rewardedAds.length;
        break;
      case AdUnitType.appOpen:
        _appOpenAdIndex = (_appOpenAdIndex + 1) % _appOpenAds.length;
        break;
      default:
        break;
    }
  }

  /// Disposes every ad managed by the singleton and tears down all
  /// auxiliary subsystems (lifecycle reactor, load resumer, event
  /// controller). Safe to call multiple times.
  void destroyAds() {
    for (var ad in _allAds) {
      ad.dispose();
    }
    _interstitialAds.clear();
    _rewardedAds.clear();
    _appOpenAds.clear();
    _interstitialAdIndex = 0;
    _rewardedAdIndex = 0;
    _appOpenAdIndex = 0;

    _appLifecycleReactor?.dispose();
    _appLifecycleReactor = null;

    _loadResumer?.dispose();
    _loadResumer = null;
  }

  /// This method is used to show navigation ad after every [showNavigationAdAfterCount] navigation
  /// if [showNavigationAdAfterCount] is not provided, it will show ad after every 1 navigation
  /// This will only show interstitial ad
  bool showAdOnNavigation() {
    if ((_navigationCount % (_showNavigationAdAfterCount) == 0) &&
        _navigationCount > 0) {
      _navigationCount++;
      return showAd(AdUnitType.interstitial);
    } else {
      _navigationCount++;
      return false;
    }
  }
}
