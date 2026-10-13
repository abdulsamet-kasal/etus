import 'package:flutter/material.dart';
import '../models/route_line.dart';
import '../models/stop.dart';
import '../data/etus_data.dart';
import '../services/location_service.dart';

/// Yolculuk kartı: doğrudan veya aktarmalı rotayı adımlarla gösterir.
/// Üst bölümde süre, sefer sıklığı ve hat bilgisi; alt bölümde adım listesi.
class RouteCard extends StatefulWidget {
  final JourneyOption journey;
  final Stop originStop;
  final Stop destinationStop;
  final double userLat;
  final double userLng;

  const RouteCard({
    super.key,
    required this.journey,
    required this.originStop,
    required this.destinationStop,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<RouteCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final firstRoute = journey.legs.first.route;
    final primaryColor = Color(firstRoute.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: journey.isDirect ? Colors.grey.shade200 : Colors.deepPurple.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Başlık: süre, hatlar, sıklık
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withOpacity(0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Hat rozetleri (aktarmalıysa birden fazla)
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < journey.legs.length; i++) ...[
                            if (i > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Icon(Icons.arrow_forward_ios,
                                    size: 10, color: Colors.white70),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                journey.legs[i].route.name,
                                style: TextStyle(
                                  color: Color(journey.legs[i].route.colorValue),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⏱️ ~${journey.totalMinutes} dk',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.originStop.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Icon(Icons.arrow_downward, size: 14, color: Colors.white70),
                ),
                Text(
                  widget.destinationStop.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                // Toplam kırılım: yürüme + otobüs + bekleme
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _infoChip('🚶 ${journey.walkMinutes} dk yürüme'),
                    _infoChip('🚌 ${journey.busMinutes - journey.waitMinutes} dk yolda'),
                    _infoChip('⏳ ${journey.waitMinutes} dk bekleme'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  journey.isDirect
                      ? 'Aktarmasız • Sefer sıklığı: ${firstRoute.interval}'
                      : '${journey.transferCount} aktarma • 1. hat ${firstRoute.interval}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (firstRoute.serviceHours != null)
                  Text(
                    'Hizmet saatleri: ${firstRoute.serviceHours}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 10,
                    ),
                  ),
                const SizedBox(height: 14),

                // CANLI NAVİGASYON BUTONU — doğrudan sürüş/navigasyon modunda başlar
                ElevatedButton.icon(
                  onPressed: () {
                    LocationService.startNavigation(
                      destLat: widget.destinationStop.latitude,
                      destLng: widget.destinationStop.longitude,
                      destLabel: widget.destinationStop.name,
                    );
                  },
                  icon: const Icon(Icons.navigation, color: Colors.red, size: 18),
                  label: const Text(
                    'Canlı Navigasyonu Başlat',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 2,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Toplu taşıma alternatifi
                OutlinedButton.icon(
                  onPressed: () {
                    LocationService.launchGoogleMapsTransit(
                      originLat: widget.userLat,
                      originLng: widget.userLng,
                      destLat: widget.destinationStop.latitude,
                      destLng: widget.destinationStop.longitude,
                    );
                  },
                  icon: const Icon(Icons.directions_transit, size: 16),
                  label: const Text(
                    'Google Maps ile Toplu Taşıma',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Adım adım yol tarifi
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOLCULUK ADIMLARI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),

                // Adım 1: Yürüme
                _buildStep(
                  stepNumber: '1',
                  stepColor: Colors.amber.shade700,
                  title: 'Biniş Durağına Yürüyün',
                  subtitle:
                      '${widget.originStop.name} (~${journey.walkMinutes} dk yürüme, ${journey.walkMeters} m)',
                ),

                // Bacaklar (hatlar)
                for (var i = 0; i < journey.legs.length; i++) ...[
                  const SizedBox(height: 12),
                  _buildLegStep(journey.legs[i], i),
                  if (i < journey.legs.length - 1) ...[
                    const SizedBox(height: 12),
                    _buildStep(
                      stepNumber: '🔄',
                      stepColor: Colors.deepPurple,
                      title: 'Aktarma Yapın',
                      subtitle:
                          '${journey.legs[i].alightAt.name} durağında inip ${journey.legs[i + 1].route.name} otobüsüne binin (~${journey.legs[i + 1].waitMinutes} dk bekleme).',
                    ),
                  ],
                ],

                // Son adım: İniş
                const SizedBox(height: 12),
                _buildStep(
                  stepNumber: '🏁',
                  stepColor: Colors.green,
                  title: 'Hedef Durakta İnin',
                  subtitle: '${widget.destinationStop.name} durağında inin.',
                ),

                const SizedBox(height: 12),
                const Divider(),

                // Akordeon: Durak Listesi
                InkWell(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Geçilecek Tüm Duraklar (${journey.legs.fold<int>(0, (sum, l) => sum + l.subWaypoints.length)})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_isExpanded) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < journey.legs.length; i++) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Color(journey.legs[i].route.colorValue)
                              .withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            journey.legs[i].route.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(journey.legs[i].route.colorValue),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._buildStopList(journey.legs[i]),
                          const SizedBox(height: 6),
                          Text(
                            'Sefer sıklığı: ${journey.legs[i].route.interval} • Tahmini bekleme: ~${journey.legs[i].waitMinutes} dk',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            journey.legs[i].route.scheduleSource == 'resmi'
                                ? '✅ Belediye resmi saat çizelgesi'
                                : '⚠️ Tahmini (resmi çizelgede yok)',
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  journey.legs[i].route.scheduleSource == 'resmi'
                                      ? Colors.green.shade700
                                      : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Bir bacak (hat) için bin-in adımı
  Widget _buildLegStep(JourneyLeg leg, int index) {
    return _buildStep(
      stepNumber: '${index + 2}',
      stepColor: Color(leg.route.colorValue),
      title: '${leg.route.name} Otobüsüne Binin',
      subtitle:
          '${leg.boardAt.name} → ${leg.alightAt.name} (${leg.subWaypoints.length} durak, ~${leg.rideMinutes} dk) • Her ${leg.route.interval} bir sefer',
    );
  }

  List<Widget> _buildStopList(JourneyLeg leg) {
    return leg.subWaypoints.asMap().entries.map((entry) {
      final idx = entry.key;
      final wp = entry.value;
      final isFirst = idx == 0;
      final isLast = idx == leg.subWaypoints.length - 1;
      final stop = wp.placeId != null ? EtusDatabase.stops[wp.placeId] : null;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: isFirst
                    ? Colors.green
                    : (isLast ? Colors.red : Colors.grey.shade300),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${idx + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: (isFirst || isLast) ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stop?.name ?? wp.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      (isFirst || isLast) ? FontWeight.bold : FontWeight.normal,
                  color: (isFirst || isLast)
                      ? Colors.black87
                      : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildStep({
    required String stepNumber,
    required Color stepColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: stepColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            stepNumber,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: stepColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
