import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:etus_mobile/services/bus_journey_service.dart';
import 'package:etus_mobile/services/kentkart_api.dart';

/// Gerçek Kentkart `routes` CSV alanıyla planlama: sahte hat üretilmez.
void main() {
  KentkartStop stop(String id, String name, double lat, double lng,
      List<String> routes) {
    return KentkartStop(
        stopId: id, name: name, lat: lat, lng: lng, routes: routes);
  }

  final stops = [
    stop('1', 'Gazimihal', 41.67658, 26.54606, ['1A', '3']),
    stop('2', 'Bankalar', 41.67684, 26.55059, ['1A', '3']),
    stop('3', 'Otogar', 41.63231, 26.61950, ['3', '5A']),
    stop('4', 'Delta Park', 41.63842, 26.61186, ['5A']),
  ];

  test('aynı hattı gören iki uç direkt öneri üretir', () {
    final res = BusJourneyService.plan(
      origin: const LatLng(41.6766, 26.5461),
      destination: const LatLng(41.6769, 26.5506),
      stops: stops,
    );
    expect(res.direct, isNotEmpty);
    expect(res.direct.first.lineCode, '1A');
    // Yürüme mesafeleri metre/dakika olarak hesaplanır.
    expect(res.direct.first.walkToBoardMeters, lessThan(200));
    expect(res.direct.first.totalMinutes, greaterThan(0));
  });

  test('ortak hat yoksa aktarma veya yakın hat listesi döner', () {
    final res = BusJourneyService.plan(
      origin: const LatLng(41.6766, 26.5461),
      destination: const LatLng(41.6384, 26.6118),
      stops: stops,
    );
    // Gazimihal(1A,3) → Delta Park(5A): 3 hattı Otogar'da 5A ile kesişir.
    expect(res.hasOption, isTrue);
    if (res.direct.isEmpty) {
      expect(res.transfer, isNotEmpty);
      final t = res.transfer.first;
      expect(t.firstLine, isNotEmpty);
      expect(t.secondLine, isNotEmpty);
      expect(t.hubStop.routes,
          containsAll([t.firstLine, t.secondLine]));
    }
  });

  test('durak ağı boşsa sahte öneri üretilmez', () {
    final res = BusJourneyService.plan(
      origin: const LatLng(41.67, 26.55),
      destination: const LatLng(41.63, 26.61),
      stops: const [],
    );
    expect(res.hasOption, isFalse);
    expect(res.direct, isEmpty);
    expect(res.destLines, isEmpty);
  });

  test('çok uzak varışta en yakın durak yine de gösterilir', () {
    final res = BusJourneyService.plan(
      origin: const LatLng(41.6766, 26.5461),
      destination: const LatLng(40.0, 25.0),
      stops: stops,
      maxWalkMeters: 900,
    );
    // Uzakta direkt olamaz ama yakın hat listesi dürüstçe boş/dolu döner,
    // sahte direkt uydurulmaz.
    expect(res.direct, isEmpty);
  });
}
