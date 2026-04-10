/// Global kill switch for ad loading.
///
/// Set to `true` to prevent every ad in the package from issuing new
/// load requests. Useful for premium / paid users where you want to
/// disable advertising entirely without rebuilding your widget tree.
///
/// In-flight loads are NOT cancelled — only future calls to `load()`
/// are skipped. Toggle this BEFORE calling [ApslAds.initialize] for
/// the strongest effect.
bool forceStopToLoadAds = false;
