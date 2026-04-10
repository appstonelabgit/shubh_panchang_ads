/// Supported ad networks.
enum AdNetwork { any, admob, adManager }

/// Extension to get string representation.
extension AdNetworkExtension on AdNetwork {
  String get value => name;
}

/// Converts a string to [AdNetwork] enum.
/// Returns [AdNetwork.any] if no match is found.
///
/// Accepts multiple formats for Ad Manager:
/// "adManager", "admanager", "gam", "ad_manager", "adplus"
AdNetwork getAdNetworkFromString(String providerName) {
  final normalized = providerName.toLowerCase().replaceAll('_', '');

  // Standard enum name match
  final match = AdNetwork.values.cast<AdNetwork?>().firstWhere(
        (e) => e!.name.toLowerCase() == normalized,
        orElse: () => null,
      );
  if (match != null) return match;

  // Additional aliases for Ad Manager
  const adManagerAliases = {'gam', 'adplus', 'googleadmanager'};
  if (adManagerAliases.contains(normalized)) {
    return AdNetwork.adManager;
  }

  return AdNetwork.any;
}
