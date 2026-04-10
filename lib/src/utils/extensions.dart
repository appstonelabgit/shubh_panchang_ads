import 'package:apsl_ads/src/apsl_ad_base.dart';
import 'package:apsl_ads/src/enums/ad_network.dart';
import 'package:apsl_ads/src/enums/ad_unit_type.dart';

extension ApslAdBaseListExtension on List<ApslAdBase> {
  bool doesNotContain(AdNetwork adNetwork, AdUnitType type, String adUnitId) =>
      indexWhere((e) =>
          e.adNetwork == adNetwork &&
          e.adUnitType == type &&
          e.adUnitId == adUnitId) ==
      -1;
}
