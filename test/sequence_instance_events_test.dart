import 'package:apsl_ads/apsl_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ids extends AdsIdManager {
  const _Ids();

  @override
  List<AppAdIds> get appAdIds => const [
        AppAdIds(
          appId: '',
          adNetwork: AdNetwork.adManager,
          bannerId: '/1/banner',
          nativeId: '/1/native',
        ),
        AppAdIds(
          appId: 'ca-app-pub-1~1',
          adNetwork: AdNetwork.admob,
          bannerId: 'ca-app-pub-1/2',
          nativeId: 'ca-app-pub-1/3',
        ),
      ];
}

class _FakeAd extends StatelessWidget {
  const _FakeAd(this.adNetwork, this.onLoaded, this.onFailed);

  final AdNetwork adNetwork;
  final ApslAdCallback onLoaded;
  final ApslAdCallback onFailed;

  @override
  Widget build(BuildContext context) =>
      Text(adNetwork.name, textDirection: TextDirection.ltr);
}

Widget _fake(AdNetwork n, ApslAdCallback loaded, ApslAdCallback failed) =>
    _FakeAd(n, loaded, failed);

_FakeAd _adIn(WidgetTester tester, Key key) => tester.widget<_FakeAd>(
      find.descendant(of: find.byKey(key), matching: find.byType(_FakeAd)),
    );

void main() {
  const a = ValueKey('a');
  const b = ValueKey('b');

  setUpAll(() => ApslAds.instance.adIdManager = const _Ids());

  tearDown(() {
    ApslSequenceBannerAd.debugChildBuilder = null;
    ApslSequenceNativeAd.debugChildBuilder = null;
  });

  Widget pair(Widget first, Widget second) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [first, second]),
      );

  testWidgets('one sequence banner failing leaves the other untouched',
      (tester) async {
    ApslSequenceBannerAd.debugChildBuilder = _fake;
    final loaded = <String>[];
    final failed = <String>[];
    ApslSequenceBannerAd banner(String id, Key key) => ApslSequenceBannerAd(
          key: key,
          onAdLoaded: (n, t, d, {errorMessage, rewardType, rewardAmount}) =>
              loaded.add(id),
          onAdFailedToLoad: (n, t, d,
                  {errorMessage, rewardType, rewardAmount}) =>
              failed.add(id),
        );

    await tester.pumpWidget(pair(banner('a', a), banner('b', b)));
    expect(_adIn(tester, a).adNetwork, AdNetwork.adManager);
    expect(_adIn(tester, b).adNetwork, AdNetwork.adManager);

    _adIn(tester, b).onLoaded(AdNetwork.adManager, AdUnitType.banner, null);
    _adIn(tester, a).onFailed(AdNetwork.adManager, AdUnitType.banner, null);
    await tester.pump();

    expect(_adIn(tester, a).adNetwork, AdNetwork.admob);
    expect(_adIn(tester, b).adNetwork, AdNetwork.adManager);
    expect(loaded, ['b']);
    expect(failed, ['a']);

    // A stale failure from the network A already left does not skip admob.
    _adIn(tester, a).onFailed(AdNetwork.adManager, AdUnitType.banner, null);
    await tester.pump();
    expect(_adIn(tester, a).adNetwork, AdNetwork.admob);
    expect(_adIn(tester, b).adNetwork, AdNetwork.adManager);
  });

  testWidgets('a failure fired while building is deferred, not thrown',
      (tester) async {
    ApslSequenceBannerAd.debugChildBuilder = (n, loaded, failed) {
      if (n == AdNetwork.adManager) {
        failed(n, AdUnitType.banner, null);
      }
      return _FakeAd(n, loaded, failed);
    };
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ApslSequenceBannerAd(key: a),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_adIn(tester, a).adNetwork, AdNetwork.admob);
  });

  testWidgets('one sequence native failing leaves the other untouched',
      (tester) async {
    ApslSequenceNativeAd.debugChildBuilder = _fake;
    final loaded = <String>[];
    ApslSequenceNativeAd native(String id, Key key) => ApslSequenceNativeAd(
          key: key,
          onAdLoaded: (n, t, d, {errorMessage, rewardType, rewardAmount}) =>
              loaded.add(id),
        );

    await tester.pumpWidget(pair(native('a', a), native('b', b)));
    _adIn(tester, a).onLoaded(AdNetwork.adManager, AdUnitType.native, null);
    _adIn(tester, b).onFailed(AdNetwork.adManager, AdUnitType.native, null);
    await tester.pump();

    expect(_adIn(tester, a).adNetwork, AdNetwork.adManager);
    expect(_adIn(tester, b).adNetwork, AdNetwork.admob);
    expect(loaded, ['a']);
  });
}
