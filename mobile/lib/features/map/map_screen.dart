import 'route_option.dart';
import '../../core/design/sheets.dart';
import '../../core/design/components.dart';
import '../maintenance/screens.dart';
import '../journeys/screens.dart';
import '../journeys/store.dart';
import '../departure/controller.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/state.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/tile_client.dart';
import 'camera_session.dart';
import 'base_map.dart';
import 'traffic_refresh.dart';
import '../../core/performance.dart';
import '../location/location_service.dart';
import '../departure/screens.dart';

import 'package:url_launcher/url_launcher.dart';

class MapScreen extends ConsumerStatefulWidget {
  final bool autoStartNavigation;
  final bool compact;
  final Place? initialDestination;
  final VoidCallback? onExpand;
  final VoidCallback? onCancelSearch;
  final BaseMapSource? source;
  final SavedTrip? plannedTrip;
  final String? plannedVehicle;
  final String? journeyId, direction, occurrenceId;
  const MapScreen({
    super.key,
    this.source,
    this.autoStartNavigation = false,
    this.compact = false,
    this.initialDestination,
    this.onExpand,
    this.onCancelSearch,
    this.plannedTrip,
    this.plannedVehicle,
    this.journeyId,
    this.direction,
    this.occurrenceId,
  });
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final map = MapController();
  final query = TextEditingController();
  final hanoi = const LatLng(21.0285, 105.8542);
  late final CameraSession cameraSession;
  late final BaseMapSource baseMap;
  late final TrafficRefreshPolicy trafficRefresh;
  bool get trafficAvailable => false;
  final locationService = LocationService();
  String vehicle = 'car';
  bool locating = false;
  LatLng? location;
  double heading = 0;
  Place? destination;
  List<Place> results = [];
  List<TravelRoute> routes = [];
  TravelRoute? refreshedProposal;
  int selected = 0, searchGeneration = 0, trafficEpoch = 0, offRouteFixes = 0;
  int mapEpoch = 0;
  bool searching = false,
      loading = false,
      navigating = false,
      refreshing = false,
      foreground = true;
  String? error, tileError;
  String copyrightCaption = '© Geoapify • © OpenStreetMap contributors';
  String? activeTripId;
  Map<String, dynamic>? copyright;
  String? attributionToken;
  DateTime? lastTileReceived, lastRefresh, lastSuggestion;
  Timer? debounce, refreshTimer;
  DateTime? searchBlockedUntil;
  CancelToken? searchCancel;
  StreamSubscription<Position>? gps;
  late final TileClient mapClient, trafficClient;
  final mapTileUpdates = TileUpdateTransformers.debounce(
    const Duration(milliseconds: 250),
  );
  final trafficTileUpdates = TileUpdateTransformers.debounce(
    const Duration(milliseconds: 250),
  );
  void tileFailure(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tileError != message) setState(() => tileError = message);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  TravelRoute? get current =>
      routes.isEmpty ? null : routes[selected.clamp(0, routes.length - 1)];

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.plannedTrip;
    if (widget.compact &&
        current == null &&
        incoming?.route != null &&
        oldWidget.plannedTrip != incoming) {
      destination = incoming!.destination;
      routes = [incoming.route!];
      vehicle = incoming.vehicle;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.compact &&
            cameraSession.gestureRevision == 0 &&
            current!.points.length > 1) {
          map.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(current!.points),
              padding: const EdgeInsets.all(24),
            ),
          );
        }
      });
    }
    if (widget.initialDestination != null &&
        widget.initialDestination != oldWidget.initialDestination) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) choose(widget.initialDestination!);
      });
    }
  }

  Widget searchCredit(Iterable<Place> places) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        onPressed: () => launchUrl(Uri.parse('https://www.geoapify.com/')),
        child: const Text('Powered by Geoapify'),
      ),
      TextButton(
        onPressed: () =>
            launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
        child: const Text('© OpenStreetMap contributors'),
      ),
      for (final credit
          in places.map((p) => p.sourceAttribution).whereType<String>().toSet())
        if (!credit.contains('OpenStreetMap')) Text(credit),
    ],
  );

  @override
  void initState() {
    super.initState();
    if (widget.autoStartNavigation) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (current == null) await calculate();
        if (mounted && current != null) await start();
      });
    }
    vehicle = ref.read(stateProvider).defaultVehicle;
    if (widget.plannedTrip != null) {
      destination = widget.plannedTrip!.destination;
      vehicle = widget.plannedVehicle ?? widget.plannedTrip!.vehicle;
      if (widget.plannedTrip!.route != null) {
        routes = [widget.plannedTrip!.route!];
      }
    }
    cameraSession = ref.read(cameraSessionProvider);
    baseMap = widget.source ?? BaseMapSource.configured();
    if (baseMap.name == 'geoapify') {
      copyrightCaption = baseMap.attribution;
      copyright = {
        'notices': 'Powered by Geoapify; © OpenStreetMap contributors; Open Database License',
      };
    }
    trafficRefresh = TrafficRefreshPolicy(DateTime.now());
    WidgetsBinding.instance.addTimingsCallback(PerformanceLog.instance.frames);
    mapClient = TileClient(
      () {},
      onFailure: (message) => tileFailure('Bản đồ: $message'),
    );
    trafficClient = TileClient(() {
      if (mounted &&
          (lastTileReceived == null ||
              DateTime.now().difference(lastTileReceived!).inSeconds > 10)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => lastTileReceived = DateTime.now());
        });
      }
    }, onFailure: (message) => tileFailure('Traffic: $message'));
    WidgetsBinding.instance.addObserver(this);
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      if (mounted &&
          trafficRefresh.shouldRefresh(
            now,
            foreground:
                foreground && (ModalRoute.of(context)?.isCurrent ?? true),
            enabled: ref.read(stateProvider).traffic && trafficAvailable,
            navigating: navigating,
            blocked: trafficClient.blockedUntil?.isAfter(now) ?? false,
          )) {
        trafficRefresh.refreshed(now);
        PerformanceLog.instance.phase = 'traffic_refresh';
        setState(() {
          trafficEpoch++;
          lastTileReceived = null;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(
      PerformanceLog.instance.frames,
    );
    debounce?.cancel();
    refreshTimer?.cancel();
    searchCancel?.cancel();
    gps?.cancel();
    query.dispose();
    map.dispose();
    mapClient.close();
    trafficClient.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      gps?.cancel();
      gps = null;
    } else if (navigating) {
      watchPosition();
    }
  }

  void fail(Object e) {
    if (mounted) setState(() => error = errorMessage(e));
  }

  Future<bool> permission() async {
    await locationService.permission();
    return true;
  }

  Future<void> locationFailure(Object e) async {
    fail(e);
    if (!mounted ||
        e is! LocationFailure ||
        !['blocked', 'disabled'].contains(e.code)) {
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cài đặt vị trí'),
        content: Text(e.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Đóng'),
          ),
          TrafficPrimaryButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Mở cài đặt'),
          ),
        ],
      ),
    );
    if (open == true) {
      if (e.code == 'blocked') {
        await Geolocator.openAppSettings();
      } else {
        await Geolocator.openLocationSettings();
      }
    }
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() => locating = true);
    final revision = cameraSession.gestureRevision;
    try {
      final p = await locationService.current();
      if (!mounted) return;
      setState(() {
        location = LatLng(p.latitude, p.longitude);
        error = null;
      });
      if (cameraSession.gestureRevision == revision) {
        cameraSession.following = navigating;
        map.move(location!, map.camera.zoom);
      }
    } catch (e) {
      await locationFailure(e);
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void search(String value) {
    debounce?.cancel();
    searchCancel?.cancel();
    final generation = ++searchGeneration;
    if (value.trim().length < 3) {
      setState(() {
        results = [];
        searching = false;
      });
      return;
    }
    if (searchBlockedUntil?.isAfter(DateTime.now()) ?? false) {
      setState(() {
        searching = false;
        error = 'Tìm kiếm đang tạm giới hạn. Chờ rồi nhập lại.';
      });
      return;
    }
    setState(() => searching = true);
    debounce = Timer(const Duration(milliseconds: 650), () async {
      final cancel = CancelToken();
      searchCancel = cancel;
      try {
        final places = await ref
            .read(apiProvider)
            .search(value.trim(), location ?? hanoi, cancel);
        if (!mounted || generation != searchGeneration) return;
        setState(() {
          results = places;
          searching = false;
          error = places.isEmpty ? 'Không tìm thấy địa điểm.' : null;
        });
      } catch (e) {
        if (e is DioException && e.response?.statusCode == 429) {
          final seconds =
              int.tryParse(e.response?.headers.value('retry-after') ?? '') ??
              60;
          searchBlockedUntil = DateTime.now().add(
            Duration(seconds: seconds.clamp(1, 86400)),
          );
        }
        if (!mounted ||
            generation != searchGeneration ||
            CancelToken.isCancel(
              e is DioException
                  ? e
                  : DioException(requestOptions: RequestOptions()),
            )) {
          return;
        }
        setState(() => searching = false);
        fail(e);
      }
    });
  }

  void cancelSearch() {
    debounce?.cancel();
    searchCancel?.cancel();
    searchGeneration++;
    FocusScope.of(context).unfocus();
    query.clear();
    setState(() {
      destination = null;
      routes = [];
      results = [];
      refreshedProposal = null;
      selected = 0;
      searching = false;
      loading = false;
      error = null;
    });
    if (widget.onCancelSearch != null) {
      widget.onCancelSearch!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  void choose(Place p) {
    if (navigating) stop();
    searchCancel?.cancel();
    debounce?.cancel();
    searchGeneration++;
    ref.read(stateProvider).recordSearch(query.text.trim());
    FocusScope.of(context).unfocus();
    query.clear();
    setState(() {
      destination = p;
      results = [];
      routes = [];
      refreshedProposal = null;
      searching = false;
      error = null;
    });
    map.move(p.point, 15);
  }

  Future<void> calculate() async {
    if (destination == null || loading) return;
    final target = destination!;
    final revision = cameraSession.gestureRevision;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.plannedTrip == null && location == null) await locate();
      final origin = widget.plannedTrip?.origin.point ?? location;
      if (origin == null || !mounted || destination != target) return;
      final answer = await ref
          .read(apiProvider)
          .routes(origin, target, vehicle: vehicle);
      if (!mounted || destination != target) return;
      setState(() {
        routes = answer;
        selected = 0;
        if (answer.isEmpty) {
          error = 'Nhà cung cấp không trả về tuyến phù hợp.';
        }
      });
      if (answer.isNotEmpty &&
          answer.first.points.length > 1 &&
          cameraSession.gestureRevision == revision) {
        map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(answer.first.points),
            padding: const EdgeInsets.fromLTRB(45, 180, 45, 320),
          ),
        );
      }
    } catch (e) {
      if (mounted && destination == target) fail(e);
    } finally {
      if (mounted && destination == target) setState(() => loading = false);
    }
  }

  Future<void> start() async {
    try {
      await permission();
      if (!mounted) return;
      setState(() {
        navigating = true;
        activeTripId = newId();
        PerformanceLog.instance.phase = 'navigation';
        cameraSession.following = true;
        lastRefresh = DateTime.now();
        error = null;
      });
      watchPosition();
    } catch (e) {
      fail(e);
    }
  }

  void watchPosition() {
    gps?.cancel();
    gps =
        Geolocator.getPositionStream(
          locationSettings: locationService.settings(stream: true),
        ).listen(
          (p) {
            if (!mounted || !navigating || !foreground) return;
            final point = LatLng(p.latitude, p.longitude);
            setState(() {
              location = point;
              heading = p.heading.isFinite && p.heading >= 0 ? p.heading : 0;
            });
            if (cameraSession.following) {
              map.move(point, map.camera.zoom);
            }
            if (p.accuracy > 60) return;
            final route = current;
            if (route == null) return;
            offRouteFixes =
                distanceToRoute(point, route.points) >
                    math.max(60, p.accuracy * 2)
                ? offRouteFixes + 1
                : 0;
            if (destination != null &&
                const Distance().as(
                      LengthUnit.Meter,
                      point,
                      destination!.point,
                    ) <
                    35) {
              finishJourney();
              setState(() => error = 'Bạn đang ở gần điểm đến.');
              return;
            }
            if (offRouteFixes >= 3) {
              setState(
                () => error = 'Có thể bạn đã lệch tuyến. Dừng ở nơi an toàn rồi nhấn Tính lại.',
              );
            }
            if (DateTime.now().difference(lastRefresh ?? DateTime(2000)) >=
                const Duration(minutes: 5)) {
              refreshRoute();
            }
          },
          onError: (Object e) {
            fail(e);
            stop();
          },
        );
  }

  Future<void> finishJourney() async {
    final route = current;
    final origin =
        widget.plannedTrip?.origin ??
        (location == null ? null : Place('Điểm xuất phát', location!));
    final id = widget.occurrenceId ?? activeTripId;
    stop();
    if (route == null || origin == null || destination == null || id == null) {
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bạn đã hoàn thành hành trình?'),
        content: const Text(
          'Chỉ chuyến được xác nhận mới được tính vào thống kê.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Chỉ dừng dẫn đường'),
          ),
          TrafficPrimaryButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Đã hoàn thành'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      try {
        if (widget.occurrenceId != null) {
          await ref.read(departureProvider).mutate(
            'PATCH',
            'occurrences/${widget.occurrenceId}',
            {'status': 'completed'},
          );
        }
        await ref
            .read(journeysProvider)
            .complete(
              id,
              journeyId: widget.journeyId,
              direction: widget.direction,
              trip: SavedTrip(
                widget.plannedTrip?.name ?? 'Đến ${destination!.name}',
                origin,
                destination!,
                route: route,
                vehicle: vehicle,
              ),
            );
        if (mounted) {
          showTrafficSuccess(context, 'Đã ghi nhận chuyến đi hoàn thành');
        }
      } catch (e) {
        fail(e);
      }
    }
  }

  void stop() {
    gps?.cancel();
    gps = null;
    setState(() {
      navigating = false;
      cameraSession.following = false;
      offRouteFixes = 0;
    });
  }

  Future<void> refreshRoute() async {
    if (refreshing ||
        (location == null && widget.plannedTrip == null) ||
        destination == null ||
        current == null) {
      return;
    }
    refreshing = true;
    lastRefresh = DateTime.now();
    final previous = current!;
    final target = destination!;
    final wasNavigating = navigating;
    final routeOrigin = navigating
        ? location
        : widget.plannedTrip?.origin.point ?? location;
    if (routeOrigin == null) {
      refreshing = false;
      return;
    }
    try {
      final answer = await ref
          .read(apiProvider)
          .routes(routeOrigin, target, refresh: true, vehicle: vehicle);
      if (!mounted ||
          navigating != wasNavigating ||
          destination != target ||
          current != previous ||
          answer.isEmpty) {
        return;
      }
      setState(() => refreshedProposal = answer.first);
      final fraction = !navigating || previous.meters == 0
          ? 1.0
          : (remainingDistance() * 1000 / previous.meters).clamp(0.0, 1.0);
      final remaining = math.max(1, (previous.seconds * fraction).round());
      // Refresh results are proposals; never silently replace the active path.
      if ((!navigating ||
              DateTime.now().difference(lastSuggestion ?? DateTime(2000)) >=
                  const Duration(minutes: 5)) &&
          (offRouteFixes >= 3 ||
              shouldSuggest(
                remaining,
                answer.first.seconds,
                DateTime.now().difference(lastSuggestion ?? DateTime(2000)),
              ) ||
              !navigating)) {
        lastSuggestion = DateTime.now();
        final accept = await showTrafficSheet<bool>(
          context,
          title: 'So sánh tuyến đề xuất',
          builder: (c) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tuyến đề xuất: ${formatEta(answer.first.seconds)}. Tiết kiệm ước tính ${formatEta(math.max(0, remaining - answer.first.seconds))}. ${answer.first.trafficAware ? 'ETA có xét giao thông.' : 'ETA chưa xét giao thông trực tiếp.'} Chỉ thao tác khi đã dừng ở nơi an toàn.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      plannedTrip: SavedTrip(
                        'Tuyến đề xuất',
                        Place('Điểm xuất phát', routeOrigin),
                        target,
                        route: answer.first,
                        vehicle: vehicle,
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Xem trên bản đồ'),
              ),
              const SizedBox(height: 12),
              TrafficButton(
                label: 'Xác nhận chuyển tuyến',
                onPressed: () => Navigator.pop(c, true),
              ),
              const SizedBox(height: 8),
              TrafficButton(
                label: 'Giữ tuyến',
                secondary: true,
                onPressed: () => Navigator.pop(c, false),
              ),
            ],
          ),
        );
        if (mounted &&
            navigating == wasNavigating &&
            destination == target &&
            current == previous &&
            accept == true) {
          setState(() {
            routes = answer;
            selected = 0;
            offRouteFixes = 0;
            error = null;
          });
        }
      }
    } catch (e) {
      fail(e);
    } finally {
      refreshing = false;
    }
  }

  Widget iconButton(IconData icon, String label, VoidCallback action) =>
      TrafficPress(
        enabled: icon != Icons.my_location || !locating,
        child: Card(
          child: IconButton(
            tooltip: label,
            onPressed: icon == Icons.my_location && locating ? null : action,
            icon: icon == Icons.my_location && locating
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: TrafficMotion.reduced(context) ? .5 : null,
                    ),
                  )
                : Icon(icon),
          ),
        ),
      );
  Future<void> loadAttribution(String token) async {
    if (!baseMap.usesTomTom && !trafficAvailable) {
      attributionToken = token;
      return;
    }
    if (token.isEmpty || attributionToken == token) return;
    attributionToken = token;
    try {
      final data = await ref.read(apiProvider).attribution();
      if (mounted) {
        setState(() {
          copyright = data;
          copyrightCaption = data['caption'] as String;
        });
      }
    } catch (e) {
      fail(e);
    }
  }

  Future<void> showCopyright() async {
    if (copyright == null) {
      attributionToken = null;
      await loadAttribution(ref.read(stateProvider).token);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(copyrightCaption),
        content: SingleChildScrollView(
          child: SelectableText(
            '${baseMap.attribution}\n${baseMap.usesTomTom ? '' : 'https://www.openstreetmap.org/copyright\n'}${copyright == null ? 'Chưa tải được thông tin bản quyền.' : const JsonEncoder.withIndent('  ').convert(copyright!['notices'])}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stateProvider);
    final color = Theme.of(context).colorScheme;
    if (state.token.isNotEmpty && attributionToken != state.token) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadAttribution(state.token);
      });
    }
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            key: const ValueKey('trafficgo-map-camera'),
            mapController: map,
            options: MapOptions(
              initialCenter: cameraSession.center,
              initialZoom: cameraSession.zoom,
              initialRotation: cameraSession.rotation,
              keepAlive: true,
              onMapReady: () {
                if (widget.plannedTrip?.route != null &&
                    current!.points.length > 1) {
                  map.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(current!.points),
                      padding: widget.compact
                          ? const EdgeInsets.all(24)
                          : const EdgeInsets.fromLTRB(40, 180, 40, 300),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  PerformanceLog.instance.firstMapFrameMs ??=
                      PerformanceLog.instance.started.elapsedMicroseconds /
                      1000;
                });
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  PerformanceLog.instance.phase =
                      camera.zoom != cameraSession.zoom ? 'zoom' : 'pan';
                  trafficRefresh.interact(DateTime.now());
                }
                final wasFollowing = cameraSession.following;
                cameraSession.update(
                  camera.center,
                  camera.zoom,
                  camera.rotation,
                  gesture: hasGesture,
                );
                if (hasGesture && wasFollowing && mounted) setState(() {});
              },
              minZoom: 7,
              maxZoom: 18,
              onLongPress: (_, p) {
                if (!navigating) choose(Place('Điểm đã chọn', p));
              },
            ),
            children: [
              if (state.token.isNotEmpty || !baseMap.usesBackend)
                TileLayer(
                  key: ValueKey('map-$mapEpoch-${state.token}'),
                  panBuffer: 0,
                  tileUpdateTransformer: mapTileUpdates,
                  urlTemplate: baseMap.usesTomTom
                      ? '$apiBase/api/v1/tiles/map/{z}/{x}/{y}.png'
                      : baseMap.name == 'geoapify'
                      ? '$apiBase/api/v1/geo/tiles/{z}/{x}/{y}.png'
                      : baseMap.url,
                  tileBuilder: (context, child, tile) {
                    if (tile.loadFinishedAt != null && !tile.loadError) {
                      PerformanceLog.instance.decodedTile();
                    }
                    return child;
                  },
                  tileProvider: NetworkTileProvider(
                    httpClient: mapClient,
                    cachingProvider: const DisabledMapCachingProvider(),
                    headers: baseMap.usesBackend
                        ? {'X-App-Token': state.token}
                        : {},
                  ),
                  userAgentPackageName: 'vn.trafficgo.trafficgo',
                  errorTileCallback: (_, e, stack) {
                    if (mounted && tileError == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(
                            () => tileError = 'Không tải được bản đồ. Kiểm tra token, API key và kết nối.',
                          );
                        }
                      });
                    }
                  },
                ),
              if (state.token.isNotEmpty && state.traffic && trafficAvailable)
                TileLayer(
                  key: ValueKey('traffic-$trafficEpoch-${state.token}'),
                  panBuffer: 0,
                  tileUpdateTransformer: trafficTileUpdates,
                  urlTemplate:
                      '$apiBase/api/v1/tiles/traffic/{z}/{x}/{y}.png?epoch=$trafficEpoch',
                  tileBuilder: (context, child, tile) {
                    if (tile.loadFinishedAt != null && !tile.loadError) {
                      PerformanceLog.instance.decodedTile();
                    }
                    return child;
                  },
                  tileProvider: NetworkTileProvider(
                    httpClient: trafficClient,
                    cachingProvider: const DisabledMapCachingProvider(),
                    headers: {'X-App-Token': state.token},
                  ),
                  userAgentPackageName: 'vn.trafficgo.trafficgo',
                  errorTileCallback: (_, e, stack) {
                    if (mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && tileError == null) {
                          setState(
                            () => tileError = 'Lớp giao thông không khả dụng.',
                          );
                        }
                      });
                    }
                  },
                ),
              PolylineLayer(
                polylines: [
                  for (var i = 0; i < routes.length; i++)
                    if (i != selected)
                      Polyline(
                        points: routes[i].points,
                        color: color.outline.withValues(alpha: .65),
                        strokeWidth: 5,
                      ),
                  if (current != null)
                    Polyline(
                      points: current!.points,
                      color: color.brightness == Brightness.dark
                          ? const Color(0xffd9fa84)
                          : const Color(0xff20252b),
                      strokeWidth: 7,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (destination != null)
                    Marker(
                      point: destination!.point,
                      width: 180,
                      height: 72,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.location_pin,
                            size: 40,
                            color: Color(0xff20252b),
                          ),
                          Flexible(
                            child: Tooltip(
                              message: destination!.name,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.surface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  destination!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: color.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (location != null)
                    Marker(
                      point: location!,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        label: 'Vị trí hiện tại',
                        child: Transform.rotate(
                          angle: heading * math.pi / 180,
                          child: const Icon(
                            Icons.navigation_rounded,
                            size: 36,
                            color: Color(0xff007cde),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (widget.compact) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 64,
              child: Material(
                color: color.surface.withValues(alpha: .94),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () =>
                          launchUrl(Uri.parse('https://www.geoapify.com/')),
                      child: const Text(
                        '© Geoapify',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                      child: const Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                tooltip: 'Mở bản đồ toàn màn hình',
                onPressed: widget.onExpand,
                icon: const Icon(Icons.open_in_full_rounded),
              ),
            ),
            if (tileError != null)
              Positioned(
                bottom: 8,
                left: 8,
                right: 64,
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  color: color.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Chưa tải được bản đồ. Mở để thử lại.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
          ],
          if (!widget.compact) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .55,
                ),
                child: SingleChildScrollView(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!baseMap.usesTomTom)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                children: [
                                  if (baseMap.name == 'geoapify')
                                    TextButton(
                                      onPressed: () => launchUrl(
                                        Uri.parse('https://www.geoapify.com/'),
                                      ),
                                      child: const Text(
                                        'Powered by Geoapify',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  if (baseMap.name == 'stadia_dev')
                                    TextButton(
                                      onPressed: () => launchUrl(
                                        Uri.parse('https://stadiamaps.com/'),
                                      ),
                                      child: const Text(
                                        '© Stadia Maps',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  if (baseMap.name == 'stadia_dev')
                                    TextButton(
                                      onPressed: () => launchUrl(
                                        Uri.parse('https://openmaptiles.org/'),
                                      ),
                                      child: const Text(
                                        '© OpenMapTiles',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: () => launchUrl(
                                      Uri.parse(
                                        'https://www.openstreetmap.org/copyright',
                                      ),
                                    ),
                                    child: Text(
                                      baseMap.name == 'stadia_dev' ||
                                              baseMap.name == 'geoapify'
                                          ? '© OpenStreetMap contributors'
                                          : baseMap.attribution,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              const Icon(
                                Icons.explore,
                                color: Color(0xff20252b),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'TrafficGo',
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (!navigating)
                                TextButton.icon(
                                  onPressed: cancelSearch,
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Hủy'),
                                ),
                              PopupMenuButton<String>(
                                tooltip: 'Hành trình và chi phí',
                                icon: const Icon(Icons.apps),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'route',
                                    child: Text('Tìm tuyến giữa hai địa điểm'),
                                  ),
                                  PopupMenuItem(
                                    value: 'journeys',
                                    child: Text('Hành trình đi học / đi làm'),
                                  ),
                                  PopupMenuItem(
                                    value: 'garage',
                                    child: Text('Xe và bảo dưỡng'),
                                  ),
                                  PopupMenuItem(
                                    value: 'cost',
                                    child: Text('Chi phí và thống kê'),
                                  ),
                                ],
                                onSelected: (value) async {
                                  if (value == 'route') {
                                    final trip =
                                        await Navigator.push<SavedTrip>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RoutePlanner(),
                                          ),
                                        );
                                    if (trip != null && context.mounted) {
                                      ref.read(stateProvider).saveTrip(trip);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MapScreen(plannedTrip: trip),
                                        ),
                                      );
                                    }
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => value == 'journeys'
                                            ? const JourneysScreen()
                                            : value == 'garage'
                                            ? const GarageScreen()
                                            : const ExpensesScreen(),
                                      ),
                                    );
                                  }
                                },
                              ),
                              iconButton(
                                Icons.bookmark_outline,
                                'Địa điểm đã lưu',
                                () async {
                                  final p = await context.push<Place>('/saved');
                                  if (p != null && mounted) choose(p);
                                },
                              ),
                              iconButton(
                                Icons.tune_rounded,
                                'Cài đặt',
                                () => context.push('/settings'),
                              ),
                            ],
                          ),
                          if (!navigating)
                            Material(
                              elevation: 1,
                              borderRadius: BorderRadius.circular(20),
                              child: TextField(
                                controller: query,
                                onChanged: search,
                                decoration: InputDecoration(
                                  hintText: 'Bạn muốn đi đâu ở Hà Nội?',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    tooltip: 'Xóa tìm kiếm',
                                    onPressed: () {
                                      query.clear();
                                      search('');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                  filled: true,
                                  fillColor: color.surface,
                                ),
                              ),
                            ),
                          if (query.text.isEmpty &&
                              destination == null &&
                              state.saved.isNotEmpty)
                            SizedBox(
                              height: 52,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: state.saved.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (c, index) => TrafficPress(
                                  child: ActionChip(
                                    avatar: Icon(
                                      placeIcon(state.saved[index].name),
                                      size: 18,
                                    ),
                                    backgroundColor: color.primaryContainer,
                                    side: BorderSide.none,
                                    label: Text(state.saved[index].name),
                                    onPressed: () => choose(state.saved[index]),
                                  ),
                                ),
                              ),
                            ),
                          if (searching)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Đang tìm địa điểm',
                            ),
                          if (results.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 260),
                              child: Card(
                                child: ListView(
                                  shrinkWrap: true,
                                  children: results
                                      .map(
                                        (p) => ListTile(
                                          leading: const Icon(
                                            Icons.place_outlined,
                                          ),
                                          title: Text(p.name),
                                          onTap: () => choose(p),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          if (results.any((p) => p.provider == 'geoapify'))
                            searchCredit(results),
                          if (query.text.isEmpty &&
                              state.historyEnabled &&
                              destination == null &&
                              state.history.isNotEmpty)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.history),
                                title: Text(state.history.first),
                                onTap: () {
                                  query.text = state.history.first;
                                  search(query.text);
                                },
                              ),
                            ),
                          if (state.token.isEmpty)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.key),
                                title: const Text(
                                  'Kết nối backend để mở bản đồ thật',
                                ),
                                subtitle: const Text(
                                  'Thiết lập access token trong Cài đặt.',
                                ),
                                onTap: () => context.push('/settings'),
                              ),
                            ),
                          if (error != null || tileError != null)
                            Card(
                              color: color.errorContainer,
                              child: ListTile(
                                title: Text(error ?? tileError!),
                                trailing: IconButton(
                                  tooltip: 'Đóng thông báo',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() {
                                    error = null;
                                    tileError = null;
                                  }),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: MediaQuery.paddingOf(context).top + 170,
              child: Column(
                children: [
                  iconButton(
                    Icons.my_location,
                    navigating && !cameraSession.following
                        ? 'Tiếp tục theo dõi vị trí'
                        : locating
                        ? 'Đang lấy vị trí…'
                        : 'Định vị tôi',
                    locate,
                  ),
                  iconButton(
                    state.traffic ? Icons.layers : Icons.layers_outlined,
                    'Bật hoặc tắt giao thông',
                    () => state.setTraffic(!state.traffic),
                  ),
                  iconButton(
                    Icons.refresh,
                    'Tải lại bản đồ',
                    () => setState(() {
                      mapEpoch++;
                      trafficEpoch++;
                      trafficRefresh.refreshed(DateTime.now());
                      tileError = null;
                    }),
                  ),
                ],
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: destination == null ? 0.22 : 0.38,
              minChildSize: .16,
              maxChildSize: .85,
              snap: true,
              snapSizes: const [.16, .38, .85],
              builder: (context, scroll) => Container(
                decoration: BoxDecoration(
                  color: color.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 20),
                  ],
                ),
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 38),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: showCopyright,
                        child: Text('$copyrightCaption • Bản quyền dữ liệu'),
                      ),
                    ),
                    if (destination?.provider == 'geoapify')
                      searchCredit([destination!]),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: color.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                navigating
                                    ? 'Đang trên hành trình'
                                    : destination?.name ?? 'Chào Hà Nội!',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (current != null)
                                Text(
                                  '${formatEta(current!.seconds)} • ${(current!.meters / 1000).toStringAsFixed(1)} km',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(color: color.primary),
                                ),
                            ],
                          ),
                        ),
                        if (destination != null && !navigating)
                          Tooltip(
                            message: current == null
                                ? 'Tìm đường'
                                : 'Bắt đầu hành trình',
                            child: TrafficPrimaryButton(
                              onPressed: loading
                                  ? null
                                  : current == null
                                  ? calculate
                                  : start,
                              phase: loading
                                  ? TrafficButtonPhase.loading
                                  : TrafficButtonPhase.idle,
                              child: Icon(
                                current == null
                                    ? Icons.route_rounded
                                    : Icons.navigation_rounded,
                              ),
                            ),
                          ),
                        if (destination != null)
                          IconButton(
                            tooltip: 'Lưu địa điểm',
                            onPressed: () async {
                              final name = await editText(
                                context,
                                'Lưu địa điểm',
                                initial: destination!.name,
                              );
                              if (name != null && name.isNotEmpty) {
                                await state.save(
                                  Place(
                                    name,
                                    destination!.point,
                                    provider: destination!.provider,
                                    sourceAttribution:
                                        destination!.sourceAttribution,
                                  ),
                                );
                                if (context.mounted) {
                                  showTrafficSuccess(
                                    context,
                                    'Đã lưu địa điểm',
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.bookmark_add_outlined),
                          ),
                      ],
                    ),
                    if (destination == null)
                      const Text(
                        'Tìm địa điểm hoặc nhấn giữ trên bản đồ để chọn điểm đến.',
                      ),
                    if (!navigating &&
                        ref.watch(departureProvider).next != null)
                      const NextDepartureCard(),
                    const SizedBox(height: 12),
                    TrafficToggle<String>(
                      value: vehicle,
                      values: const ['car', 'motorcycle'],
                      label: (v) => v == 'car' ? 'Ô tô' : 'Xe máy',
                      icon: (v) => v == 'car'
                          ? Icons.directions_car_rounded
                          : Icons.two_wheeler_rounded,
                      onChanged: navigating || loading
                          ? null
                          : (v) => setState(() {
                              vehicle = v;
                              routes = [];
                              selected = 0;
                              refreshedProposal = null;
                            }),
                    ),
                    if (vehicle == 'motorcycle')
                      const Text(
                        'Tuân thủ biển báo và đường cấm xe máy thực tế. Nguồn ETA hiển thị theo từng tuyến.',
                      ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator(),
                      ),
                    if (current != null) ...[
                      if (!navigating)
                        TextButton.icon(
                          onPressed:
                              location == null && widget.plannedTrip == null
                              ? null
                              : () {
                                  state.saveTrip(
                                    SavedTrip(
                                      'Đến ${destination!.name}',
                                      widget.plannedTrip?.origin ??
                                          Place(
                                            'Điểm xuất phát đã chọn',
                                            location!,
                                          ),
                                      destination!,
                                      route: current,
                                      vehicle: vehicle,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Đã lưu đúng tuyến đang chọn và ETA tham khảo.',
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Lưu tuyến thường dùng'),
                        ),
                      for (var i = 0; i < routes.length; i++)
                        RouteOption(
                          route: routes[i],
                          selected: selected == i,
                          fastest: routes.length > 1 && i == 0,
                          onTap: navigating
                              ? null
                              : () => setState(() => selected = i),
                        ),
                      Text(
                        '${current!.provider} • ${current!.trafficAware ? 'ETA có xét traffic' : 'ETA KHÔNG có traffic realtime'}${current!.provider == 'tomtom' && vehicle == 'motorcycle' ? ' • Xe máy beta: kiểm tra biển báo và đường cấm' : ''} • ETA tham khảo cập nhật ${current!.retrievedAt.toLocal().toString().substring(0, 16)}${current!.fallbackReason == null ? '' : ' • dùng provider dự phòng'}',
                      ),
                      if (!navigating)
                        OutlinedButton.icon(
                          onPressed: refreshing ? null : refreshRoute,
                          icon: const Icon(Icons.alt_route),
                          label: const Text(
                            'Tìm tuyến nhanh hơn / cập nhật ETA',
                          ),
                        ),
                      if (navigating) ...[
                        if (refreshedProposal != null)
                          Text(
                            'ETA mới từ vị trí GPS: ${formatEta(refreshedProposal!.seconds)} • tải ${refreshedProposal!.retrievedAt.toLocal().toString().substring(11, 19)}. Đây là tuyến đề xuất, chưa thay tuyến đang chọn.',
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Còn lại theo tuyến: ${remainingDistance().toStringAsFixed(1)} km (ước tính GPS)',
                        ),
                        if (current!.instructions.isNotEmpty)
                          const Text(
                            'Có dữ liệu hướng dẫn từ provider; MVP chưa xác định rẽ tiếp theo hoặc phát giọng nói.',
                          ),
                        OutlinedButton(
                          onPressed: refreshing ? null : refreshRoute,
                          child: Text(
                            refreshing
                                ? 'Đang cập nhật…'
                                : 'Cập nhật / Tính lại tuyến',
                          ),
                        ),
                        TrafficPrimaryButton(
                          onPressed: finishJourney,
                          child: const Text('Kết thúc hành trình'),
                        ),
                      ] else
                        TrafficPrimaryButton.icon(
                          onPressed: start,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Bắt đầu hành trình'),
                        ),
                    ] else if (destination != null)
                      TrafficPrimaryButton.icon(
                        onPressed: loading ? null : calculate,
                        phase: loading
                            ? TrafficButtonPhase.loading
                            : TrafficButtonPhase.idle,
                        icon: const Icon(Icons.route),
                        label: Text(
                          widget.plannedTrip == null
                              ? 'Tìm đường từ vị trí của tôi'
                              : 'Tìm đường theo lịch đã lưu',
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (state.traffic && !trafficAvailable)
                      const Text(
                        'Dữ liệu giao thông realtime chưa khả dụng. ETA dựa trên routing.',
                      ),
                    if (state.traffic && trafficAvailable) ...[
                      Text(
                        lastTileReceived == null
                            ? 'Chưa nhận được tile giao thông trong phiên làm mới này.'
                            : 'Nhận tile lúc ${lastTileReceived!.toLocal().toString().substring(11, 19)} • không phải thời điểm đo',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const Text(
                        'TomTom relative0 • tốc độ / tốc độ thông thoáng',
                        style: TextStyle(fontSize: 12),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 5,
                        children: [
                          legend(const Color(0xff2eab30), '≥75%'),
                          legend(const Color(0xfff1bf40), '35–75%'),
                          legend(const Color(0xfff18237), '15–35%'),
                          legend(const Color(0xffe70704), '<15%'),
                          legend(const Color(0xffc1272d), 'Đóng đường'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Traffic chỉ tự làm mới khi đang điều hướng hoặc vừa tương tác. Khi đứng yên, nhấn tải lại nếu cần dữ liệu mới. Thời điểm nhận tile không phải thời điểm đo.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 5, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
  double remainingDistance() {
    if (location == null || current == null) return 0;
    final points = current!.points;
    if (points.isEmpty) return 0;
    final distance = const Distance();
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = distance.as(LengthUnit.Meter, location!, points[i]);
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    double remaining = best;
    for (var i = nearest + 1; i < points.length; i++) {
      remaining += distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return remaining / 1000;
  }
}
