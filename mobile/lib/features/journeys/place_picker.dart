import '../../core/design/components.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../app/state.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/tile_client.dart';
import '../location/location_service.dart';

Future<Place?> pickPlace(
  BuildContext context, {
  String title = 'Chọn địa điểm',
}) => Navigator.push<Place>(
  context,
  MaterialPageRoute(builder: (_) => PlacePicker(title: title)),
);

class PlacePicker extends ConsumerStatefulWidget {
  final String title;
  const PlacePicker({super.key, required this.title});
  @override
  ConsumerState<PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends ConsumerState<PlacePicker> {
  final text = TextEditingController();
  final client = TileClient(() {});
  Timer? debounce;
  DateTime? blockedUntil;
  CancelToken? cancel;
  List<Place> results = [];
  Place? chosen;
  String? error;
  bool busy = false, showMap = false;
  int revision = 0;
  void search(String q) {
    debounce?.cancel();
    cancel?.cancel();
    final rev = ++revision;
    setState(() {
      chosen = null;
      results = [];
      busy = false;
      error = null;
    });
    if (q.trim().length < 2) return;
    if (blockedUntil?.isAfter(DateTime.now()) ?? false) {
      setState(
        () => error =
            'Tìm kiếm đang giới hạn lượt gọi. Vui lòng chờ rồi nhập lại.',
      );
      return;
    }
    debounce = Timer(const Duration(milliseconds: 650), () async {
      final token = cancel = CancelToken();
      setState(() => busy = true);
      try {
        final answer = await ref
            .read(apiProvider)
            .search(q.trim(), const LatLng(21.0285, 105.8542), token);
        if (mounted && rev == revision) setState(() => results = answer);
      } catch (e) {
        if (mounted && rev == revision && !token.isCancelled) {
          if (e is DioException && e.response?.statusCode == 429) {
            blockedUntil = DateTime.now().add(
              Duration(
                seconds:
                    int.tryParse(
                      e.response?.headers.value('retry-after') ?? '',
                    ) ??
                    60,
              ),
            );
          }
          setState(() => error = errorMessage(e));
        }
      } finally {
        if (mounted && rev == revision) setState(() => busy = false);
      }
    });
  }

  Future<void> gps() async {
    setState(() => busy = true);
    try {
      final p = await LocationService().current();
      if (mounted) {
        Navigator.pop(
          context,
          Place('Vị trí hiện tại', LatLng(p.latitude, p.longitude)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    cancel?.cancel();
    text.dispose();
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: text,
              onChanged: search,
              decoration: const InputDecoration(
                labelText: 'Tên địa điểm hoặc địa chỉ',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: busy ? null : gps,
                icon: const Icon(Icons.my_location),
                label: const Text('GPS hiện tại'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => showMap = !showMap),
                icon: const Icon(Icons.map),
                label: const Text('Chạm bản đồ'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (showMap)
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: const LatLng(21.0285, 105.8542),
                  initialZoom: 13,
                  onTap: (_, p) => setState(
                    () => chosen = Place(
                      text.text.trim().isEmpty
                          ? 'Điểm đã chọn trên bản đồ'
                          : text.text.trim(),
                      p,
                    ),
                  ),
                ),
                children: [
                  TileLayer(
                    panBuffer: 0,
                    tileUpdateTransformer: TileUpdateTransformers.debounce(
                      const Duration(milliseconds: 250),
                    ),
                    urlTemplate: '$apiBase/api/v1/geo/tiles/{z}/{x}/{y}.png',
                    tileProvider: NetworkTileProvider(
                      httpClient: client,
                      headers: {'X-App-Token': state.token},
                    ),
                  ),
                  if (chosen != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: chosen!.point,
                          child: const Icon(Icons.location_pin, size: 40),
                        ),
                      ],
                    ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  if (text.text.trim().isEmpty)
                    const ListTile(title: Text('Địa điểm đã lưu')),
                  for (final p
                      in text.text.trim().isEmpty ? state.saved : results)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text(p.address),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  if (!busy &&
                      text.text.trim().length >= 2 &&
                      results.isEmpty &&
                      error == null)
                    const ListTile(
                      title: Text(
                        'Không tìm thấy địa điểm. Có thể chọn trên bản đồ.',
                      ),
                    ),
                ],
              ),
            ),
          const Text('Powered by Geoapify • © OpenStreetMap contributors'),
          if (chosen != null)
            SafeArea(
              child: TrafficPrimaryButton(
                onPressed: () => Navigator.pop(context, chosen),
                child: Text('Chọn ${chosen!.name}'),
              ),
            ),
        ],
      ),
    );
  }
}
