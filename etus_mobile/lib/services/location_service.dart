import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/etus_data.dart';
import '../models/stop.dart';

class UserLocationResult {
  final double latitude;
  final double longitude;
  final String label;
  final Stop nearestStop;
  final int distanceToStopMeters;

  const UserLocationResult({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.nearestStop,
    required this.distanceToStopMeters,
  });
}

class LocationService {
  // Varsayılan Edirne Şehir Merkezi Koordinatı (GPS izni yoksa yedek)
  static const double defaultLat = 41.6752;
  static const double defaultLng = 26.5548;
  static const String defaultLabel = "Saraçlar Caddesi (Edirne Merkez)";

  /// Cihazın GPS Konumunu Al ve En Yakın Durağı Bul
  static Future<UserLocationResult> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Konum servisleri açık mı?
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _getDefaultLocation("Konum Servisi Kapalı (Merkez Seçildi)");
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _getDefaultLocation("Konum İzni Verilmedi (Merkez Seçildi)");
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return _getDefaultLocation("Konum İzni Kalıcı Reddedildi (Merkez)");
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final nearest = findNearestStop(position.latitude, position.longitude);
      final dist = nearest.distanceTo(position.latitude, position.longitude);

      return UserLocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        label: "Canlı GPS Konumunuz",
        nearestStop: nearest,
        distanceToStopMeters: dist,
      );
    } catch (e) {
      return _getDefaultLocation("GPS Zaman Aşımı (Merkez Seçildi)");
    }
  }

  /// Belirtilen Koordinata En Yakın Durağı Tespit Eder
  static Stop findNearestStop(double lat, double lng) {
    Stop? nearest;
    int minDistance = 999999999;

    for (var stop in EtusDatabase.stops.values) {
      final dist = stop.distanceTo(lat, lng);
      if (dist < minDistance) {
        minDistance = dist;
        nearest = stop;
      }
    }

    return nearest ?? EtusDatabase.stops.values.first;
  }

  /// Varsayılan Konum Yardımcısı
  static UserLocationResult _getDefaultLocation(String reason) {
    final nearest = findNearestStop(defaultLat, defaultLng);
    return UserLocationResult(
      latitude: defaultLat,
      longitude: defaultLng,
      label: reason,
      nearestStop: nearest,
      distanceToStopMeters: nearest.distanceTo(defaultLat, defaultLng),
    );
  }

  /// Google Maps Toplu Taşıma Yol Tarifini Aç (seçim ekranı)
  static Future<bool> launchGoogleMapsTransit({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final Uri url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng&travelmode=transit',
    );

    if (await canLaunchUrl(url)) {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      return false;
    }
  }

  /// Canlı navigasyonu **doğrudan başlatır** (yol tarifi ekranı değil, sürüş modu).
  ///
  /// Öncelik sırası:
  /// 1. `google.navigation:q=` → Google Maps anında turn-by-turn navigasyon açar
  /// 2. `https://www.google.com/maps/dir/?...&dir_action=navigate` → web fallback
  /// 3. `geo:` → cihazdaki varsayılan harita uygulaması
  static Future<bool> startNavigation({
    required double destLat,
    required double destLng,
    String? destLabel,
    String travelMode = 'd', // d=driving, w=walking, t=transit
  }) async {
    final coord = '$destLat,$destLng';
    final label = destLabel ?? '';

    final candidates = <Uri>[
      // 1) Google Maps native navigasyon — harita anında canlı konumla başlar
      Uri.parse('google.navigation:q=$coord&mode=$travelMode'),
      // 2) Web fallback — dir_action=navigate ile doğrudan navigasyon başlatır
      Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$coord&destination_place_id=&dir_action=navigate&travelmode=$travelMode'),
      // 3) Genel geo: intenti (OsmAnd, Apple Haritalar vb.)
      Uri.parse('geo:$coord?q=$coord(${Uri.encodeComponent(label)})'),
    ];

    for (final url in candidates) {
      try {
        if (await canLaunchUrl(url)) {
          final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
          if (ok) return true;
        }
      } catch (_) {
        // sıradaki adaya geç
      }
    }
    return false;
  }
}
