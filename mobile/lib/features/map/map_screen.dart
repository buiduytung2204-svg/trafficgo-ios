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

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final map = MapController();
  final query = TextEditingController();
  final hanoi = const LatLng(21.0285, 105.8542);
  late final CameraSession cameraSession;
  LatLng? location;
  double heading = 0;
  Place? destination;
  List<Place> results = [];
  List<TravelRoute> routes = [];
  TravelRoute? refreshedProposal;
  int selected = 0, searchGeneration = 0, trafficEpoch = 0, offRouteFixes = 0;
  bool searching = false,
      loading = false,
      navigating = false,
      refreshing = false,
      foreground = true;
  String? error, tileError;
  String copyrightCaption = '© TomTom';
  Map<String, dynamic>? copyright;
  String? attributionToken;
  DateTime? lastTileReceived, lastRefresh, lastSuggestion;
  Timer? debounce, refreshTimer;
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
  void initState() {
    super.initState();
    cameraSession = ref.read(cameraSessionProvider);
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
    refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted && foreground && ref.read(stateProvider).traffic) {
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
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('GPS đang tắt. Hãy bật Dịch vụ định vị trong Cài đặt.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Quyền vị trí đã bị chặn. Mở Cài đặt ứng dụng để cấp lại quyền.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Chưa có quyền vị trí. Bạn vẫn có thể xem bản đồ.');
    }
    return true;
  }

  Future<void> locate() async {
    final revision = cameraSession.gestureRevision;
    try {
      await permission();
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
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
      fail(e);
    }
  }

  void search(String value) {
    debounce?.cancel();
    searchCancel?.cancel();
    final generation = ++searchGeneration;
    if (value.trim().length < 2) {
      setState(() {
        results = [];
        searching = false;
      });
      return;
    }
    setState(() => searching = true);
    debounce = Timer(const Duration(milliseconds: 400), () async {
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
      if (location == null) await locate();
      if (location == null || !mounted || destination != target) return;
      final answer = await ref.read(apiProvider).routes(location!, target);
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
      fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> start() async {
    try {
      await permission();
      if (!mounted) return;
      setState(() {
        navigating = true;
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
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 12,
          ),
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
              stop();
              setState(() => error = 'Bạn đang ở gần điểm đến.');
              return;
            }
            if (offRouteFixes >= 3) {
              setState(
                () => error =
                    'Có thể bạn đã lệch tuyến. Dừng ở nơi an toàn rồi nhấn Tính lại.',
              );
            }
            if (DateTime.now().difference(lastRefresh ?? DateTime(2000)) >=
                const Duration(seconds: 90)) {
              refreshRoute();
            }
          },
          onError: (Object e) {
            fail(e);
            stop();
          },
        );
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
        location == null ||
        destination == null ||
        current == null) {
      return;
    }
    refreshing = true;
    lastRefresh = DateTime.now();
    final previous = current!;
    final target = destination!;
    try {
      final answer = await ref
          .read(apiProvider)
          .routes(location!, target, refresh: true);
      if (!mounted || !navigating || destination != target || answer.isEmpty) {
        return;
      }
      setState(() => refreshedProposal = answer.first);
      final elapsed = DateTime.now().difference(previous.retrievedAt).inSeconds;
      final remaining = math.max(1, previous.seconds - elapsed);
      // Refresh results are proposals; never silently replace the active path.
      if (offRouteFixes >= 3 ||
          shouldSuggest(
            remaining,
            answer.first.seconds,
            DateTime.now().difference(lastSuggestion ?? DateTime(2000)),
          )) {
        lastSuggestion = DateTime.now();
        final accept = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Có tuyến mới'),
            content: Text(
              'Ước tính ${formatEta(answer.first.seconds)}. Chỉ thao tác khi đã dừng ở nơi an toàn.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Giữ tuyến'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Chọn tuyến mới'),
              ),
            ],
          ),
        );
        if (mounted && navigating && accept == true) {
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

  Widget iconButton(IconData icon, String label, VoidCallback action) => Card(
    child: IconButton(tooltip: label, onPressed: action, icon: Icon(icon)),
  );
  Future<void> loadAttribution(String token) async {
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
            copyright == null
                ? 'Chưa tải được thông tin bản quyền.'
                : const JsonEncoder.withIndent(
                    '  ',
                  ).convert(copyright!['notices']),
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
              onPositionChanged: (camera, hasGesture) {
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
              if (state.token.isNotEmpty)
                TileLayer(
                  key: ValueKey('map-${state.token}'),
                  panBuffer: 0,
                  tileUpdateTransformer: mapTileUpdates,
                  urlTemplate: '$apiBase/api/v1/tiles/map/{z}/{x}/{y}.png',
                  tileProvider: NetworkTileProvider(
                    httpClient: mapClient,
                    cachingProvider: const DisabledMapCachingProvider(),
                    headers: {'X-App-Token': state.token},
                  ),
                  userAgentPackageName: 'vn.trafficgo.trafficgo',
                  errorTileCallback: (_, e, stack) {
                    if (mounted && tileError == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(
                            () => tileError =
                                'Không tải được bản đồ. Kiểm tra token, API key và kết nối.',
                          );
                        }
                      });
                    }
                  },
                ),
              if (state.token.isNotEmpty && state.traffic)
                TileLayer(
                  key: ValueKey('traffic-$trafficEpoch-${state.token}'),
                  panBuffer: 0,
                  tileUpdateTransformer: trafficTileUpdates,
                  urlTemplate:
                      '$apiBase/api/v1/tiles/traffic/{z}/{x}/{y}.png?epoch=$trafficEpoch',
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
                        color: color.primary.withValues(alpha: .3),
                        strokeWidth: 5,
                      ),
                  if (current != null)
                    Polyline(
                      points: current!.points,
                      color: const Color(0xff007cde),
                      strokeWidth: 7,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (destination != null)
                    Marker(
                      point: destination!.point,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_pin,
                        size: 48,
                        color: Color(0xff007c78),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.explore, color: Color(0xff007c78)),
                      const SizedBox(width: 8),
                      Text(
                        'TrafficGo',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
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
                      elevation: 3,
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
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(p.name),
                                  onTap: () => choose(p),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
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
                        title: const Text('Kết nối backend để mở bản đồ thật'),
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
          Positioned(
            right: 16,
            top: MediaQuery.paddingOf(context).top + 170,
            child: Column(
              children: [
                iconButton(
                  Icons.my_location,
                  navigating && !cameraSession.following
                      ? 'Tiếp tục theo dõi vị trí'
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
                    trafficEpoch++;
                    tileError = null;
                  }),
                ),
              ],
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: destination == null ? 0.22 : 0.38,
            minChildSize: .16,
            maxChildSize: .65,
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
                        child: Text(
                          navigating
                              ? 'Đang trên hành trình'
                              : destination?.name ?? 'Chào Hà Nội!',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (destination != null)
                        IconButton(
                          tooltip: 'Lưu địa điểm',
                          onPressed: () async {
                            final controller = TextEditingController(
                              text: destination!.name,
                            );
                            final name = await showDialog<String>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Lưu địa điểm'),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(
                                    hintText: 'Nhà, Trường học, Công ty...',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Hủy'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(
                                      c,
                                      controller.text.trim(),
                                    ),
                                    child: const Text('Lưu'),
                                  ),
                                ],
                              ),
                            );
                            if (name != null && name.isNotEmpty) {
                              state.save(Place(name, destination!.point));
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      const Chip(
                        avatar: Icon(Icons.directions_car, size: 18),
                        label: Text('Ô tô'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.two_wheeler, size: 18),
                        label: const Text('Xe máy • chưa hỗ trợ'),
                        onPressed: () => setState(
                          () => error =
                              'Chưa xác minh được tuyến xe máy hợp lệ tại Việt Nam.',
                        ),
                      ),
                    ],
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  if (current != null) ...[
                    if (!navigating)
                      TextButton.icon(
                        onPressed: location == null
                            ? null
                            : () {
                                state.saveTrip(
                                  SavedTrip(
                                    'Đến ${destination!.name}',
                                    Place('Điểm xuất phát đã chọn', location!),
                                    destination!,
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Đã lưu hai điểm của tuyến thường dùng.',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Lưu tuyến thường dùng'),
                      ),
                    for (var i = 0; i < routes.length; i++)
                      Card(
                        color: selected == i
                            ? color.primaryContainer
                            : color.surfaceContainerLow,
                        child: ListTile(
                          onTap: navigating
                              ? null
                              : () => setState(() => selected = i),
                          leading: Icon(
                            i == selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(
                            '${formatEta(routes[i].seconds)} • ${(routes[i].meters / 1000).toStringAsFixed(1)} km',
                          ),
                          subtitle: Text(
                            '${i == 0 ? 'Nhanh nhất theo ETA • ' : ''}Chậm do traffic: ${routes[i].delay == null ? 'không có dữ liệu' : formatEta(routes[i].delay!)}',
                          ),
                        ),
                      ),
                    Text(
                      'Tuyến tải lúc ${current!.retrievedAt.toLocal().toString().substring(11, 19)}. ETA là ước tính của provider.',
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
                      FilledButton(
                        onPressed: stop,
                        child: const Text('Kết thúc hành trình'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: start,
                        icon: const Icon(Icons.navigation),
                        label: const Text('Bắt đầu hành trình'),
                      ),
                  ] else if (destination != null)
                    FilledButton.icon(
                      onPressed: loading ? null : calculate,
                      icon: const Icon(Icons.route),
                      label: const Text('Tìm đường từ vị trí của tôi'),
                    ),
                  const SizedBox(height: 12),
                  if (state.traffic) ...[
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
                      'Làm mới lớp traffic mỗi 2 phút khi mở app. Provider không cung cấp thời điểm đo trong raster tile.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
