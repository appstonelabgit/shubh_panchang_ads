import 'dart:async';
import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/utils/ad_loading_gate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Reacts to app lifecycle changes to show App Open Ads appropriately.
/// Accepts any [ApslAdBase] that implements app-open show() behavior
/// (both [ApslAdmobAppOpenAd] and [ApslGamAppOpenAd]).
class AppLifecycleReactor {
  final ApslAdBase appOpenAdManager;
  StreamSubscription<AppState>? _subscription;
  bool _hasJustResumed = false;

  AppLifecycleReactor({required this.appOpenAdManager});

  /// Start listening to foreground/background state changes.
  void listenToAppStateChanges() {
    AppStateEventNotifier.startListening();

    // Use `listen()` instead of `forEach()` to be able to cancel the subscription
    _subscription =
        AppStateEventNotifier.appStateStream.listen(_onAppStateChanged);
  }

  /// Cleanup on app shutdown to prevent leaks.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Called whenever the app state changes.
  void _onAppStateChanged(AppState state) {
    if (state == AppState.foreground) {
      if (forceStopToLoadAds || _hasJustResumed) return;

      _hasJustResumed = true;

      /// Give a brief delay to allow UI restoration (optional UX buffer)
      Future.delayed(const Duration(milliseconds: 300), () {
        _hasJustResumed = false;
        appOpenAdManager.show();
      });
    }
  }
}
