/// ETUS Otobüs Hattı Modeli (Gerçek ETUS Verisi)
///
/// Waypoint'ler resmi/güncel ETUS güzergah kataloglarından alınmıştır.
/// placeId verilen waypoint'ler EtusDatabase.stops içindeki önemli yerlere
/// (durak-anlamlı POI) bağlanmıştır; koordinat hesabı ve arama bu sayede çalışır.
class RouteWaypoint {
  /// Durağın gerçek adı (katalogdaki hali)
  final String name;

  /// Bu waypoint bir önemli yere aitse (duran POI) ID'si
  final String? placeId;

  const RouteWaypoint(this.name, {this.placeId});
}

class RouteLine {
  final String id;
  final String name; // Örn: 'Hat 3'
  final String title; // Örn: 'Gazimihal - Bankalar - ... - Otogar'
  final String description;
  final int colorValue; // Renk hex değeri (0xFF2563EB gibi)

  /// Tipik sefer aralığı, örn: '5-12 dk' (gündüz saatleri)
  final String interval;

  /// Gün içi saat dilimi bazında resmi aralık dökümü
  /// Örn: '07:00-08:00: 10 dk · 08:00-17:30: 5-10 dk · 18:00-23:30: 15-20 dk'
  final String intervalDetail;

  /// 'resmi' = Belediye Otobüs Saatleri çizelgesinden, 'tahmini' = yayına dayalı tahmin
  final String scheduleSource;

  /// Bekleme süresi hesabı için ortalama sefer aralığı (dakika)
  final int avgHeadwayMin;

  /// Resmi çizelgedeki ortalama tam hat sefer süresi (varsa)
  final int? avgTripMinutes;

  /// İlk ve son kalkış saatleri (varsa), örn: '07:00 - 23:30'
  final String? serviceHours;

  /// Güzergahın sıralı gerçek durakları
  final List<RouteWaypoint> waypoints;

  const RouteLine({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.colorValue,
    required this.interval,
    required this.intervalDetail,
    required this.scheduleSource,
    required this.avgHeadwayMin,
    this.avgTripMinutes,
    this.serviceHours,
    required this.waypoints,
  });

  /// Belirli bir önemli yerin (placeId) bu hattaki tüm durak indekslerini bulur
  List<int> indexesOfPlace(String placeId) {
    final List<int> indexes = [];
    for (int i = 0; i < waypoints.length; i++) {
      if (waypoints[i].placeId == placeId) indexes.add(i);
    }
    return indexes;
  }

  /// fromPlaceId ile toPlaceId arasındaki waypoint segmentini güzergah
  /// sırasına göre döndürür (her iki yön de desteklenir). Bulunamazsa null.
  List<RouteWaypoint>? segmentBetween(String fromPlaceId, String toPlaceId) {
    final fromIndexes = indexesOfPlace(fromPlaceId);
    final toIndexes = indexesOfPlace(toPlaceId);

    List<RouteWaypoint>? best;
    for (final fi in fromIndexes) {
      for (final ti in toIndexes) {
        if (fi == ti) continue;
        final List<RouteWaypoint> seg = fi < ti
            ? waypoints.sublist(fi, ti + 1)
            : waypoints.sublist(ti, fi + 1).reversed.toList();
        if (best == null || seg.length < best.length) {
          best = seg;
        }
      }
    }
    return best;
  }
}

/// Bir biniş-iniş bacağının (hat üzerinde tek sefer) hesabı
class JourneyLeg {
  final RouteLine route;
  final List<RouteWaypoint> subWaypoints;

  /// Otobüs içinde tahmini süre (dakika)
  final int rideMinutes;

  /// Bu biniş için tahmini bekleme (sefer aralığının yarısı)
  final int waitMinutes;

  const JourneyLeg({
    required this.route,
    required this.subWaypoints,
    required this.rideMinutes,
    required this.waitMinutes,
  });

  RouteWaypoint get boardAt => subWaypoints.first;
  RouteWaypoint get alightAt => subWaypoints.last;

  /// İki durak arası ara durak sayısı (biniş/iniş hariç)
  int get intermediateStops => (subWaypoints.length - 2).clamp(0, 1 << 30);
}

/// Kullanıcıya gösterilen tam yolculuk seçeneği (doğrudan veya 1 aktarmalı)
class JourneyOption {
  final List<JourneyLeg> legs;

  /// Biniş durağına yürüme süresi (dakika)
  final int walkMinutes;

  /// Biniş durağına yürüme mesafesi (metre)
  final int walkMeters;

  final String originPlaceId;
  final String destinationPlaceId;

  const JourneyOption({
    required this.legs,
    required this.walkMinutes,
    required this.walkMeters,
    required this.originPlaceId,
    required this.destinationPlaceId,
  });

  bool get isDirect => legs.length == 1;
  int get transferCount => legs.length - 1;

  /// Yürüme + otobüs süreleri + aktarma cezası (aktarma başına 3 dk)
  int get totalMinutes {
    int bus = 0;
    for (final leg in legs) {
      bus += leg.rideMinutes + leg.waitMinutes;
    }
    return walkMinutes + bus + (transferCount * 3);
  }

  /// Sadece otobüste geçen toplam süre (bekleme dahil)
  int get busMinutes {
    int bus = 0;
    for (final leg in legs) {
      bus += leg.rideMinutes + leg.waitMinutes;
    }
    return bus;
  }

  /// Toplam tahmini bekleme (binmeden önce + aktarmada)
  int get waitMinutes {
    int w = 0;
    for (final leg in legs) {
      w += leg.waitMinutes;
    }
    return w;
  }

  /// Kullanıcının binmesi gereken hatların özeti: 'Hat 3 → Hat 5A'
  String get lineSummary => legs.map((l) => l.route.name).join(' → ');
}
