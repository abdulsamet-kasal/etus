import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Gerçek yer araması: **Photon (birincil) + Nominatim (yedek)**.
///
/// Tek kaynakla bazı yerler bulunamıyordu (sınırlayıcı kutu / indeks farkı).
/// Photon konum yanlı (Edirne merkez) arama yapar ve POI kapsamı geniştir;
/// Nominatim eksikleri kapatır. Sonuçlar 150 m içinde tekilleştirilir.
/// Sahte sonuç üretilmez: iki kaynak da boşsa boş liste döner.
class GeocodingService {
  static http.Client client = http.Client();

  static const double _edirneLat = 41.6752;
  static const double _edirneLng = 26.5548;

  static const String _photonBase = 'https://photon.komoot.io/api/';
  static const String _nominatimBase =
      'https://nominatim.openstreetmap.org/search';
  static const String _photonReverse = 'https://photon.komoot.io/reverse';

  static Map<String, String> get _headers => const {
        'Accept': 'application/json',
        'User-Agent': 'ETUS-Asistani/1.5 (Edirne toplu tasima)',
      };

  /// Birleştirilmiş yer araması (en fazla [limit] sonuç).
  static Future<List<GeocodedPlace>> search(String query,
      {int limit = 10}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // İki kaynak paralel sorgulanır; biri çökerse diğeri yine döner.
    final results = await Future.wait([
      _searchPhoton(q).catchError((_) => <GeocodedPlace>[]),
      _searchNominatim(q).catchError((_) => <GeocodedPlace>[]),
    ]);
    final photon = results[0];
    final nominatim = results[1];

    final merged = <GeocodedPlace>[...photon];
    for (final p in nominatim) {
      final dup = merged.any((m) =>
          _meters(m.lat, m.lng, p.lat, p.lng) < 150 &&
          _nameSimilar(m.name, p.name));
      if (!dup) merged.add(p);
    }
    return merged.take(limit).toList();
  }

  /// Haritada dokunulan noktanın adres karşılığı (kalkış/varış etiketi için).
  /// Bulunamazsa null döner; çağıran genel etikete düşer.
  static Future<String?> reverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(_photonReverse).replace(queryParameters: {
        'lat': '$lat',
        'lon': '$lng',
        'limit': '1',
      });
      final res = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      final feats = decoded['features'];
      if (feats is! List || feats.isEmpty) return null;
      final props = feats.first['properties'];
      if (props is! Map) return null;
      return _photonTitle(props, fallback: null);
    } catch (_) {
      return null;
    }
  }

  static Future<List<GeocodedPlace>> _searchPhoton(String q) async {
    final uri = Uri.parse(_photonBase).replace(queryParameters: {
      'q': q,
      'lat': '$_edirneLat',
      'lon': '$_edirneLng',
      'limit': '8',
    });
    final res = await client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw GeocodingException(
          'Photon araması başarısız (HTTP ${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return [];
    final feats = decoded['features'];
    if (feats is! List) return [];
    final out = <GeocodedPlace>[];
    for (final f in feats) {
      if (f is! Map) continue;
      final geom = f['geometry'];
      final props = f['properties'];
      if (geom is! Map || props is! Map) continue;
      if (geom['type'] != 'Point') continue;
      final coords = geom['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final title = _photonTitle(props, fallback: q);
      if (title == null) continue;
      out.add(GeocodedPlace(
        name: title,
        fullName: _photonSubtitle(props, fallback: title),
        lat: lat,
        lng: lng,
        type: props['osm_value']?.toString() ?? '',
        category: props['osm_key']?.toString() ?? '',
      ));
    }
    return out;
  }

  static String? _photonTitle(Map props, {String? fallback}) {
    final name = props['name']?.toString();
    final street = props['street']?.toString();
    final district =
        props['district']?.toString() ?? props['suburb']?.toString();
    final city = props['city']?.toString() ?? props['county']?.toString();
    if (name != null && name.isNotEmpty) {
      if (city != null && city.isNotEmpty && !name.contains(city)) {
        return '$name, $city';
      }
      return name;
    }
    if (street != null && street.isNotEmpty) {
      final tail = district ?? city ?? '';
      return tail.isEmpty ? street : '$street, $tail';
    }
    return fallback;
  }

  static String _photonSubtitle(Map props, {required String fallback}) {
    final parts = <String>[
      for (final k in ['street', 'district', 'city', 'state', 'country'])
        if ((props[k]?.toString().isNotEmpty ?? false))
          props[k].toString(),
    ];
    final name = props['name']?.toString() ?? '';
    final rest = parts.where((p) => p != name).join(', ');
    if (name.isEmpty) return rest.isEmpty ? fallback : rest;
    return rest.isEmpty ? name : '$name — $rest';
  }

  static Future<List<GeocodedPlace>> _searchNominatim(String q) async {
    final uri = Uri.parse(_nominatimBase).replace(queryParameters: {
      'format': 'jsonv2',
      'q': q,
      'limit': '6',
      'countrycodes': 'tr',
      'accept-language': 'tr',
      'addressdetails': '1',
      'viewbox': '26.2,41.9,27.0,41.4',
      'bounded': '0',
    });
    final res = await client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw GeocodingException(
          'Yer araması başarısız (HTTP ${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) return [];
    final out = <GeocodedPlace>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lon == null) continue;
      final full = item['display_name']?.toString() ?? q;
      out.add(GeocodedPlace(
        name: _shortName(item, fallback: full),
        fullName: full,
        lat: lat,
        lng: lon,
        type: item['type']?.toString() ?? '',
        category: item['class']?.toString() ?? '',
      ));
    }
    // Edirne içi sonuçlar önce gelsin.
    out.sort((a, b) {
      final ai = _inEdirne(a) ? 0 : 1;
      final bi = _inEdirne(b) ? 0 : 1;
      return ai.compareTo(bi);
    });
    return out;
  }

  static String _shortName(Map item, {required String fallback}) {
    final addr = item['address'];
    if (addr is Map) {
      for (final k in [
        'amenity',
        'shop',
        'tourism',
        'leisure',
        'road',
        'suburb',
        'neighbourhood',
        'village',
        'town'
      ]) {
        final v = addr[k]?.toString();
        if (v != null && v.isNotEmpty) {
          final city = addr['city'] ?? addr['town'] ?? addr['county'] ?? '';
          return city.toString().isEmpty ? v : '$v, $city';
        }
      }
      final road = addr['road']?.toString() ?? '';
      final num = addr['house_number']?.toString() ?? '';
      if (road.isNotEmpty) {
        return num.isNotEmpty ? '$road $num' : road;
      }
    }
    final named = item['namedetails'] is Map
        ? (item['namedetails'] as Map)['name']?.toString()
        : null;
    if (named != null && named.isNotEmpty) return named;
    if (fallback.length > 90) return '${fallback.substring(0, 90)}…';
    return fallback;
  }

  static bool _inEdirne(GeocodedPlace p) =>
      p.lat >= 41.4 && p.lat <= 41.9 && p.lng >= 26.2 && p.lng <= 27.0;

  static double _meters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * r * asin(sqrt(a));
  }

  static bool _nameSimilar(String a, String b) {
    final na = a.toLowerCase(), nb = b.toLowerCase();
    if (na.isEmpty || nb.isEmpty) return false;
    return na.contains(nb) ||
        nb.contains(na) ||
        na.split(RegExp(r'\s+')).first ==
            nb.split(RegExp(r'\s+')).first;
  }
}

class GeocodedPlace {
  final String name;
  final String fullName;
  final double lat;
  final double lng;
  final String type;
  final String category;

  const GeocodedPlace({
    required this.name,
    required this.fullName,
    required this.lat,
    required this.lng,
    required this.type,
    required this.category,
  });
}

class GeocodingException implements Exception {
  final String message;
  const GeocodingException(this.message);

  @override
  String toString() => 'GeocodingException: $message';
}
