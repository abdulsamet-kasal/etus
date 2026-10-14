import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:etus_mobile/screens/map_screen.dart';
import 'package:etus_mobile/services/kentkart_api.dart';
import 'package:etus_mobile/services/kentkart_health.dart';

/// Gerçek katalog yanıtından alınan iki durak. Gazimihal harita merkezine
/// (41.6752, 26.5548) ~700 m uzakta olduğu için görünür alanda kalır;
/// flutter_map görünür alan dışındaki işaretçileri çizmez.
const String _catalogBody = '''
{
  "result": {"cmd": "/web/nearest/find", "code": 0, "message": "OK"},
  "routeList": [
    {"routeCode": "22011", "displayRouteCode": "1A", "name": "GAZİMİHAL-SERAKENT",
     "routeColor": "EBE10E", "agencyName": "Edirne Serhat Birlik Koop"}
  ],
  "stopList": [
    {"stopId": "20210", "name": "Gazimihal", "lat": "41.6765808", "lng": "26.5460646"},
    {"stopId": "20001", "name": "Otogar", "lat": "41.632311", "lng": "26.6195089"}
  ]
}
''';

const String _stopDetailBody = '''
{
  "result": {"cmd": "/web/nearest/bus", "code": 0, "message": "OK"},
  "stopInfo": {"busStopid": "20210", "busStopName": "Gazimihal",
               "lat": "41.6765808", "lng": "26.5460646"},
  "busList": [
    {"busId": "1", "plate": "22 AB 123", "displayRouteCode": "1A",
     "headSign": "SERA KENT", "lat": "41.6770", "lng": "26.5480",
     "stopDiff": "2", "timeDiff": "6", "routeColor": "EBE10E"}
  ],
  "routeList": [
    {"routeCode": "22011", "displayRouteCode": "1A", "name": "GAZİMİHAL-SERAKENT",
     "headSign": "GAZİMİHAL - SERA KENT", "routeColor": "EBE10E", "direction": "0"}
  ]
}
''';

/// pathInfo her zaman `pathList` içerir (gerçek serviste olduğu gibi);
/// boş liste sorun değil, önemli olan şema kayması üretilmemesi.
const String _emptyPathBody = '''
{
  "result": {"cmd": "/web/pathInfo", "code": 0, "message": "OK"},
  "pathList": [
    {"headSign": "X", "displayRouteCode": "1A", "direction": "0",
     "pointList": [], "busStopList": [], "busList": []}
  ]
}
''';

void main() {
  final originalClient = KentkartApi.client;

  setUp(() => KentkartHealth.instance.reset());
  tearDown(() => KentkartApi.client = originalClient);

  Future<void> pumpMap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: MapScreen(initialLat: 41.6752, initialLng: 26.5548),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('harita tüm durakları gösterir ve dokununca detay açar',
      (tester) async {
    KentkartApi.client = MockClient((req) async => http.Response(
          req.url.path.endsWith('/nearest/find')
              ? _catalogBody
              : (req.url.path.endsWith('/pathInfo')
                  ? _emptyPathBody
                  : _stopDetailBody),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));

    await pumpMap(tester);

    // Alt durum satırı: katalogdan gelen durak sayısı
    expect(find.textContaining('2 durak'), findsOneWidget);
    expect(find.text('Edirne Ulaşım'), findsOneWidget);
    expect(
      find.byTooltip('Gazimihal\nDokun: hatlar ve canlı otobüsler'),
      findsOneWidget,
    );

    // Durağa dokun → o duraktan geçen hatlar ve canlı otobüsler açılır
    await tester.tap(
      find.byTooltip('Gazimihal\nDokun: hatlar ve canlı otobüsler'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('BU DURAKTAN GEÇEN HATLAR'), findsOneWidget);
    expect(find.text('1A'), findsWidgets);
    expect(find.text('YAKLAŞAN CANLI OTOBÜSLER'), findsOneWidget);
    expect(find.text('6 dk'), findsOneWidget);
    expect(find.textContaining('SERA KENT'), findsWidgets);

    // Zamanlayıcıları kapat (pending timer uyarısı olmasın)
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('canlı veri alınamazsa harita yine açılır ve uyarı gösterir',
      (tester) async {
    KentkartApi.client = MockClient((_) async => http.Response('bakim', 503));

    await pumpMap(tester);

    expect(find.text('Edirne Ulaşım'), findsOneWidget);
    expect(find.text('Canlı veri: erişilemiyor'), findsOneWidget);
    expect(
      find.textContaining('Canlı durak listesi alınamadı'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
