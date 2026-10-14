import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:etus_mobile/services/geocoding_service.dart';

const String _nominatimBody = '''
[
  {"place_id": 1, "lat": "41.67890", "lon": "26.55900",
   "display_name": "Meriç Köprüsü, Edirne, Türkiye",
   "type": "bridge", "class": "route",
   "address": {"road": "Meriç Köprüsü", "city": "Edirne"}},
  {"place_id": 2, "lat": "41.64000", "lon": "26.62000",
   "display_name": "Istanbul, Türkiye",
   "type": "city", "class": "place",
   "address": {"city": "Istanbul"}}
]
''';

void main() {
  final original = GeocodingService.client;
  tearDown(() => GeocodingService.client = original);

  test('gerçek yerler koordinatıyla döner, Edirne önce gelir', () async {
    GeocodingService.client = MockClient((req) async {
      expect(req.url.host, 'nominatim.openstreetmap.org');
      expect(req.url.queryParameters['countrycodes'], 'tr');
      return http.Response(_nominatimBody, 200,
          headers: {'content-type': 'application/json'});
    });

    final res = await GeocodingService.search('meric koprusu');
    expect(res.length, 2);
    expect(res.first.name, contains('Meriç Köprüsü'));
    expect(res.first.lat, closeTo(41.6789, 1e-4));
    // Edirne içi sonuç başa alınır.
    expect(res.first.lat, greaterThan(41.4));
  });

  test('HTTP hatası istisna üretir (sessiz sahte sonuç yok)', () async {
    GeocodingService.client =
        MockClient((_) async => http.Response('hata', 500));
    expect(() => GeocodingService.search('xyz'),
        throwsA(isA<GeocodingException>()));
  });

  test('boş sorgu ağa çıkmadan boş döner', () async {
    var called = false;
    GeocodingService.client = MockClient((_) async {
      called = true;
      return http.Response('[]', 200);
    });
    final res = await GeocodingService.search('   ');
    expect(res, isEmpty);
    expect(called, isFalse);
  });
}
