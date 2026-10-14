import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:etus_mobile/services/geocoding_service.dart';

/// Photon birincil, Nominatim yedek kaynaktır.
const String _photonBody = '''
{
  "features": [
    {"geometry": {"type": "Point", "coordinates": [26.55212, 41.663416]},
     "properties": {"name": "Meriç Köprüsü", "city": "Edirne",
                    "osm_key": "bridge", "osm_value": "bridge"}},
    {"geometry": {"type": "Point", "coordinates": [26.57096, 41.66631]},
     "properties": {"name": "Erasta Edirne Alışveriş Merkezi", "city": "Edirne",
                    "osm_key": "shop", "osm_value": "mall"}}
  ]
}
''';

const String _nominatimBody = '''
[
  {"place_id": 1, "lat": "41.663416", "lon": "26.55212",
   "display_name": "Meriç Köprüsü, Edirne, Türkiye",
   "type": "bridge", "class": "route",
   "address": {"road": "Meriç Köprüsü", "city": "Edirne"}},
  {"place_id": 2, "lat": "41.67890", "lon": "26.55900",
   "display_name": "Selimiye Camii, Edirne, Türkiye",
   "type": "place_of_worship", "class": "amenity",
   "address": {"amenity": "Selimiye Camii", "city": "Edirne"}}
]
''';

MockClient dualMock() => MockClient((req) async {
      if (req.url.host == 'photon.komoot.io' &&
          !req.url.path.contains('reverse')) {
        return http.Response(_photonBody, 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(_nominatimBody, 200,
          headers: {'content-type': 'application/json'});
    });

void main() {
  final original = GeocodingService.client;
  tearDown(() => GeocodingService.client = original);

  test('iki kaynak birleşir, yakın tekrarlar tekilleştirilir', () async {
    GeocodingService.client = dualMock();

    final res = await GeocodingService.search('kopru');
    // Photon 2 + Nominatim 2, Meriç Köprüsü iki kaynakta da var (~0 m) → 3.
    expect(res.length, 3);
    expect(res.first.name, contains('Meriç Köprüsü'));
    final kopru =
        res.where((p) => p.name.contains('Meriç Köprüsü')).toList();
    expect(kopru.length, 1);
  });

  test('Photon çökerse Nominatim yine sonuç verir', () async {
    GeocodingService.client = MockClient((req) async {
      if (req.url.host == 'photon.komoot.io') {
        return http.Response('hata', 500);
      }
      return http.Response(_nominatimBody, 200,
          headers: {'content-type': 'application/json'});
    });

    final res = await GeocodingService.search('selimiye');
    expect(res, isNotEmpty);
    expect(res.any((p) => p.name.contains('Selimiye')), isTrue);
  });

  test('iki kaynak da çökerse boş liste döner (sahte sonuç yok)',
      () async {
    GeocodingService.client =
        MockClient((_) async => http.Response('hata', 500));
    final res = await GeocodingService.search('xyz');
    expect(res, isEmpty);
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

  test('reverse dokunulan noktanın adını döndürür', () async {
    GeocodingService.client = MockClient((req) async {
      expect(req.url.path, contains('reverse'));
      return http.Response(
          '{"features": [{"properties": {"name": "Saraçlar Caddesi", "city": "Edirne"}}]}',
          200,
          headers: {'content-type': 'application/json'});
    });
    final name = await GeocodingService.reverse(41.6752, 26.5548);
    expect(name, contains('Saraçlar'));
  });

  test('reverse bulunamazsa null döner', () async {
    GeocodingService.client = MockClient(
        (_) async => http.Response('{"features": []}', 200,
            headers: {'content-type': 'application/json'}));
    expect(await GeocodingService.reverse(0, 0), isNull);
  });
}
