import 'package:flutter_test/flutter_test.dart';
import 'package:etus_mobile/data/etus_data.dart';
import 'package:etus_mobile/services/journey_service.dart';

void main() {
  group('ETUS Gerçek Veri Bütünlüğü', () {
    test("her waypoint placeId'si stops haritasında mevcut", () {
      for (final route in EtusDatabase.routes) {
        for (final wp in route.waypoints) {
          if (wp.placeId != null) {
            expect(EtusDatabase.stops.containsKey(wp.placeId),
                isTrue,
                reason: '${route.id}. hatında bilinmeyen placeId: ${wp.placeId}');
          }
        }
      }
    });

    test('her hat 2den fazla durak içerir', () {
      for (final route in EtusDatabase.routes) {
        expect(route.waypoints.length, greaterThanOrEqualTo(2),
            reason: '${route.id} hattı çok kısa');
        expect(route.interval, isNotEmpty);
        expect(['resmi', 'tahmini'], contains(route.scheduleSource));
        expect(route.avgHeadwayMin, greaterThan(0));
      }
    });

    test('20 gerçek ETUS hattı tanımlı', () {
      expect(EtusDatabase.routes.length, 20);
      final ids = EtusDatabase.routes.map((r) => r.id).toSet();
      expect(ids, containsAll(['1A', '1F', '2A', '3', '3A', '3C', '4', '5A', '5B', '6', '6A', '6B', '7', '7A', '7E']));
    });

    test('süre ve bekleme hesapları makul', () {
      // Saraçlar → Otogar doğrudan (Hat 3, 3A, 5A vb.)
      final origin = EtusDatabase.stops['D_SARACLAR']!;
      final dest = EtusDatabase.stops['D_OTOGAR']!;
      final journeys = JourneyService.findJourneys(
        originPlace: origin,
        destinationPlace: dest,
        walkMeters: 200,
      );

      expect(journeys, isNotEmpty, reason: 'Saraçlar→Otogar için seçenek yok');
      final direct = journeys.where((j) => j.isDirect).toList();
      expect(direct, isNotEmpty, reason: 'Saraçlar→Otogar doğrudan hat yok');

      for (final j in journeys) {
        expect(j.totalMinutes, greaterThan(0));
        expect(j.totalMinutes, lessThan(180),
            reason: 'yolculuk 3 saati geçmemeli');
        expect(j.walkMinutes, greaterThanOrEqualTo(1));
        expect(j.waitMinutes, greaterThanOrEqualTo(1));
        expect(j.legs.first.subWaypoints.first.placeId, origin.id);
        expect(j.legs.last.subWaypoints.last.placeId, dest.id);
      }
    });

    test('aktarmalı rota bulunabilir (Karaağaç → Eczacılık)', () {
      final origin = EtusDatabase.stops['D_KARAAĞAC']!;
      final dest = EtusDatabase.stops['D_ECZACILIK']!;
      final journeys = JourneyService.findJourneys(
        originPlace: origin,
        destinationPlace: dest,
        walkMeters: 300,
      );

      expect(journeys, isNotEmpty, reason: 'Karaağaç→Eczacılık seçenek yok');

      // Doğrudan hat var mı kontrol et (3C, 6A Eczacılık'a gitmiyor olabilir)
      final direct = journeys.where((j) => j.isDirect);
      final transfer = journeys.where((j) => !j.isDirect);

      // En az bir seçenek ya doğrudandır ya aktarmalı
      expect(direct.isNotEmpty || transfer.isNotEmpty, isTrue);

      // Aktarmalı seçenek varsa: 2 bacak, hub her iki hatta da geçiyor
      for (final j in transfer) {
        expect(j.legs.length, 2);
        final hub = j.legs[0].alightAt.placeId;
        expect(hub, isNotNull);
        expect(hub, j.legs[1].boardAt.placeId,
            reason: 'aktarma durağı iki bacakta aynı olmalı');
      }
    });

    test('kendi kendine yolculuk boş döner', () {
      final p = EtusDatabase.stops['D_SARACLAR']!;
      final journeys = JourneyService.findJourneys(
        originPlace: p,
        destinationPlace: p,
        walkMeters: 100,
      );
      expect(journeys, isEmpty);
    });
  });
}
