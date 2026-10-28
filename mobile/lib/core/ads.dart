import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Only official sample IDs. Real IDs require a separate release review.
class TrafficAds extends ChangeNotifier {
  static final instance = TrafficAds();
  bool ready = false, navigating = false, _initializing = false;
  InterstitialAd? _interstitial;
  bool _loading = false, _transition = false;
  DateTime? _lastShown;
  final DateTime _opened = DateTime.now();
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get visible => supported && ready && !navigating;
  bool get android => defaultTargetPlatform == TargetPlatform.android;
  String get bannerId => android
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';
  static bool cooldownElapsed(DateTime now, DateTime previous) =>
      now.difference(previous) >= const Duration(minutes: 3);

  Future<void> initialize() async {
    if (!supported || ready || _initializing) return;
    _initializing = true;
    try {
      // UMP decides whether requests are allowed; never block app startup.
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((_) async {
          if (await ConsentInformation.instance.canRequestAds()) {
            await MobileAds.instance.initialize();
            ready = true;
            notifyListeners();
            _loadInterstitial();
          }
          _initializing = false;
        }),
        (_) {
          _initializing = false;
        },
      );
    } catch (_) {
      _initializing = false;
    }
  }

  void setNavigation(bool value) {
    if (navigating == value) return;
    navigating = value;
    notifyListeners();
  }

  void _loadInterstitial() {
    if (!ready || _loading || _interstitial != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) {
          _loading = false;
        },
      ),
    );
  }

  Future<void> beforeTabChange(VoidCallback proceed) async {
    if (_transition) return;
    final now = DateTime.now();
    final ad = _interstitial;
    if (!visible ||
        ad == null ||
        !cooldownElapsed(now, _lastShown ?? _opened)) {
      proceed();
      if (visible) _loadInterstitial();
      return;
    }
    _transition = true;
    _interstitial = null;
    final done = Completer<void>();
    void finish() {
      ad.dispose();
      if (!done.isCompleted) done.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _lastShown = DateTime.now();
      },
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, _) => finish(),
    );
    try {
      await ad.show();
      await done.future;
    } catch (_) {
      finish();
    } finally {
      _transition = false;
    }
    proceed();
    _loadInterstitial();
  }
}

class TrafficAdBanner extends StatefulWidget {
  const TrafficAdBanner({super.key});
  @override
  State<TrafficAdBanner> createState() => _TrafficAdBannerState();
}

class _TrafficAdBannerState extends State<TrafficAdBanner> {
  BannerAd? _ad;
  int? _width;
  bool _loaded = false;
  bool _failed = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    TrafficAds.instance.addListener(_changed);
  }

  void _changed() {
    if (!TrafficAds.instance.visible) {
      _revision++;
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      _failed = false;
      _width = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _load(int width) async {
    final revision = ++_revision;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted ||
        revision != _revision ||
        !TrafficAds.instance.visible ||
        size == null) {
      return;
    }
    final ad = BannerAd(
      adUnitId: TrafficAds.instance.bannerId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted && revision == _revision) {
            setState(() {
              _loaded = true;
            });
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted && revision == _revision) {
            setState(() {
              _ad = null;
              _loaded = false;
              _failed = true;
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _revision++;
    TrafficAds.instance.removeListener(_changed);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed ||
        !TrafficAds.instance.visible ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 32).floor();
        if (_width != width && width > 0) {
          _width = width;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ad?.dispose();
            _ad = null;
            _loaded = false;
            unawaited(_load(width));
          });
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Quảng cáo thử nghiệm',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: _ad?.size.width.toDouble() ?? width.toDouble(),
                height: _ad?.size.height.toDouble() ?? 60,
                child: _loaded && _ad != null ? AdWidget(ad: _ad!) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
