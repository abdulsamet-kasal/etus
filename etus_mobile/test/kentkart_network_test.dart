import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:etus_mobile/services/kentkart_api.dart';
import 'package:etus_mobile/services/kentkart_health.dart';

/// pathInfo birleşimi: tüm duraklar + tüm canlı araçlar.
const String _catalogBody = '''
{
  "result": {"code": 0, "message": "OK"},
  "routeList": [
    {"routeCode": "22011", "displayRouteCode": "1A", "name": "GAZIMIHAL-SERAKENT",
     "routeColor": "EBE10E", "agencyName": "X"},
    {"routeCode": "22003", "displayRouteCode": "3", "name": "GAZIMIHAL - OTOGAR",
     "routeColor": "1B610B", "agencyName": "X"}
  ],
  "stopList": [
    {"stopId": "20001", "name": "Otogar", "lat": "41.632311", "lng": "26.6195089"}
  ]
}
''';

const String _path1ABody = '''
{
  "result": {"code": 0, "message": "OK"},
  "pathList": [{
    "headSign": "SERA KENT", "displayRouteCode": "1A", "direction": "0",
    "pointList": [{"lat": "41.67", "lng": "26.54"}],
    "busStopList": [
      {"seq": "1", "lat": "41.6765808", "lng": "26.5460646", "stopId": "20210",
       "stopName": "Gazimihal", "routes": "1A,3"},
      {"seq": "2", "lat": "41.6768462", "lng": "26.5505967", "stopId": "20033",
       "stopName": "Bankalar 1", "routes": "1A"}
    ],
    "busList": [
      {"busId": "9001", "lat": "41.6770", "lng": "26.5480",
       "plateNumber": "22 M 0001", "busLabel": "SERA KENT"}
    ]
  }]
}
''';

const String _path3Body = '''
{
  "result": {"code": 0, "message": "OK"},
  "pathList": [{
    "headSign": "OTOGAR", "displayRouteCode": "3", "direction": "0",
    "pointList": [],
    "busStopList": [
      {"seq": "1", "lat": "41.6765808", "lng": "26.5460646", "stopId": "20210",
       "stopName": "Gazimihal", "routes": "1A,3"},
      {"seq": "5", "lat": "41.632311", "lng": "26.6195089", "stopId": "20001",
       "stopName": "Otogar", "routes": "3"}
    ],
    "busList": [
      {"busId": "9001", "lat": "41.6770", "lng": "26.5480",
       "plateNumber": "22 M 0001", "busLabel": "SERA KENT"},
      {"busId": "9002", "lat": "41.6321", "lng": "26.6188",
       "plateNumber": "22 M 0002", "busLabel": "OTOGAR"}
    ]
  }]
}
''';

http.Response _json(String body) => http.Response(body, 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final originalClient = KentkartApi.client;
  setUp(() => KentkartHealth.instance.reset());
  tearDown(() => KentkartApi.client = originalClient);

  MockClient pathMock() => MockClient((req) async {
        final url = req.url;
        if (url.path.endsWith('/nearest/find')) return _json(_catalogBody);
        final code = url.queryParameters['displayRouteCode'];
        if (code == '1A') return _json(_path1ABody);
        if (code == '3') return _json(_path3Body);
        // Diğer yönler boş güzergâh.
        return _json(
            '{"result": {"code": 0}, "pathList": []}');
      });

  test('fetchPath durak routes CSV ve pathInfo otobüs biçimini çözer',
      () async {
    KentkartApi.client = pathMock();
    final path = await KentkartApi.fetchPath('1A');
    expect(path.stops.length, 2);
    expect(path.stops.first.routes, containsAll(['1A', '3']));
    // pathInfo busList: plateNumber/busLabel → plate/headSign.
    expect(path.buses.length, 1);
    expect(path.buses.first.plate, '22 M 0001');
    expect(path.buses.first.lineCode, '1A');
    expect(path.buses.first.headSign, 'SERA KENT');
  });

  test('fetchAllStops durakları stopId ile tekilleştirir', () async {
    KentkartApi.client = pathMock();
    final stops =
        await KentkartApi.fetchAllStops(lineCodes: ['1A', '3']);
    final ids = stops.map((s) => s.stopId).toList();
    expect(ids.toSet().length, ids.length);
    // Gazimihal iki hatta da var ama tek kayıt; hatları birleşir.
    final gaz = stops.firstWhere((s) => s.stopId == '20210');
    expect(gaz.routes, containsAll(['1A', '3']));
    expect(stops.length, 3);
  });

  test('fetchAllLiveBuses araçları busId ile tekilleştirir', () async {
    KentkartApi.client = pathMock();
    final buses =
        await KentkartApi.fetchAllLiveBuses(lineCodes: ['1A', '3']);
    // 9001 iki hatta da görünür ama tek araç.
    expect(buses.length, 2);
    expect(buses.map((b) => b.busId).toSet(), {'9001', '9002'});
  });
}
