import 'dart:math';

import '../data/etus_data.dart';
import '../models/route_line.dart';
import '../models/stop.dart';

/// ETUS Yolculuk Planlayıcı
///
/// - Doğrudan: origin POI → destination POI tek hatta
/// - Aktarmalı: origin → ortak POI (transfer hub) → destination, 2 hat
///
/// Süreler: kuzey-güney/doğu-batı düzeltmeli haversine yol mesafesi +
/// durak arası tipik bekleme; bekleme süreleri resmi sefer aralığından.
class JourneyService {
  // Ortalama otobüs hızı (km/s) - şehir içi, duraklarda bekleme dahil
  static const double _avgSpeedKmh = 22.0;

  // Yol katsayısı: düz çizgi mesafe → gerçek yol mesafesi
  static const double _routeFactor = 1.35;

  // Durak başına eklenen tipik gecikme (dk)
  static const double _perStopDelayMin = 0.4;

  // Yürüme hızı (dk/metre cinsinden değil: 80 m/dk ≈ 4.8 km/s)
  static const double _walkMetersPerMin = 80.0;

  /// Doğrudan ve tek aktarmalı tüm seçenekleri süre sırasına göre döndürür.
  static List<JourneyOption> findJourneys({
    required Stop originPlace,
    required Stop destinationPlace,
    required int walkMeters,
    int maxResults = 6,
  }) {
    if (originPlace.id == destinationPlace.id) return [];

    final walkMinutes = max(1, (walkMeters / _walkMetersPerMin).ceil());
    final options = <JourneyOption>[];

    // 1) Doğrudan hatlar
    for (final route in EtusDatabase.routes) {
      final seg = route.segmentBetween(originPlace.id, destinationPlace.id);
      if (seg == null || seg.length < 2) continue;
      options.add(JourneyOption(
        legs: [_buildLeg(route, seg)],
        walkMinutes: walkMinutes,
        walkMeters: walkMeters,
        originPlaceId: originPlace.id,
        destinationPlaceId: destinationPlace.id,
      ));
    }

    // 2) Tek aktarmalı seçenekler (origin → hub → destination)
    //    Hub adayları: her iki hatta da geçen koordinatlı POI'lar
    final hubCandidates = _findTransferHubs(originPlace.id, destinationPlace.id);

    for (final hub in hubCandidates) {
      for (final r1 in EtusDatabase.routes) {
        final seg1 = r1.segmentBetween(originPlace.id, hub);
        if (seg1 == null || seg1.length < 2) continue;

        for (final r2 in EtusDatabase.routes) {
          if (r2.id == r1.id) continue; // aktarma farklı hatta olmalı
          final seg2 = r2.segmentBetween(hub, destinationPlace.id);
          if (seg2 == null || seg2.length < 2) continue;

          options.add(JourneyOption(
            legs: [_buildLeg(r1, seg1), _buildLeg(r2, seg2)],
            walkMinutes: walkMinutes,
            walkMeters: walkMeters,
            originPlaceId: originPlace.id,
            destinationPlaceId: destinationPlace.id,
          ));
        }
      }
    }

    // Süre sıralaması; aynı hat kombinasyonunda tekrarları ele
    options.sort((a, b) => a.totalMinutes.compareTo(b.totalMinutes));

    final seen = <String>{};
    final unique = <JourneyOption>[];
    for (final o in options) {
      final key = o.legs.map((l) => '${l.route.id}:${l.boardAt.name}').join('|');
      if (seen.add(key)) unique.add(o);
      if (unique.length >= maxResults) break;
    }
    return unique;
  }

  /// origin ve destination ile en az birer hattı paylaşıp, arada biniş-iniş
  /// için kullanılabilecek ortak POI (transferhub) ID'leri.
  static List<String> _findTransferHubs(String originId, String destId) {
    // origin'i geçen hatların POI seti ∩ destination'i geçen hatların POI seti
    final originHubs = <String>{};
    final destHubs = <String>{};

    for (final route in EtusDatabase.routes) {
      final servesOrigin = route.indexesOfPlace(originId).isNotEmpty;
      final servesDest = route.indexesOfPlace(destId).isNotEmpty;
      for (final wp in route.waypoints) {
        final pid = wp.placeId;
        if (pid == null || pid == originId || pid == destId) continue;
        if (servesOrigin) originHubs.add(pid);
        if (servesDest) destHubs.add(pid);
      }
    }

    final both = originHubs.intersection(destHubs).toList()..sort();
    return both;
  }

  static JourneyLeg _buildLeg(RouteLine route, List<RouteWaypoint> segment) {
    final rideMinutes = _estimateLegMinutes(route, segment);
    final waitMinutes = max(1, (route.avgHeadwayMin / 2).ceil());
    return JourneyLeg(
      route: route,
      subWaypoints: segment,
      rideMinutes: rideMinutes,
      waitMinutes: waitMinutes,
    );
  }

  /// Bir bacağın otobüs içi süresi: uç nokta arası yol mesafesi + durak sayısı
  static int _estimateLegMinutes(RouteLine route, List<RouteWaypoint> segment) {
    final from = EtusDatabase.stops[segment.first.placeId];
    final to = EtusDatabase.stops[segment.last.placeId];

    double minutes;
    if (from != null && to != null) {
      final straight = from.distanceTo(to.latitude, to.longitude).toDouble();
      final roadMeters = straight * _routeFactor;
      minutes = (roadMeters / 1000.0) / _avgSpeedKmh * 60.0;
    } else {
      // Koordinatsız uç nokta: durak sayısına göre tahmin
      minutes = (segment.length - 1) * 2.5;
    }

    minutes += (segment.length - 1) * _perStopDelayMin;
    return max(2, minutes.round());
  }
}
