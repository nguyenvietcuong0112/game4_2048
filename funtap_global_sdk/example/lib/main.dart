import 'dart:async';

import 'package:flutter/material.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';

void main() => runApp(const FGSDKTesterApp());

class FGSDKTesterApp extends StatelessWidget {
  const FGSDKTesterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FGSDK Tester',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const TesterPage(),
      );
}

class TesterPage extends StatefulWidget {
  const TesterPage({super.key});

  @override
  State<TesterPage> createState() => _TesterPageState();
}

class _TesterPageState extends State<TesterPage> {
  final List<String> _log = [];
  final List<StreamSubscription<Object?>> _subs = [];
  final ScrollController _scroll = ScrollController();

  final String _playMode = 'classic';
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _subscribeEvents();
    _probe();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _say(String msg) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $msg');
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _probe() async {
    _say('sdkVersion = ${await FGSDK.getSdkVersion()}');
    _say('isInit = ${await FGSDK.isInit()}');
  }

  /// Đăng ký hết event để thấy SDK bắn gì lúc chạy.
  void _subscribeEvents() {
    void ad(String label, Stream<FGAdsInfo> s) => _subs.add(
        s.listen((i) => _say('$label  net=${i.networkName} rev=${i.revenue}')));

    ad('inters.loaded', FGSDK.onInterstitialLoaded);
    ad('inters.shown', FGSDK.onInterstitialShown);
    ad('inters.clicked', FGSDK.onInterstitialClicked);
    ad('inters.closed', FGSDK.onInterstitialClosed);
    ad('reward.loaded', FGSDK.onRewardedLoaded);
    ad('reward.shown', FGSDK.onRewardedShown);
    ad('reward.COMPLETED', FGSDK.onRewardedCompleted);
    ad('reward.closed', FGSDK.onRewardedClosed);
    ad('banner.loaded', FGSDK.onBannerLoaded);
    ad('banner.revenue', FGSDK.onBannerRevenuePaid);
    ad('mrec.loaded', FGSDK.onMRecLoaded);

    _subs.add(FGSDK.onIAPInitialized.listen((ok) => _say('iap.initialized = $ok')));
    _subs.add(FGSDK.onPurchaseCompleted
        .listen((p) => _say('iap.completed product=${p.a} tx=${p.b}')));
    _subs.add(FGSDK.onPurchaseFailed
        .listen((p) => _say('iap.failed product=${p.a} reason=${p.b}')));
    _subs.add(FGSDK.onRemoteConfigFetched.listen((_) => _say('remoteconfig.fetched')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FGSDK Tester'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(_log.clear),
            tooltip: 'Xoá log',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Wrap(spacing: 6, runSpacing: 6, children: _buttons()),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.black87,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(
                  _log[i],
                  style: const TextStyle(
                      color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buttons() {
    Widget b(String label, VoidCallback onTap) =>
        FilledButton.tonal(onPressed: onTap, child: Text(label));

    return [
      b('sdkVersion / isInit', _probe),

      // ── Ads ──
      b('Interstitial', () async {
        _say('showInterstitial…');
        await FGSDK.showInterstitial('main_menu', _playMode, _level);
        _say('showInterstitial xong');
      }),
      b('Rewarded', () async {
        _say('showRewarded…');
        await FGSDK.showRewarded('double_coin', _playMode, _level);
        _say('showRewarded xong (xem reward.COMPLETED để biết có thưởng)');
      }),
      b('isRewardedReady', () async => _say('isRewardedReady = ${await FGSDK.isRewardedReady()}')),
      b('loadRewarded', () { FGSDK.loadRewarded(); _say('loadRewarded()'); }),
      b('Banner show', () { FGSDK.showBanner('bottom', _playMode, _level); _say('showBanner()'); }),
      b('Banner hide', () { FGSDK.hideBanner(); _say('hideBanner()'); }),
      b('AppOpen', () { FGSDK.showAppOpen('resume', _playMode, _level); _say('showAppOpen()'); }),
      b('MRec load', () { FGSDK.loadMRec(); _say('loadMRec()'); }),
      b('MRec show', () {
        FGSDK.showMRec('shop', _playMode, _level, position: const FGMRecPosition.preset(3));
        _say('showMRec()');
      }),
      b('MRec hide', () { FGSDK.hideMRec(); _say('hideMRec()'); }),
      b('isMRecReady', () async => _say('isMRecReady = ${await FGSDK.isMRecReady()}')),

      // ── Tracking ──
      b('logEvent', () {
        FGSDK.logEvent('test_event', params: {'src': 'tester', 'n': 1});
        _say('logEvent(test_event)');
      }),
      b('level_start', () {
        FGSDK.logLevelStart(_level, 1, 0, _playMode);
        _say('logLevelStart($_level)');
      }),
      b('level_end (win)', () {
        FGSDK.logLevelEnd(_level, 1, 0, _playMode, 42.5, true, 'clear');
        _say('logLevelEnd($_level, success) → AppLovin level_complete');
      }),
      b('resource_source', () {
        FGSDK.logEarnResource(_playMode, _level, 'coin', 'gold', 50, 'reward', 'chest', '', 200);
        _say('logEarnResource(+50)');
      }),
      b('resource_sink', () {
        FGSDK.logSpendResource(
            _playMode, _level, 'booster', 'gold', 30, 'shop', 'buy', 'sword', 'booster', 170);
        _say('logSpendResource(-30) → AppLovin use_prop');
      }),
      b('tut success', () {
        FGSDK.logTutorial('success', 'step_3');
        _say('logTutorial(success) → AppLovin tutorial_complete');
      }),
      b('iap_show/click', () {
        FGSDK.logIAPShow(_playMode, _level, 'shop', 'pack', 'com.game.pack1');
        FGSDK.logIAPClick(_playMode, _level, 'shop', 'pack', 'com.game.pack1');
        _say('logIAPShow + logIAPClick');
      }),
      b('userProperties', () {
        FGSDK.setUserProperties({'vip_level': 3, 'faction': 'red'});
        _say('setUserProperties()');
      }),

      // ── RemoteConfig / IAP / Deeplink ──
      b('remoteConfig', () async {
        _say('rc ready = ${await FGSDK.isRemoteConfigReady()}');
        _say('rc int max_retry = ${await FGSDK.getRemoteConfigInt('max_retry', 3)}');
      }),
      b('buyProduct', () async {
        final r = await FGSDK.buyProduct('com.game.pack1', 'shop', _playMode, _level);
        _say('buyProduct ok=${r.ok} tx=${r.transactionId}');
      }),
      b('restorePurchases', () async => _say('restore = ${await FGSDK.restorePurchases()}')),
      b('deeplink', () async {
        final d = await FGSDK.getDeeplinkResult();
        _say(d == null ? 'deeplink: null' : 'deeplink ${d.scheme} / ${d.data}');
      }),
      b('level +1', () => setState(() => _level++)),
    ];
  }
}
