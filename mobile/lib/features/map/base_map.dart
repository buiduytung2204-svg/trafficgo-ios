import 'package:flutter/foundation.dart';

class BaseMapSource {
  final String name, url, attribution;
  const BaseMapSource(this.name, this.url, this.attribution);
  bool get usesTomTom => name == 'tomtom';
  bool get usesBackend => usesTomTom || name == 'geoapify';

  static BaseMapSource configured({
    String source = const String.fromEnvironment(
      'BASE_MAP_SOURCE',
      defaultValue: 'geoapify',
    ),
    String osmUrl = const String.fromEnvironment('OSM_RASTER_URL'),
    String attribution = const String.fromEnvironment('OSM_RASTER_ATTRIBUTION'),
    bool? web,
    String? hostname,
  }) {
    if (source == 'geoapify') {
      return const BaseMapSource(
        'geoapify',
        '',
        '© Geoapify • © OpenStreetMap contributors',
      );
    }
    if (source == 'tomtom') {
      throw StateError('TomTom đã ngừng hỗ trợ. Chọn Geoapify.');
    }
    if (source == 'stadia_dev') {
      final host = hostname ?? Uri.base.host;
      if (!(web ?? kIsWeb) || !['localhost', '127.0.0.1'].contains(host)) {
        throw StateError(
          'stadia_dev chỉ dùng trên Web localhost; iOS cần endpoint OSM được cấp phép riêng.',
        );
      }
      return const BaseMapSource(
        'stadia_dev',
        'https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}.png',
        '© Stadia Maps • © OpenMapTiles • © OpenStreetMap contributors',
      );
    }
    final uri = Uri.tryParse(osmUrl);
    if (source != 'osm_raster' ||
        uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        attribution.trim().isEmpty ||
        !['{z}', '{x}', '{y}'].every(osmUrl.contains) ||
        uri.host == 'tile.openstreetmap.org' ||
        uri.host.endsWith('.tile.openstreetmap.org')) {
      throw StateError(
        'Cần URL raster OSM và attribution được cấp phép; không dùng máy chủ tile OSM cộng đồng.',
      );
    }
    if (uri.scheme == 'http' &&
        !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)) {
      throw StateError('OSM production phải dùng HTTPS.');
    }
    return BaseMapSource('osm_raster', osmUrl, attribution);
  }
}
