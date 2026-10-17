import 'package:apsl_ads/apsl_ads.dart';
import 'package:apsl_ads/src/apsl_admob/apsl_admob_native_ad.dart';
import 'package:apsl_ads/src/utils/load_retry_governor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DisabledAdUnits.reset);
  tearDown(DisabledAdUnits.reset);

  Future<void> expectReleased(ApslAdBase ad, String id) async {
    DisabledAdUnits.disable(id, reason: 'invalid');
    final failures = <String?>[];
    var ready = 0;
    ad.addOnAdFailedToLoad(
      (network, type, data, {errorMessage, rewardType, rewardAmount}) =>
          failures.add(errorMessage),
    );
    ad.addOnNativeAdReadyForSetState(
      (network, type, data, {errorMessage, rewardType, rewardAmount}) =>
          ready++,
    );
    await ad.load();
    expect(failures, ['unit disabled']);
    expect(ready, 1);
  }

  test('admob native on a disabled unit releases its host', () async {
    const id = 'ca-app-pub-1/3';
    await expectReleased(ApslAdmobNativeAd(id), id);
  });

  test('gam native on a disabled unit releases its host', () async {
    const id = '/1/native';
    await expectReleased(ApslGamNativeAd(id), id);
  });
}
