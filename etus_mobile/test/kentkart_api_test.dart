import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:etus_mobile/services/kentkart_api.dart';
import 'package:etus_mobile/services/kentkart_health.dart';

/// Bu testler Kentkart servisinden **gerçekten alınmış** yanıt gövdelerini
/// (2026-10-14, region=013, durak 20001 "Otogar") kullanır. Böylece ayrıştırma
/// mantığı ağa çıkmadan, gerçek alan adlarıyla doğrulanır.
const String _otogarBody = '''
{
  "result": {"cmd": "/web/nearest/bus", "code": 0, "message": "OK",
             "dateTime": "20261014003839", "debugTimeDiff": "", "authType": ""},
  "stopInfo": {"busStopid": "20001", "busStopName": "Otogar",
               "lat": "41.632311", "lng": "26.6195089"},
  "busList": [],
  "routeList": [
    {"routeCode": "22001", "displayRouteCode": "1T", "name": "GAZİMİHAL - OTOGAR",
     "headSign": "GAZİMİHAL - OTOGAR", "routeColor": "EBE10E", "direction": "0"},
    {"routeCode": "22001", "displayRouteCode": "1T", "name": "OTOGAR - GAZİMİHAL",
     "headSign": "OTOGAR - GAZİMİHAL", "routeColor": "EBE10E", "direction": "1"},
    {"routeCode": "22002", "displayRouteCode": "2A", "name": "PAZARTESİ PAZARI - OTOGAR",
     "headSign": "PAZARTESİ PAZARI - OTOGAR", "routeColor": "FF14B3", "direction": "0"},
    {"routeCode": "22002", "displayRouteCode": "2A", "name": "OTOGAR - PAZARTESİ PAZARI",
     "headSign": "OTOGAR - PAZARTESİ PAZARI", "routeColor": "FF14B3", "direction": "1"}
  ]
}
''';

/// Canlı otobüs alanları gerçek yanıttaki adlarla aynıdır
/// (busId, plate, displayRouteCode, headSign, lat, lng, stopDiff, timeDiff).
const String _withBusesBody = '''
{
  "result": {"cmd": "/web/nearest/bus", "code": 0, "message": "OK"},
  "stopInfo": {"busStopid": "20210", "busStopName": "Gazimihal",
               "lat": "41.6765808", "lng": "26.5460646"},
  "busList": [
    {"busId": "1234", "plate": "22 AB 123", "displayRouteCode": "1A",
     "headSign": "SERA KENT", "lat": "41.6770", "lng": "26.5480",
     "stopDiff": "4", "timeDiff": "9", "routeColor": "EBE10E"},
    {"busId": "5678", "plate": "22 CD 456", "displayRouteCode": "3",
     "headSign": "OTOGAR", "lat": "41.6760", "lng": "26.5470",
     "stopDiff": "1", "timeDiff": "3", "routeColor": "1B610B"}
  ],
  "routeList": [
    {"routeCode": "22011", "displayRouteCode": "1A", "name": "GAZİMİHAL-SERAKENT",
     "headSign": "GAZİMİHAL - SERA KENT", "routeColor": "EBE10E", "direction": "0"}
  ]
}
''';

http.Response _json(String body) => http.Response(body, 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final originalClient = KentkartApi.client;

  setUp(() => KentkartHealth.instance.reset());
  tearDown(() => KentkartApi.client = originalClient);

  group('fetchStopDetail — gerçek yanıt', () {
    test('durak adı, hatlar ve yönler doğru ayrıştırılır', () async {
      KentkartApi.client =
          MockClient((_) async => _json(_otogarBody));

      final detail = await KentkartApi.fetchStopDetail(
        stopId: '20001',
        lat: 41.632311,
        lng: 26.6195089,
      );

      expect(detail.name, 'Otogar');
      expect(detail.stopId, '20001');
      expect(detail.routes.length, 4, reason: 'iki hat × iki yön');

      // Aynı hattın iki yönü tek kayıtta toplanmalı
      expect(detail.lines.length, 2);
      final codes = detail.lines.map((l) => l.code).toList();
      expect(codes, ['1T', '2A']);

      final first = detail.lines.firstWhere((l) => l.code == '1T');
      expect(first.headSigns.length, 2);
      expect(first.headSigns, contains('GAZİMİHAL - OTOGAR'));
      expect(first.headSigns, contains('OTOGAR - GAZİMİHAL'));
      expect(first.colorHex, 'EBE10E');

      // Otobüs yoksa boş liste (gece saatleri) — çökmemeli
      expect(detail.buses, isEmpty);

      expect(KentkartHealth.instance.status, KentkartStatus.ok);
      expect(KentkartHealth.instance.hasSchemaDrift, isFalse);
    });

    test('canlı otobüsler yakınlığa göre sıralanır', () async {
      KentkartApi.client = MockClient((_) async => _json(_withBusesBody));

      final detail = await KentkartApi.fetchStopDetail(
        stopId: '20210',
        lat: 41.6765808,
        lng: 26.5460646,
      );

      expect(detail.name, 'Gazimihal');
      expect(detail.buses.length, 2);
      // 1 durak uzaktaki otobüs ilk sırada
      expect(detail.buses.first.lineCode, '3');
      expect(detail.buses.first.stopsAway, 1);
      expect(detail.buses.first.minutesAway, 3);
      expect(detail.buses.first.plate, '22 CD 456');
      expect(detail.buses.last.lineCode, '1A');
      expect(detail.buses.last.minutesAway, 9);
    });

    test('istek region=013 ve busStopId ile yapılır', () async {
      Uri? seen;
      KentkartApi.client = MockClient((request) async {
        seen = request.url;
        return _json(_otogarBody);
      });

      await KentkartApi.fetchStopDetail(
        stopId: '20001',
        lat: 41.632311,
        lng: 26.6195089,
      );

      expect(seen!.host, 'service.kentkart.com');
      expect(seen!.path, '/rl1/web/nearest/bus');
      expect(seen!.queryParameters['region'], '013');
      expect(seen!.queryParameters['busStopId'], '20001');
      expect(seen!.queryParameters['lat'], '41.632311');
    });

    test('fetchLiveBuses aynı uçtan yalnızca otobüsleri döndürür', () async {
      KentkartApi.client = MockClient((_) async => _json(_withBusesBody));

      final buses = await KentkartApi.fetchLiveBuses(
        stopId: '20210',
        lat: 41.6765808,
        lng: 26.5460646,
      );

      expect(buses.length, 2);
      expect(buses.first.lineCode, '3');
    });
  });

  group('Şema kayması ve hatalar', () {
    test('routeList kaybolursa sağlık durumu degraded olur ve veri yine döner', () async {
      KentkartApi.client = MockClient((_) async => _json('''
        {
          "result": {"cmd": "/web/nearest/bus", "code": 0, "message": "OK"},
          "stopInfo": {"busStopid": "20001", "busStopName": "Otogar"},
          "busList": []
        }
      '''));

      final detail = await KentkartApi.fetchStopDetail(
        stopId: '20001',
        lat: 41.632311,
        lng: 26.6195089,
      );

      // Ayrıştırma çökmemeli
      expect(detail.lines, isEmpty);
      expect(detail.name, 'Otogar');

      // Ama sorun sessizce yutulmamalı
      final health = KentkartHealth.instance;
      expect(health.hasSchemaDrift, isTrue);
      expect(health.status, KentkartStatus.degraded);
      expect(health.liveDataAvailable, isFalse);
      expect(health.userMessage, contains('routeList'));
    });

    test('HTTP 500 KentkartException ve down durumu üretir', () async {
      KentkartApi.client = MockClient((_) async => http.Response('boom', 500));

      await expectLater(
        KentkartApi.fetchStopDetail(stopId: '1', lat: 41.0, lng: 26.0),
        throwsA(isA<KentkartException>()
            .having((e) => e.kind, 'kind', KentkartIssueKind.http)
            .having((e) => e.statusCode, 'statusCode', 500)),
      );

      expect(KentkartHealth.instance.status, KentkartStatus.down);
    });

    test('result.code != 0 servis hatası olarak raporlanır', () async {
      KentkartApi.client = MockClient((_) async => _json('''
        {"result": {"code": 5, "message": "Sistem hatası"}, "busList": [], "routeList": []}
      '''));

      await expectLater(
        KentkartApi.fetchStopDetail(stopId: '1', lat: 41.0, lng: 26.0),
        throwsA(isA<KentkartException>()
            .having((e) => e.kind, 'kind', KentkartIssueKind.apiError)),
      );

      final health = KentkartHealth.instance;
      expect(health.issues.first.message, contains('Sistem hatası'));
    });

    test('JSON olmayan yanıt payload hatası olarak raporlanır', () async {
      // Gerçek hayatta servis bazen JSON yerine bakım sayfası döndürür.
      KentkartApi.client = MockClient(
          (_) async => http.Response('<html><body>Maintenance</body></html>', 200));

      await expectLater(
        KentkartApi.fetchStopDetail(stopId: '1', lat: 41.0, lng: 26.0),
        throwsA(isA<KentkartException>()
            .having((e) => e.kind, 'kind', KentkartIssueKind.payload)),
      );

      expect(
        KentkartHealth.instance.issues.first.kind,
        KentkartIssueKind.payload,
      );
    });

    test('başarılı istek önceki hata kaydını temizler', () async {
      KentkartApi.client = MockClient((_) async => http.Response('boom', 503));
      await expectLater(
        KentkartApi.fetchStopDetail(stopId: '1', lat: 41.0, lng: 26.0),
        throwsA(isA<KentkartException>()),
      );
      expect(KentkartHealth.instance.status, KentkartStatus.down);

      KentkartApi.client = MockClient((_) async => _json(_otogarBody));
      await KentkartApi.fetchStopDetail(
        stopId: '20001',
        lat: 41.632311,
        lng: 26.6195089,
      );

      final health = KentkartHealth.instance;
      expect(health.status, KentkartStatus.ok);
      expect(health.issues, isEmpty);
      expect(health.consecutiveFailures, 0);
      expect(health.lastSuccessAt, isNotNull);
    });
  });

  group('fetchCatalog', () {
    test('hatlar ve duraklar ayrıştırılır', () async {
      KentkartApi.client = MockClient((_) async => _json('''
        {
          "result": {"code": 0, "message": "OK"},
          "routeList": [
            {"routeCode": "22011", "displayRouteCode": "1A",
             "name": "GAZİMİHAL-SERAKENT", "routeColor": "EBE10E",
             "agencyName": "Edirne Serhat Birlik Koop"}
          ],
          "stopList": [
            {"stopId": "20001", "name": "Otogar",
             "lat": "41.632311", "lng": "26.6195089"}
          ]
        }
      '''));

      final catalog = await KentkartApi.fetchCatalog();

      expect(catalog.routes.length, 1);
      expect(catalog.routes.first.displayCode, '1A');
      expect(catalog.stops.length, 1);
      expect(catalog.stops.first.name, 'Otogar');
      expect(catalog.stops.first.lat, closeTo(41.632311, 1e-6));
    });

    test('hat kodu olmayan kayıtlar atlanır', () async {
      KentkartApi.client = MockClient((_) async => _json('''
        {
          "result": {"code": 0, "message": "OK"},
          "routeList": [{"routeCode": "1"}, {"displayRouteCode": "3A"}],
          "stopList": [{"stopId": "1", "name": "X", "lat": "41", "lng": "26"}]
        }
      '''));

      final catalog = await KentkartApi.fetchCatalog();
      expect(catalog.routes.map((r) => r.displayCode), ['3A']);
    });
  });
}
