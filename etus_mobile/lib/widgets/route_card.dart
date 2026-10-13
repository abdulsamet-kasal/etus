import 'package:flutter/material.dart';
import '../models/route_line.dart';
import '../models/stop.dart';
import '../data/etus_data.dart';
import '../services/location_service.dart';

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
    final route = widget.journey.route;
    final primaryColor = Color(route.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
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
          // 1. Google Maps & Hat Başlık Kartı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor,
                  primaryColor.withOpacity(0.85),
                ],
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        route.name,
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⏱️ ~${widget.journey.totalDurationMinutes} dk',
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
                  route.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sefer aralığı: ${route.interval} • Toplam ${widget.journey.stopCount} durak',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 14),

                // GOOGLE MAPS AKSİYON BUTONU
                ElevatedButton.icon(
                  onPressed: () {
                    LocationService.launchGoogleMapsTransit(
                      originLat: widget.userLat,
                      originLng: widget.userLng,
                      destLat: widget.destinationStop.latitude,
                      destLng: widget.destinationStop.longitude,
                    );
                  },
                  icon: const Icon(Icons.navigation, color: Colors.red, size: 18),
                  label: const Text(
                    'Google Haritalar\'da Canlı Başlat',
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
              ],
            ),
          ),

          // 2. Adım Adım Yol Tarifi
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
                  subtitle: '${widget.originStop.name} (~${widget.journey.walkDurationMinutes} dk yürüme)',
                ),

                const SizedBox(height: 12),

                // Adım 2: Otobüs
                _buildStep(
                  stepNumber: '2',
                  stepColor: primaryColor,
                  title: '${route.name} Otobüsüne Binin',
                  subtitle: '${widget.journey.stopCount} durak boyunca seyahat edin (~${widget.journey.busDurationMinutes} dk)',
                ),

                const SizedBox(height: 12),

                // Adım 3: İniş
                _buildStep(
                  stepNumber: '3',
                  stepColor: Colors.emerald,
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
                          'Geçilecek Tüm Duraklar (${widget.journey.subStopIds.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_isExpanded) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: widget.journey.subStopIds.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final stopId = entry.value;
                        final stop = EtusDatabase.stops[stopId];
                        final isFirst = idx == 0;
                        final isLast = idx == widget.journey.subStopIds.length - 1;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: isFirst
                                      ? Colors.emerald
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
                                  stop?.name ?? stopId,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: (isFirst || isLast) ? FontWeight.bold : FontWeight.normal,
                                    color: (isFirst || isLast) ? Colors.black87 : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
