import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'kentkart_health.dart';

/// Kentkart'ın herkese açık servisinden Edirne (ETUS) toplu taşıma verisi çeker.
///
/// Kaynak: service.kentkart.com — region=013 (Edirne). 2026-10-13'te HTTP 200
/// ile doğrulandı (bkz. AGENTS.md). Resmî bir API değil; topluluk/kentkart
/// altyapısıdır, bu yüzden sadece okuma amaçlı, sınırlı sıklıkta kullanılır.
///
/// Her yanıt [KentkartHealth] üzerinden şema doğrulamasından geçer: beklenen
/// alanlar kaybolur veya tipi değişirse bu sessizce yutulmaz, arayüzde
/// görünür bir uyarıya dönüşür.
class KentkartApi {
  static const String _base = 'https://service.kentkart.com/rl1';
  static const String _region = '013';
  static const Duration _timeout = Duration(seconds: 12);

  /// Uç nokta yolları (sağlık raporunda da bu adlar kullanılır).
  static const String endpointCatalog = '/web/nearest/find';
  static const String endpointPath = '/web/pathInfo';
  static const String endpointNearestBus = '/web/nearest/bus';

  /// Uç noktaların beklenen zorunlu alanları. Servis şeması değişirse
  /// [KentkartHealth] bu listeler üzerinden sapmayı tespit eder.
  static const Set<String> _catalogKeys = {'result', 'routeList', 'stopList'};
  static const Set<String> _pathKeys = {'result', 'pathList'};
  static const Set<String> _nearestBusKeys = {
    'result',
    'busList',
    'routeList',
  };

  /// HTTP istemcisi. Testler `package:http/testing.dart` ile bunu değiştirerek
  /// gerçek servis yanıtlarını ağa çıkmadan doğrulayabilir.
  static http.Client client = http.Client();

  static Map<String, String> get _headers => const {
        'Accept': 'application/json',
      };

  static Uri _uri(String path, [Map<String, String>? q]) {
    final query = {'region': _region, 'lang': 'tr', ...?q};
    return Uri.parse('$_base$path').replace(queryParameters: query);
  }

  static KentkartHealth get _health => KentkartHealth.instance;

  /// İstek yapar, yanıtı doğrular ve sağlık durumunu günceller.
  static Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    required Set<String> requiredKeys,
    Set<String> listKeys = const <String>{},
  }) async {
    http.Response res;
    try {
      res = await client
          .get(_uri(path, query), headers: _headers)
          .timeout(_timeout);
    } on TimeoutException catch (e) {
      final err = KentkartException(
        'Zaman aşımı (${_timeout.inSeconds} sn)',
        kind: KentkartIssueKind.network,
        cause: e,
      );
      _health.reportFailure(path, err, kind: err.kind);
      throw err;
    } catch (e) {
      final err = KentkartException(
        'Bağlantı hatası: $e',
        kind: KentkartIssueKind.network,
        cause: e,
      );
      _health.reportFailure(path, err, kind: err.kind);
      throw err;
    }

    if (res.statusCode != 200) {
      final err = KentkartException(
        'HTTP ${res.statusCode}',
        kind: KentkartIssueKind.http,
        statusCode: res.statusCode,
      );
      _health.reportFailure(path, err, kind: err.kind);
      throw err;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (e) {
      final err = KentkartException(
        'Yanıt JSON olarak çözümlenemedi',
        kind: KentkartIssueKind.payload,
        cause: e,
      );
      _health.reportFailure(path, err, kind: err.kind);
      throw err;
    }

    if (decoded is! Map<String, dynamic>) {
      final err = KentkartException(
        'Beklenmeyen yanıt gövdesi',
        kind: KentkartIssueKind.payload,
      );
      _health.reportFailure(path, err, kind: err.kind);
      throw err;
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic> && result['code'] != 0) {
      final err = KentkartException(
        result['message']?.toString() ?? 'API hatası',
        kind: KentkartIssueKind.apiError,
      );
      _health.reportFailure(path, err, kind: err.kind);
      throw err;
    }

    // Şema doğrulaması: eksik alan / tip değişimi burada tespit edilir.
    _health.validatePayload(
      endpoint: path,
      body: decoded,
      requiredKeys: requiredKeys,
      listKeys: listKeys,
    );

    return decoded;
  }

  /// Bölgedeki tüm hatlar ve duraklar (tek istekte).
  static Future<KentkartCatalog> fetchCatalog() async {
    final body = await _get(
      endpointCatalog,
      requiredKeys: _catalogKeys,
      listKeys: const {'routeList', 'stopList'},
    );
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
        name: s['name']?.toString() ?? 'Durak $id',
        lat: lat,
        lng: lng,
      ));
    }
    return KentkartCatalog(routes: routes, stops: stops);
  }

  /// Bir hattın güzergâhını: polyline noktaları + sıralı duraklar.
  ///
  /// `resultType` Kentkart bitmaskesidir (deneysel çözüm):
  /// `111111` = tamamı, `001000` = yalnızca duraklar, `010000` = yalnızca
  /// canlı araçlar. Hafif kipler veri tasarrufu için kullanılır.
  static Future<KentkartPath> fetchPath(String displayRouteCode,
      {int direction = 0, String resultType = '111111'}) async {
    final body = await _get(
      endpointPath,
      query: {
        'direction': '$direction',
        'displayRouteCode': displayRouteCode,
        'resultType': resultType,
      },
      requiredKeys: _pathKeys,
      listKeys: const {'pathList'},
    );
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
      // busStopList her durağın `routes: "1A,3,4"` CSV alanını taşır —
      // bu, tek tek stopDetail çekmeden hat eşleşmesi yapmayı sağlar.
      final rawRoutes = s['routes']?.toString() ?? '';
      final through = rawRoutes
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      stops.add(KentkartStop(
        stopId: id,
        name: s['stopName']?.toString() ?? 'Durak $id',
        lat: lat,
        lng: lng,
        routes: through,
      ));
    }
    // pathInfo busList: plateNumber/busLabel biçiminde canlı araçlar.
    final pathBuses = _parseBuses(
      {'busList': p['busList']},
      fallbackLineCode: displayRouteCode,
    );
    return KentkartPath(
      displayCode: displayRouteCode,
      headSign: p['headSign']?.toString() ?? '',
      points: points,
      stops: stops,
      buses: pathBuses,
    );
  }

  /// Tek bir durağın **tam kartı**: o duraktan geçen tüm hatlar + yaklaşan
  /// canlı otobüsler. Tek istekte gelir, bu yüzden durak dokunuşu hızlıdır.
  static Future<KentkartStopDetail> fetchStopDetail({
    required String stopId,
    required double lat,
    required double lng,
  }) async {
    final body = await _get(
      endpointNearestBus,
      query: {
        'lat': lat.toStringAsFixed(6),
        'lng': lng.toStringAsFixed(6),
        'busStopId': stopId,
      },
      requiredKeys: _nearestBusKeys,
      listKeys: const {'busList', 'routeList'},
    );

    final info = body['stopInfo'];
    final name = info is Map ? info['busStopName']?.toString() : null;

    final routes = <KentkartStopRoute>[];
    for (final r in (body['routeList'] as List? ?? const [])) {
      if (r is! Map) continue;
      final code = r['displayRouteCode']?.toString();
      if (code == null || code.isEmpty) continue;
      routes.add(KentkartStopRoute(
        displayCode: code,
        name: r['name']?.toString() ?? code,
        headSign: r['headSign']?.toString() ?? '',
        colorHex: r['routeColor']?.toString() ?? '1D4ED8',
        direction: int.tryParse(r['direction']?.toString() ?? '') ?? 0,
      ));
    }

    return KentkartStopDetail(
      stopId: stopId,
      name: (name == null || name.isEmpty) ? 'Durak $stopId' : name,
      lat: lat,
      lng: lng,
      routes: routes,
      buses: _parseBuses(body),
    );
  }

  /// Bir durağın yakınındaki **canlı** otobüsler (konum + kaç durak uzakta).
  static Future<List<KentkartLiveBus>> fetchLiveBuses({
    required double lat,
    required double lng,
    required String stopId,
  }) async {
    final detail = await fetchStopDetail(stopId: stopId, lat: lat, lng: lng);
    return detail.buses;
  }

  static List<KentkartLiveBus> _parseBuses(Map<String, dynamic> body,
      {String? fallbackLineCode, String? fallbackColor}) {
    final buses = <KentkartLiveBus>[];
    for (final b in (body['busList'] as List? ?? const [])) {
      if (b is! Map) continue;
      final blat = double.tryParse(b['lat']?.toString() ?? '');
      final blng = double.tryParse(b['lng']?.toString() ?? '');
      if (blat == null || blng == null) continue;
      // nearest/bus: plate/displayRouteCode/headSign/stopDiff/timeDiff
      // pathInfo:   plateNumber/busLabel (headSign yok), stopDiff/timeDiff yok
      final plate =
          (b['plate'] ?? b['plateNumber'])?.toString() ?? '';
      final lineCode = (b['displayRouteCode']?.toString().isNotEmpty == true
              ? b['displayRouteCode']?.toString()
              : null) ??
          fallbackLineCode ??
          '';
      final head = (b['headSign'] ?? b['busLabel'] ?? b['displayName'])
              ?.toString() ??
          '';
      final color = (b['routeColor']?.toString().isNotEmpty == true
              ? b['routeColor']?.toString()
              : null) ??
          fallbackColor ??
          '1D4ED8';
      buses.add(KentkartLiveBus(
        busId: b['busId']?.toString() ?? '',
        plate: plate,
        lineCode: lineCode,
        headSign: head,
        lat: blat,
        lng: blng,
        stopsAway: int.tryParse(b['stopDiff']?.toString() ?? '') ?? 0,
        minutesAway: int.tryParse(b['timeDiff']?.toString() ?? '') ?? 0,
        colorHex: color,
      ));
    }
    buses.sort((a, b) => a.stopsAway.compareTo(b.stopsAway));
    return buses;
  }

  /// Tüm hatların güzergâh duraklarının birleşimi (≈390 durak).
  ///
  /// `/nearest/find` yalnızca 50 durak döndürür; gerçek kent içi durak
  /// ağı her hattın `pathInfo` yanıtındaki `busStopList` alanlarında saklıdır.
  /// Hatalı tekil hatlar atlanır; hiçbiri çekilemezse boş liste döner
  /// (çağıran kataloğa düşer).
  static Future<List<KentkartStop>> fetchAllStops(
      {List<String>? lineCodes}) async {
    List<String> codes = lineCodes ?? [];
    if (codes.isEmpty) {
      final catalog = await fetchCatalog();
      codes = catalog.routes.map((r) => r.displayCode).toList();
    }
    final Map<String, KentkartRoute> colorByCode = {};
    try {
      final catalog = await fetchCatalog();
      for (final r in catalog.routes) {
        colorByCode[r.displayCode] = r;
      }
    } catch (_) {
      // renkler olmadan da devam
    }
    final Map<String, KentkartStop> merged = {};
    final futures = <Future<KentkartPath?>>[];
    for (final code in codes) {
      for (var dir = 0; dir <= 1; dir++) {
        futures.add(fetchPath(code, direction: dir, resultType: '001000')
            .then<KentkartPath?>((p) => p)
            .catchError((_) => null));
      }
    }
    final paths = await Future.wait(futures);
    for (final p in paths) {
      if (p == null) continue;
      for (final s in p.stops) {
        final prev = merged[s.stopId];
        if (prev == null) {
          merged[s.stopId] = s;
        } else {
          final union = <String>{...prev.routes, ...s.routes}.toList()
            ..sort();
          merged[s.stopId] = KentkartStop(
            stopId: prev.stopId,
            name: prev.name,
            lat: prev.lat,
            lng: prev.lng,
            routes: union,
          );
        }
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Kent genelindeki **tüm canlı araçlar** (tüm hatlar, iki yön).
  ///
  /// Her hattın `pathInfo` yanıtı kendi `busList` alanını taşır; bu liste
  /// `nearest/bus` biçiminden farklıdır (plateNumber/busLabel). Araçlar
  /// `busId` ile tekilleştirilir.
  static Future<List<KentkartLiveBus>> fetchAllLiveBuses(
      {List<String>? lineCodes}) async {
    List<String> codes = lineCodes ?? [];
    Map<String, String> colorByCode = {};
    if (codes.isEmpty) {
      try {
        final catalog = await fetchCatalog();
        codes = catalog.routes.map((r) => r.displayCode).toList();
        for (final r in catalog.routes) {
          colorByCode[r.displayCode] = r.colorHex;
        }
      } catch (_) {
        return [];
      }
    }
    final futures = <Future<List<KentkartLiveBus>>>[];
    for (final code in codes) {
      for (var dir = 0; dir <= 1; dir++) {
        futures.add(_fetchPathBuses(code, dir,
            fallbackColor: colorByCode[code] ?? '1D4ED8'));
      }
    }
    final chunks = await Future.wait(futures);
    final Map<String, KentkartLiveBus> merged = {};
    for (final chunk in chunks) {
      for (final b in chunk) {
        if (b.busId.isEmpty) continue;
        merged.putIfAbsent(b.busId, () => b);
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) => a.lineCode.compareTo(b.lineCode));
    return list;
  }

  static Future<List<KentkartLiveBus>> _fetchPathBuses(
      String displayRouteCode, int direction,
      {String fallbackColor = '1D4ED8'}) async {
    try {
      // 010000 = yalnızca canlı araçlar (~1 KB); polyline/durak çekilmez.
      final path = await fetchPath(displayRouteCode,
          direction: direction, resultType: '010000');
      if (fallbackColor != '1D4ED8') {
        return path.buses
            .map((b) => KentkartLiveBus(
                  busId: b.busId,
                  plate: b.plate,
                  lineCode: b.lineCode,
                  headSign: b.headSign,
                  lat: b.lat,
                  lng: b.lng,
                  stopsAway: b.stopsAway,
                  minutesAway: b.minutesAway,
                  colorHex: b.colorHex == '1D4ED8'
                      ? fallbackColor
                      : b.colorHex,
                ))
            .toList();
      }
      return path.buses;
    } catch (_) {
      return const <KentkartLiveBus>[];
    }
  }
}

/// Kentkart servis çağrılarındaki hatalar.
class KentkartException implements Exception {
  final String message;
  final KentkartIssueKind kind;
  final int? statusCode;
  final Object? cause;

  const KentkartException(
    this.message, {
    this.kind = KentkartIssueKind.payload,
    this.statusCode,
    this.cause,
  });

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

  /// Bu duraktan geçen hat kodları (pathInfo `routes` CSV alanından).
  /// Katalog duraklarında boş olabilir.
  final List<String> routes;
  const KentkartStop({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lng,
    this.routes = const [],
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

  /// Bu hatta şu an seferde olan canlı araçlar (pathInfo `busList`).
  final List<KentkartLiveBus> buses;
  const KentkartPath({
    required this.displayCode,
    required this.headSign,
    required this.points,
    required this.stops,
    this.buses = const [],
  });
}

/// Bir duraktan geçen hattın tek yönü.
class KentkartStopRoute {
  final String displayCode;
  final String name;
  final String headSign;
  final String colorHex;
  final int direction;

  const KentkartStopRoute({
    required this.displayCode,
    required this.name,
    required this.headSign,
    required this.colorHex,
    required this.direction,
  });

  /// Aynı hattın 0/1 yönleri tek başlıkta toplanır.
  String get groupKey => displayCode;
}

/// Aynı hat kodunun durakta duran yönleri (0 = gidiş, 1 = dönüş).
class KentkartStopLine {
  final String code;
  final String colorHex;
  final List<String> headSigns;

  const KentkartStopLine({
    required this.code,
    required this.colorHex,
    required this.headSigns,
  });
}

/// Bir durağın tüm bilgisi: hatlar + yaklaşan canlı otobüsler.
class KentkartStopDetail {
  final String stopId;
  final String name;
  final double lat;
  final double lng;
  final List<KentkartStopRoute> routes;
  final List<KentkartLiveBus> buses;

  const KentkartStopDetail({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.routes,
    required this.buses,
  });

  /// Hat koduna göre gruplanmış hatlar (yönler tek kayıtta birleşir).
  List<KentkartStopLine> get lines {
    final grouped = <String, List<KentkartStopRoute>>{};
    for (final r in routes) {
      grouped.putIfAbsent(r.groupKey, () => []).add(r);
    }
    final result = <KentkartStopLine>[];
    for (final entry in grouped.entries) {
      final heads = <String>[];
      for (final r in entry.value) {
        final label = r.headSign.isNotEmpty ? r.headSign : r.name;
        if (label.isNotEmpty && !heads.contains(label)) heads.add(label);
      }
      result.add(KentkartStopLine(
        code: entry.key,
        colorHex: entry.value.first.colorHex,
        headSigns: heads,
      ));
    }
    result.sort((a, b) => a.code.compareTo(b.code));
    return result;
  }
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
