import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenStreetMap Nominatim ile gerçek yer araması (API anahtarsız).
///
/// SmartSearchService yalnızca yerleşik durak adlarını bilir; kullanıcı
/// "Tarihi köprü", rastgele bir sokak veya mahalle yazdığında sahte eşleşme
/// üretmek yerine bu servis gerçek koordinatı döndürür. Sonuçlar Edirne
/// sınırlayıcı kutusuna öncelik verir ama kutu dışı sonuçlara da izin verir
/// (kullanıcı şehir dışını ararsa boş liste yerine gerçek sonuç gösterilir).
class GeocodingService {
  static http.Client client = http.Client();

  static const String _base = 'https://nominatim.openstreetmap.org/search';

  /// Edirne sınırlayıcı kutu: sol, üst, sağ, alt (lon,lat).
  static const String _edirneViewBox = '26.2,41.9,27.0,41.4';

  static Future<List<GeocodedPlace>> search(String query,
      {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse(_base).replace(queryParameters: {
      'format': 'jsonv2',
      'q': q,
      'limit': '$limit',
      'countrycodes': 'tr',
      'accept-language': 'tr',
      'addressdetails': '1',
      'viewbox': _edirneViewBox,
      'bounded': '0',
    });
    final res = await client.get(uri, headers: {
      'Accept': 'application/json',
      // Nominatim politikası geçerli bir User-Agent ister.
      'User-Agent': 'ETUS-Asistani/1.4 (Edirne toplu tasima)',
    }).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw GeocodingException('Yer araması başarısız (HTTP ${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) return [];
    final out = <GeocodedPlace>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lon == null) continue;
      final name = item['display_name']?.toString() ?? q;
      out.add(GeocodedPlace(
        name: _shortName(item, fallback: name),
        fullName: name,
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
