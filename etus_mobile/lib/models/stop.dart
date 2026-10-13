import 'dart:math';

/// ETUS Otobüs Durağı ve Önemli Yer Modeli
class Stop {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String description;
  final String category; // 'avm', 'hastane', 'universite', 'ulasim', 'tarihi', 'meydan'
  final List<String> aliases; // Kullanıcının kast edebileceği takma adlar, eşanlamlılar ve niyet kelimeleri

  const Stop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.category,
    required this.aliases,
  });

  /// Haversine formülü ile iki koordinat arası mesafeyi metre cinsinden hesaplar
  int distanceTo(double lat, double lng) {
    const double earthRadius = 6371000; // metre
    final double dLat = _degToRad(lat - latitude);
    final double dLng = _degToRad(lng - longitude);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(latitude)) *
            cos(_degToRad(lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return (earthRadius * c).round();
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);
}
