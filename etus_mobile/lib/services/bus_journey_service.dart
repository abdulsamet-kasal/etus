import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'kentkart_api.dart';

/// Kentkart durak ağıyla keyfî iki nokta arası otobüs+yürüme planı.
///
/// Yerleşik `JourneyService` yalnızca sabit POI veritabanını bilir; haritada
/// aranan gerçek bir adres (Nominatim) için bu servis devreye girer:
/// - kalkışa ve varışa en yakın durakları bulur (haversine),
/// - iki ucu da gören **direkt hatları** kesişimle çıkarır,
/// - direkt yoksa tek aktarmalı öneri üretir,
/// - her seçenekte yürüme mesafelerini (m + dk) açıkça hesaplar.
///
/// Sahte veri üretilmez: hat bilgisi yalnızca durakların gerçek `routes`
/// alanından gelir; eşleşme yoksa boş liste döner.
class BusJourneyService {
  static const double walkMetersPerMin = 80.0;
  static const double busKmh = 22.0;
  static const double routeFactor = 1.35;

  static BusJourneyResult plan({
    required LatLng origin,
    required LatLng destination,
    required List<KentkartStop> stops,
    double maxWalkMeters = 900,
    int maxDirect = 5,
    int maxTransfer = 3,
  }) {
    if (stops.isEmpty) return BusJourneyResult.empty();
    const dist = Distance();
    List<_Scored> near(LatLng p) {
      final list = <_Scored>[];
      for (final s in stops) {
        final m = dist.as(
            LengthUnit.Meter, p, LatLng(s.lat, s.lng));
        list.add(_Scored(stop: s, meters: m));
      }
      list.sort((a, b) => a.meters.compareTo(b.meters));
      return list;
    }

    final nearO = near(origin);
    final nearD = near(destination);
    final boardCands =
        nearO.where((e) => e.meters <= maxWalkMeters).take(4).toList();
    // Kullanıcı ağdan uzaktaysa en yakın durağa yürüyüş yine de önerilir
    // (3 km üstü dürüstçe "çok uzak" sayılır, sahte direkt üretilmez).
    if (boardCands.isEmpty && nearO.first.meters <= 3000) {
      boardCands.add(nearO.first);
    }
    final alightCands =
        nearD.where((e) => e.meters <= maxWalkMeters).take(4).toList();
    // Varışa yakın durak yoksa direkt hat uydurulmaz; sadece `destLines`
    // ile "yakından geçenler" gösterilir.
    if (boardCands.isEmpty || alightCands.isEmpty) {
      final destLines = <String>{};
      for (final c in nearD.take(2)) {
        destLines.addAll(c.stop.routes);
      }
      return BusJourneyResult(
        direct: [],
        transfer: [],
        boardCandidates: boardCands.map((e) => e.stop).toList(),
        alightCandidates: alightCands.map((e) => e.stop).toList(),
        destLines: destLines.toList()..sort(),
      );
    }

    final boardLines = <String>{};
    for (final c in boardCands) {
      boardLines.addAll(c.stop.routes);
    }
    final alightLines = <String>{};
    for (final c in alightCands) {
      alightLines.addAll(c.stop.routes);
    }

    // 1) Direkt hatlar: iki uçta da duran hatlar.
    final direct = <DirectBusOption>[];
    final common = boardLines.intersection(alightLines).toList()..sort();
    for (final line in common) {
      final b = boardCands.firstWhere(
        (c) => c.stop.routes.contains(line),
        orElse: () => boardCands.first,
      );
      final a = alightCands.firstWhere(
        (c) => c.stop.routes.contains(line),
        orElse: () => alightCands.first,
      );
      direct.add(DirectBusOption(
        lineCode: line,
        boardStop: b.stop,
        alightStop: a.stop,
        walkToBoardMeters: b.meters.round(),
        walkFromAlightMeters: a.meters.round(),
        rideMinutes: _rideMinutes(b.stop, a.stop),
      ));
      if (direct.length >= maxDirect) break;
    }
    direct.sort((a, b) =>
        (a.totalWalkMeters + a.rideMinutes * 100)
            .compareTo(b.totalWalkMeters + b.rideMinutes * 100));

    // 2) Tek aktarma: biniş hattı + iniş hattını birlikte gören hub durağı.
    final transfer = <TransferBusOption>[];
    if (direct.isEmpty) {
      final cands = <TransferBusOption>[];
      for (final o in boardCands.take(3)) {
        for (final oLine in o.stop.routes.take(4)) {
          for (final d in alightCands.take(3)) {
            for (final dLine in d.stop.routes.take(4)) {
              if (oLine == dLine) continue;
              final hub = _bestHub(
                  stops, oLine, dLine, o.stop, d.stop, maxHubs: 1);
              if (hub == null) continue;
              cands.add(TransferBusOption(
                firstLine: oLine,
                secondLine: dLine,
                boardStop: o.stop,
                hubStop: hub,
                alightStop: d.stop,
                walkToBoardMeters: o.meters.round(),
                walkFromAlightMeters: d.meters.round(),
                rideMinutes: _rideMinutes(o.stop, hub) +
                    _rideMinutes(hub, d.stop) +
                    5,
              ));
            }
          }
        }
      }
      cands.sort((a, b) => (a.totalWalkMeters + a.rideMinutes * 100)
          .compareTo(b.totalWalkMeters + b.rideMinutes * 100));
      final seen = <String>{};
      for (final c in cands) {
        final key = '${c.firstLine}+${c.secondLine}@${c.hubStop.stopId}';
        if (seen.add(key)) transfer.add(c);
        if (transfer.length >= maxTransfer) break;
      }
    }

    return BusJourneyResult(
      direct: direct,
      transfer: transfer,
      boardCandidates: boardCands.map((e) => e.stop).toList(),
      alightCandidates: alightCands.map((e) => e.stop).toList(),
      destLines: alightLines.toList()..sort(),
    );
  }

  static KentkartStop? _bestHub(
    List<KentkartStop> stops,
    String lineA,
    String lineB,
    KentkartStop nearO,
    KentkartStop nearD, {
    int maxHubs = 1,
  }) {
    const dist = Distance();
    KentkartStop? best;
    var bestScore = double.infinity;
    for (final s in stops) {
      if (!s.routes.contains(lineA) || !s.routes.contains(lineB)) continue;
      if (s.stopId == nearO.stopId || s.stopId == nearD.stopId) continue;
      final d1 = dist.as(LengthUnit.Meter,
          LatLng(nearO.lat, nearO.lng), LatLng(s.lat, s.lng));
      final d2 = dist.as(LengthUnit.Meter,
          LatLng(s.lat, s.lng), LatLng(nearD.lat, nearD.lng));
      final score = d1 + d2;
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  static int _rideMinutes(KentkartStop a, KentkartStop b) {
    const dist = Distance();
    final straight = dist.as(
        LengthUnit.Meter,
        LatLng(a.lat, a.lng),
        LatLng(b.lat, b.lng));
    final roadKm = straight * routeFactor / 1000.0;
    return max(2, (roadKm / busKmh * 60.0).round());
  }
}

class _Scored {
  final KentkartStop stop;
  final double meters;
  _Scored({required this.stop, required this.meters});
}

int walkMinutes(int meters) => max(1, (meters / BusJourneyService.walkMetersPerMin).ceil());

class DirectBusOption {
  final String lineCode;
  final KentkartStop boardStop;
  final KentkartStop alightStop;
  final int walkToBoardMeters;
  final int walkFromAlightMeters;
  final int rideMinutes;

  const DirectBusOption({
    required this.lineCode,
    required this.boardStop,
    required this.alightStop,
    required this.walkToBoardMeters,
    required this.walkFromAlightMeters,
    required this.rideMinutes,
  });

  int get totalWalkMeters => walkToBoardMeters + walkFromAlightMeters;
  int get totalMinutes =>
      walkMinutes(walkToBoardMeters) +
      walkMinutes(walkFromAlightMeters) +
      rideMinutes +
      3;
}

class TransferBusOption {
  final String firstLine;
  final String secondLine;
  final KentkartStop boardStop;
  final KentkartStop hubStop;
  final KentkartStop alightStop;
  final int walkToBoardMeters;
  final int walkFromAlightMeters;
  final int rideMinutes;

  const TransferBusOption({
    required this.firstLine,
    required this.secondLine,
    required this.boardStop,
    required this.hubStop,
    required this.alightStop,
    required this.walkToBoardMeters,
    required this.walkFromAlightMeters,
    required this.rideMinutes,
  });

  int get totalWalkMeters => walkToBoardMeters + walkFromAlightMeters;
  int get totalMinutes =>
      walkMinutes(walkToBoardMeters) +
      walkMinutes(walkFromAlightMeters) +
      rideMinutes +
      8;
}

class BusJourneyResult {
  final List<DirectBusOption> direct;
  final List<TransferBusOption> transfer;
  final List<KentkartStop> boardCandidates;
  final List<KentkartStop> alightCandidates;

  /// Varış noktasının yakınından geçen tüm hatlar (direkt olmasa bile).
  final List<String> destLines;

  const BusJourneyResult({
    required this.direct,
    required this.transfer,
    required this.boardCandidates,
    required this.alightCandidates,
    required this.destLines,
  });

  factory BusJourneyResult.empty() => const BusJourneyResult(
        direct: [],
        transfer: [],
        boardCandidates: [],
        alightCandidates: [],
        destLines: [],
      );

  bool get hasOption => direct.isNotEmpty || transfer.isNotEmpty;
}
