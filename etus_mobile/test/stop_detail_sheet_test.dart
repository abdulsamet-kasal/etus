import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:etus_mobile/services/kentkart_api.dart';
import 'package:etus_mobile/services/kentkart_health.dart';
import 'package:etus_mobile/widgets/stop_detail_sheet.dart';

/// Gerçek Kentkart yanıtları (durak 20210 "Gazimihal" ve 20001 "Otogar").
const String _gazimihalBody = '''
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
     "headSign": "GAZİMİHAL - SERA KENT", "routeColor": "EBE10E", "direction": "0"},
    {"routeCode": "22011", "displayRouteCode": "1A", "name": "SERAKENT-GAZİMİHAL",
     "headSign": "SERA KENT - GAZİMİHAL", "routeColor": "EBE10E", "direction": "1"},
    {"routeCode": "22003", "displayRouteCode": "3", "name": "GAZİMİHAL - OTOGAR",
     "headSign": "GAZİMİHAL - OTOGAR", "routeColor": "1B610B", "direction": "0"}
  ]
}
''';

const String _otogarEmptyBusesBody = '''
{
  "result": {"cmd": "/web/nearest/bus", "code": 0, "message": "OK"},
  "stopInfo": {"busStopid": "20001", "busStopName": "Otogar",
               "lat": "41.632311", "lng": "26.6195089"},
  "busList": [],
  "routeList": [
    {"routeCode": "22001", "displayRouteCode": "1T", "name": "GAZİMİHAL - OTOGAR",
     "headSign": "GAZİMİHAL - OTOGAR", "routeColor": "EBE10E", "direction": "0"},
    {"routeCode": "22001", "displayRouteCode": "1T", "name": "OTOGAR - GAZİMİHAL",
     "headSign": "OTOGAR - GAZİMİHAL", "routeColor": "EBE10E", "direction": "1"}
  ]
}
''';

/// routeList alanı kaybolmuş yanıt — servis şeması değişmiş senaryosu.
const String _driftedBody = '''
{
  "result": {"cmd": "/web/nearest/bus", "code": 0, "message": "OK"},
  "stopInfo": {"busStopid": "20001", "busStopName": "Otogar"},
  "busList": []
}
''';

const KentkartStop _gazimihal = KentkartStop(
  stopId: '20210',
  name: 'Gazimihal',
  lat: 41.6765808,
  lng: 26.5460646,
);

const KentkartStop _otogar = KentkartStop(
  stopId: '20001',
  name: 'Otogar',
  lat: 41.632311,
  lng: 26.6195089,
);

void main() {
  final originalClient = KentkartApi.client;

  setUp(() => KentkartHealth.instance.reset());
  tearDown(() => KentkartApi.client = originalClient);

  Future<void> pumpSheet(
    WidgetTester tester, {
    required KentkartStop stop,
    VoidCallback? onSetOrigin,
    VoidCallback? onSetDestination,
    VoidCallback? onNavigate,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StopDetailSheet(
          stop: stop,
          // Testte otomatik yenileme kapalı (bekleyen zamanlayıcı olmasın).
          refreshInterval: null,
          onSetOrigin: onSetOrigin ?? () {},
          onSetDestination: onSetDestination ?? () {},
          onNavigate: onNavigate ?? () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('durakta duran hatlar ve yaklaşan otobüsler listelenir',
      (tester) async {
    KentkartApi.client = MockClient((_) async => http.Response(
        _gazimihalBody, 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    await pumpSheet(tester, stop: _gazimihal);

    // Başlık: gerçek durak adı sunucudan gelir
    expect(find.text('Gazimihal'), findsOneWidget);
    expect(find.textContaining('Durak no: 20210'), findsOneWidget);

    // Hatlar: iki yön tek satırda birleşir, hat kodu rozeti görünür
    expect(find.text('BU DURAKTAN GEÇEN HATLAR'), findsOneWidget);
    expect(find.text('1A'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('GAZİMİHAL - SERA KENT'), findsOneWidget);

    // Yaklaşan canlı otobüsler: dakika ve durak bilgisiyle
    expect(find.text('YAKLAŞAN CANLI OTOBÜSLER'), findsOneWidget);
    expect(find.text('3 dk'), findsOneWidget);
    expect(find.text('9 dk'), findsOneWidget);
    expect(find.textContaining('22 CD 456'), findsOneWidget);
    expect(find.textContaining('1 durak uzakta'), findsOneWidget);
  });

  testWidgets('otobüs yoksa boş durum mesajı gösterilir', (tester) async {
    KentkartApi.client = MockClient((_) async => http.Response(
        _otogarEmptyBusesBody, 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    await pumpSheet(tester, stop: _otogar);

    expect(find.text('Otogar'), findsOneWidget);
    expect(find.text('1T'), findsOneWidget);
    // 1T hattının iki yönü tek satırda toplanır
    expect(
      find.textContaining('GAZİMİHAL - OTOGAR  ·  OTOGAR - GAZİMİHAL'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Şu an bu durağa yaklaşan otobüs bildirilmiyor'),
      findsOneWidget,
    );
    // Sağlık sorunu yok → uyarı bandı çizilmez
    expect(find.textContaining('Canlı veri:'), findsNothing);
  });

  testWidgets('şema değiştiğinde uyarı görünür ve sessizce yutulmaz',
      (tester) async {
    KentkartApi.client = MockClient((_) async => http.Response(
        _driftedBody, 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    await pumpSheet(tester, stop: _otogar);

    // Şema kayması kullanıcıya açıkça söylenir
    expect(find.text('Canlı veri: şema değişti'), findsOneWidget);
    expect(find.textContaining('routeList'), findsWidgets);
    expect(find.textContaining('yerleşik ETUS verisi kullanılıyor'),
        findsOneWidget);
    // Hat listesi boş olduğu da dürüstçe belirtilir
    expect(find.text('Bu durak için hat kaydı bulunamadı.'), findsOneWidget);
  });

  testWidgets('eylem butonları geri çağrıları tetikler', (tester) async {
    KentkartApi.client = MockClient((_) async => http.Response(
        _gazimihalBody, 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    var origin = 0, destination = 0, navigate = 0;
    await pumpSheet(
      tester,
      stop: _gazimihal,
      onSetOrigin: () => origin++,
      onSetDestination: () => destination++,
      onNavigate: () => navigate++,
    );

    await tester.tap(find.text('Kalkış yap'));
    await tester.tap(find.text('Varış yap'));
    await tester.tap(find.text('Bu durağa navigasyon başlat'));
    await tester.pumpAndSettle();

    expect(origin, 1);
    expect(destination, 1);
    expect(navigate, 1);
  });

  testWidgets('istek başarısızsa hata görünür şekilde gösterilir',
      (tester) async {
    KentkartApi.client = MockClient((_) async => http.Response('yok', 503));

    await pumpSheet(tester, stop: _otogar);

    expect(find.textContaining('Durak bilgisi alınamadı'), findsOneWidget);
    expect(find.text('Canlı veri: erişilemiyor'), findsOneWidget);
  });
}
