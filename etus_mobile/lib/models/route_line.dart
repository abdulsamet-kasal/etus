/// ETUS Otobüs Hattı Modeli
class RouteLine {
  final String id;
  final String name; // Örn: 'Hat 3'
  final String title; // Örn: 'Gazimihal - Saraçlar - Tıp - Otogar'
  final String description;
  final int colorValue; // Renk hex değeri (0xFF2563EB gibi)
  final String interval; // Sefer sıklığı (7-10 dk)
  final List<String> stopIds; // Sıralı durak ID listesi

  const RouteLine({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.colorValue,
    required this.interval,
    required this.stopIds,
  });

  /// İki durak arasındaki güzergahı sırasıyla döndürür
  List<String>? getSubStops(String fromStopId, String toStopId) {
    final int fromIndex = stopIds.indexOf(fromStopId);
    final int toIndex = stopIds.indexOf(toStopId);

    if (fromIndex == -1 || toIndex == -1) return null;

    if (fromIndex <= toIndex) {
      return stopIds.sublist(fromIndex, toIndex + 1);
    } else {
      return stopIds.sublist(toIndex, fromIndex + 1).reversed.toList();
    }
  }
}

/// Eşleşen Yolculuk Seçeneği Modeli
class JourneyOption {
  final RouteLine route;
  final List<String> subStopIds;
  final int stopCount;
  final int busDurationMinutes;
  final int walkDurationMinutes;
  final int totalDurationMinutes;
  final bool isForward;

  JourneyOption({
    required this.route,
    required this.subStopIds,
    required this.stopCount,
    required this.busDurationMinutes,
    required this.walkDurationMinutes,
    required this.totalDurationMinutes,
    required this.isForward,
  });
}
