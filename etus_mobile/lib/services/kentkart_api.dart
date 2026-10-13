import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Kentkart'ın herkese açık servisinden Edirne (ETUS) toplu taşıma verisi çeker.
///
/// Kaynak: service.kentkart.com — region=013 (Edirne). 2026-10-13'te HTTP 200
/// ile doğrulandı (bkz. AGENTS.md). Resmî bir API değil; topluluk/kentkart
/// altyapısıdır, bu yüzden sadece okuma amaçlı, sınırlı sıklıkta kullanılır.
class KentkartApi {
  static const String _base = 'https://service.kentkart.com/rl1';
  static const String _region = '013';
  static const Duration _timeout = Duration(seconds: 12);

  static Map<String, String> get _headers => const {
        'Accept': 'application/json',
      };

  static Uri _uri(String path, [Map<String, String>? q]) {
    final query = {'region': _region, 'lang': 'tr', ...?q};
    return Uri.parse('$_base$path').replace(queryParameters: query);
  }

  static Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    final res = await http
        .get(_uri(path, q), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw KentkartException('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw KentkartException('Beklenmeyen yanıt');
    }
    final result = body['result'];
    if (result is Map<String, dynamic> && result['code'] != 0) {
      throw KentkartException(result['message']?.toString() ?? 'API hatası');
    }
    return body;
  }

  /// Bölgedeki tüm hatlar ve duraklar (tek istekte).
  static Future<KentkartCatalog> fetchCatalog() async {
    final body = await _get('/web/nearest/find');
    final routes = <KentkartRoute>[];
    for (final r in (body['routeList'] as List? ?? const [])) {
      if (r is! Map) continue;
      final code = r['displayRouteCode']?.toString();
      if (code == null || code.isEmpty) continue;
      routes.add(KentkartRoute(
        routeCode: r['routeCode']?.toString() ?? '',
        displayCode: code,
        name: r['name']?.toString() ?? code,
        colorHex: r['routeColor']?.toString() ?? '1D4ED8',
        agencyName: r['agencyName']?.toString() ?? '',
      ));
    }
    final stops = <KentkartStop>[];
    for (final s in (body['stopList'] as List? ?? const [])) {
      if (s is! Map) continue;
      final id = s['stopId']?.toString();
      final lat = double.tryParse(s['lat']?.toString() ?? '');
      final lng = double.tryParse(s['lng']?.toString() ?? '');
      if (id == null || lat == null || lng == null) continue;
      stops.add(KentkartStop(
        stopId: id,
        name: s['name']?.toString() ?? 'Duraq $id',
        lat: lat,
        lng: lng,
      ));
    }
    return KentkartCatalog(routes: routes, stops: stops);
  }

  /// Bir hattın güzergâhını: polyline noktaları + sıralı duraklar.
  static Future<KentkartPath> fetchPath(String displayRouteCode,
      {int direction = 0}) async {
    final body = await _get('/web/pathInfo', {
      'direction': '$direction',
      'displayRouteCode': displayRouteCode,
      'resultType': '111111',
    });
    final paths = body['pathList'] as List? ?? const [];
    if (paths.isEmpty || paths.first is! Map) {
      throw KentkartException('Güzergâh bulunamadı');
    }
    final p = paths.first as Map;
    final points = <({double lat, double lng})>[];
    for (final pt in (p['pointList'] as List? ?? const [])) {
      if (pt is! Map) continue;
      final lat = double.tryParse(pt['lat']?.toString() ?? '');
      final lng = double.tryParse(pt['lng']?.toString() ?? '');
      if (lat != null && lng != null) points.add((lat: lat, lng: lng));
    }
    final stops = <KentkartStop>[];
    for (final s in (p['busStopList'] as List? ?? const [])) {
      if (s is! Map) continue;
      final id = s['stopId']?.toString();
      final lat = double.tryParse(s['lat']?.toString() ?? '');
      final lng = double.tryParse(s['lng']?.toString() ?? '');
      if (id == null || lat == null || lng == null) continue;
      stops.add(KentkartStop(
        stopId: id,
        name: s['stopName']?.toString() ?? 'Duraq $id',
        lat: lat,
        lng: lng,
      ));
    }
    return KentkartPath(
      displayCode: displayRouteCode,
      headSign: p['headSign']?.toString() ?? '',
      points: points,
      stops: stops,
    );
  }

  /// Bir durağın yakınındaki **canlı** otobüsler (konum + kaç durak uzakta).
  static Future<List<KentkartLiveBus>> fetchLiveBuses({
    required double lat,
    required double lng,
    required String stopId,
  }) async {
    final body = await _get('/web/nearest/bus', {
      'lat': lat.toStringAsFixed(6),
      'lng': lng.toStringAsFixed(6),
      'busStopId': stopId,
    });
    final buses = <KentkartLiveBus>[];
    for (final b in (body['busList'] as List? ?? const [])) {
      if (b is! Map) continue;
      final blat = double.tryParse(b['lat']?.toString() ?? '');
      final blng = double.tryParse(b['lng']?.toString() ?? '');
      if (blat == null || blng == null) continue;
      buses.add(KentkartLiveBus(
        busId: b['busId']?.toString() ?? '',
        plate: b['plate']?.toString() ?? '',
        lineCode: b['displayRouteCode']?.toString() ?? '',
        headSign: b['headSign']?.toString() ?? '',
        lat: blat,
        lng: blng,
        stopsAway: int.tryParse(b['stopDiff']?.toString() ?? '') ?? 0,
        minutesAway: int.tryParse(b['timeDiff']?.toString() ?? '') ?? 0,
        colorHex: b['routeColor']?.toString() ?? '1D4ED8',
      ));
    }
    buses.sort((a, b) => a.stopsAway.compareTo(b.stopsAway));
    return buses;
  }
}

class KentkartException implements Exception {
  final String message;
  const KentkartException(this.message);
  @override
  String toString() => 'KentkartException: $message';
}

class KentkartRoute {
  final String routeCode;
  final String displayCode;
  final String name;
  final String colorHex;
  final String agencyName;
  const KentkartRoute({
    required this.routeCode,
    required this.displayCode,
    required this.name,
    required this.colorHex,
    required this.agencyName,
  });
}

class KentkartStop {
  final String stopId;
  final String name;
  final double lat;
  final double lng;
  const KentkartStop({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lng,
  });
}

class KentkartCatalog {
  final List<KentkartRoute> routes;
  final List<KentkartStop> stops;
  const KentkartCatalog({required this.routes, required this.stops});
}

class KentkartPath {
  final String displayCode;
  final String headSign;
  final List<({double lat, double lng})> points;
  final List<KentkartStop> stops;
  const KentkartPath({
    required this.displayCode,
    required this.headSign,
    required this.points,
    required this.stops,
  });
}

class KentkartLiveBus {
  final String busId;
  final String plate;
  final String lineCode;
  final String headSign;
  final double lat;
  final double lng;
  final int stopsAway;
  final int minutesAway;
  final String colorHex;
  const KentkartLiveBus({
    required this.busId,
    required this.plate,
    required this.lineCode,
    required this.headSign,
    required this.lat,
    required this.lng,
    required this.stopsAway,
    required this.minutesAway,
    required this.colorHex,
  });
}
