import 'dart:async';

import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Background helper that re-arms ad loads on signals which usually
/// correlate with a fresh chance at success:
///
/// * Network connectivity restored after going offline.
/// * App returning to the foreground after being backgrounded.
///
/// Without this, an ad that exhausts its retry budget on a flaky network
/// stays dead until the next app launch — even after the user clearly
/// has working internet again.
class AdLoadResumer with WidgetsBindingObserver {
  final Connectivity _connectivity;

  /// Returns the current list of ads that should be considered for
  /// re-loading on a resume signal. We take a callback (rather than a
  /// snapshot list) so [ApslAds] can hand us live references without
  /// risking stale state after `destroyAds()`.
  final List<ApslAdBase> Function() _adsProvider;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasOffline = false;
  bool _isStarted = false;

  AdLoadResumer({
    required List<ApslAdBase> Function() adsProvider,
    Connectivity? connectivity,
  })  : _adsProvider = adsProvider,
        _connectivity = connectivity ?? Connectivity();

  /// Begin listening for connectivity and lifecycle changes. Safe to call
  /// multiple times — subsequent calls are no-ops.
  void start() {
    if (_isStarted) return;
    _isStarted = true;

    WidgetsBinding.instance.addObserver(this);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (_) {
        // Connectivity stream errors are non-fatal — ignore so the rest
        // of the package keeps working.
      },
    );

    // Capture the initial connectivity state so the first transition
    // (offline → online) is detected even if the app starts offline.
    _connectivity.checkConnectivity().then((results) {
      _wasOffline = _isOffline(results);
    }).catchError((_) {});
  }

  /// Stop listening and release resources.
  void dispose() {
    if (!_isStarted) return;
    _isStarted = false;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final offline = _isOffline(results);
    if (_wasOffline && !offline) {
      // Just came back online — try to revive any dead ads.
      _retryAllUnloaded();
    }
    _wasOffline = offline;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryAllUnloaded();
    }
  }

  static bool _isOffline(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.every((r) => r == ConnectivityResult.none);
  }

  void _retryAllUnloaded() {
    for (final ad in _adsProvider()) {
      if (!ad.isAdLoaded) {
        // Fire-and-forget. Each ad's load() is internally guarded by
        // its own `_isLoading` flag, so a duplicate call is a no-op.
        ad.load();
      }
    }
  }
}
