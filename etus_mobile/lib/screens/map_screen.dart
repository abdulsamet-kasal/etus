import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/etus_data.dart';
import '../models/stop.dart';
import '../services/kentkart_api.dart';
import '../services/location_service.dart';
import '../widgets/kentkart_status_banner.dart';
import '../widgets/stop_detail_sheet.dart';

/// Uygulama içi OpenStreetMap haritası:
/// - OSM döşemeleri (API anahtarı gerektirmez)
/// - **Tüm ETUS durakları** katmanı; bir durağa dokununca o duraktan geçen
///   hatlar ve yaklaşan canlı otobüsler açılır
/// - Başlangıç (kalkış) ve varış noktası seçimi (dokunarak veya GPS)
/// - Kentkart'tan canlı otobüs konumları (10 sn'de bir yenilenir)
/// - Seçilen duraklar arası güzergâh çizgisi
class MapScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum _PickMode { none, origin, destination }

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  LatLng? _origin;
  LatLng? _destination;
  String _originLabel = 'Konumunuz';
  String _destinationLabel = '';
  _PickMode _pickMode = _PickMode.none;

  KentkartCatalog? _catalog;
  bool _loadingCatalog = true;
  String? _catalogError;
  bool _showStops = true;

  List<KentkartLiveBus> _buses = [];
  Timer? _busTimer;
  bool _loadingBuses = false;

  List<LatLng> _routeLine = [];
  bool _loadingRoute = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    if (lat != null && lng != null) {
      _origin = LatLng(lat, lng);
    }
    await _loadCatalog();
    _startBusTimer();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final catalog = await KentkartApi.fetchCatalog();
      setState(() => _catalog = catalog);
      if (_origin == null && catalog.stops.isNotEmpty) {
        // Merkez: ilk durak değil, Saraçlar çevresi (Edirne merkez)
        _origin = const LatLng(41.6752, 26.5548);
      }
    } catch (e) {
      setState(() => _catalogError =
          'Canlı durak listesi alınamadı; harita yine de kullanılabilir.');
    } finally {
      setState(() => _loadingCatalog = false);
    }
  }

  void _startBusTimer() {
    _busTimer?.cancel();
    _busTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadBuses());
    _loadBuses();
  }

  Future<void> _loadBuses() async {
    final ref = _origin ?? _destination;
    if (ref == null) return;
    if (mounted) setState(() => _loadingBuses = true);
    try {
      // Yakın durak ID'sini bul
      final stops = _catalog?.stops ?? const <KentkartStop>[];
      String? stopId;
      double best = double.infinity;
      for (final s in stops) {
        final d = const Distance()
            .as(LengthUnit.Meter, ref, LatLng(s.lat, s.lng));
        if (d < best) {
          best = d;
          stopId = s.stopId;
        }
      }
      if (stopId == null) return;
      final buses = await KentkartApi.fetchLiveBuses(
        lat: ref.latitude,
        lng: ref.longitude,
        stopId: stopId,
      );
      if (mounted) setState(() => _buses = buses);
    } catch (_) {
      // Hata yutulmuyor: KentkartApi hatayı KentkartHealth'e kaydeder ve
      // ekranın üstündeki KentkartStatusBanner kullanıcıya gösterir.
      if (mounted) setState(() => _buses = []);
    } finally {
      if (mounted) setState(() => _loadingBuses = false);
    }
  }

  Future<void> _drawRoute() async {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null || _catalog == null) return;
    setState(() => _loadingRoute = true);
    try {
      // Kalkış ve varışa en yakın hatları yerel veritabanından seç
      final codes = <String>{..._localLinesThrough(o, d)};

      // Hiçbiri eşleşmediyse kalkışa en yakın Kentkart hattını dene
      if (codes.isEmpty && _catalog!.routes.isNotEmpty) {
        codes.add(_catalog!.routes.first.displayCode);
      }

      // Seçilen hatların güzergâhını çiz
      final lines = <List<LatLng>>[];
      for (final code in codes) {
        try {
          final path = await KentkartApi.fetchPath(code);
          if (path.points.length >= 2) {
            lines.add(path.points
                .map((p) => LatLng(p.lat, p.lng))
                .toList(growable: false));
          }
        } catch (_) {
          // tek hat çekilemezse diğerleriyle devam
        }
      }

      if (!mounted) return;
      if (lines.isNotEmpty) {
        // En kısa (en dolambaçsız) güzergâhı ana çizgi seç
        lines.sort((a, b) => a.length.compareTo(b.length));
        setState(() => _routeLine = lines.first);
        _fitToRoute(lines.first);
      } else {
        // Sessiz düşüş yok: kullanıcı bunun gerçek güzergâh olmadığını bilmeli.
        setState(() => _routeLine = [
              LatLng(o.latitude, o.longitude),
              LatLng(d.latitude, d.longitude),
            ]);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Canlı güzergâh çizilemedi; iki nokta arasında düz çizgi gösteriliyor.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  /// Yerel ETUS veritabanından iki nokta arasındaki hat kodlarını tahmin eder.
  List<String> _localLinesThrough(LatLng o, LatLng d) {
    final result = <String>[];
    const dist = Distance();
    for (final line in EtusDatabase.routes) {
      // Hat kodu Kentkart display koduyla aynı olmalı (1A, 3, 6B ...)
      final code = line.id;
      final stops = <Stop>[];
      for (final wp in line.waypoints) {
        final id = wp.placeId;
        if (id == null) continue;
        final s = EtusDatabase.stops[id];
        if (s != null) stops.add(s);
      }
      if (stops.isEmpty) continue;
      double minO = double.infinity, minD = double.infinity;
      for (final s in stops) {
        final p = LatLng(s.latitude, s.longitude);
        minO = mathMin(minO, dist.as(LengthUnit.Meter, o, p));
        minD = mathMin(minD, dist.as(LengthUnit.Meter, d, p));
      }
      if (minO < 600 && minD < 600) result.add(code);
      if (result.length >= 3) break;
    }
    return result;
  }

  static double mathMin(double a, double b) => a < b ? a : b;

  void _fitToRoute(List<LatLng> line) {
    if (line.isEmpty) return;
    double minLat = line.first.latitude, maxLat = line.first.latitude;
    double minLng = line.first.longitude, maxLng = line.first.longitude;
    for (final p in line) {
      minLat = mathMin(minLat, p.latitude);
      minLng = mathMin(minLng, p.longitude);
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat - 0.004, minLng - 0.004),
          LatLng(maxLat + 0.004, maxLng + 0.004),
        ),
      ),
    );
  }

  /// Durağa dokunulduğunda: hatlar + yaklaşan canlı otobüsler.
  void _openStopDetail(KentkartStop stop) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StopDetailSheet(
        stop: stop,
        onSetOrigin: () {
          Navigator.pop(ctx);
          setState(() {
            _origin = LatLng(stop.lat, stop.lng);
            _originLabel = stop.name;
            _routeLine = [];
          });
          _mapController.move(LatLng(stop.lat, stop.lng), 15);
          _loadBuses();
        },
        onSetDestination: () {
          Navigator.pop(ctx);
          setState(() {
            _destination = LatLng(stop.lat, stop.lng);
            _destinationLabel = stop.name;
            _routeLine = [];
          });
          _loadBuses();
        },
        onNavigate: () {
          Navigator.pop(ctx);
          LocationService.startNavigation(
            destLat: stop.lat,
            destLng: stop.lng,
            destLabel: stop.name,
          );
        },
      ),
    );
  }

  void _onMapTap(TapPosition tap, LatLng point) {
    if (_pickMode == _PickMode.none) return;
    setState(() {
      if (_pickMode == _PickMode.origin) {
        _origin = point;
        _originLabel = 'Seçilen kalkış';
      } else {
        _destination = point;
        _destinationLabel = 'Seçilen varış';
      }
      _pickMode = _PickMode.none;
      _routeLine = [];
    });
    _loadBuses();
  }

  Future<void> _useMyLocation() async {
    final loc = await LocationService.getCurrentLocation();
    setState(() {
      _origin = LatLng(loc.latitude, loc.longitude);
      _originLabel = 'GPS konumunuz';
      _routeLine = [];
    });
    _mapController.move(_origin!, 15);
    _loadBuses();
  }

  void _searchStop({required bool isOrigin}) {
    final stops = _catalog?.stops ?? const <KentkartStop>[];
    if (stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Durak listesi henüz yüklenmedi.')),
      );
      return;
    }
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              final q = controller.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? stops.take(30)
                  : stops.where((s) => s.name.toLowerCase().contains(q));
              return SizedBox(
                height: 500,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          hintText: isOrigin
                              ? 'Kalkış durağı ara...'
                              : 'Varış durağı ara...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: filtered.take(40).map((s) {
                          return ListTile(
                            leading: Icon(
                              isOrigin ? Icons.trip_origin : Icons.place,
                              color: isOrigin ? Colors.green : Colors.red,
                            ),
                            title: Text(s.name),
                            subtitle: Text(
                                '${s.lat.toStringAsFixed(5)}, ${s.lng.toStringAsFixed(5)}'),
                            trailing: IconButton(
                              tooltip: 'Bu durağın hatları',
                              icon: const Icon(Icons.list_alt, size: 18),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openStopDetail(s);
                              },
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                if (isOrigin) {
                                  _origin = LatLng(s.lat, s.lng);
                                  _originLabel = s.name;
                                } else {
                                  _destination = LatLng(s.lat, s.lng);
                                  _destinationLabel = s.name;
                                }
                                _routeLine = [];
                              });
                              _mapController.move(LatLng(s.lat, s.lng), 15);
                              _loadBuses();
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _busTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buses = _buses;
    final stops = _catalog?.stops ?? const <KentkartStop>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edirne Haritası (OpenStreetMap)'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: _showStops ? 'Durak katmanını gizle' : 'Tüm durakları göster',
            onPressed: () => setState(() => _showStops = !_showStops),
            icon: Icon(_showStops ? Icons.location_off : Icons.location_on),
          ),
          IconButton(
            tooltip: 'GPS konumumu al',
            onPressed: _useMyLocation,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Güzergâhı çiz',
            onPressed: _loadingRoute ? null : _drawRoute,
            icon: _loadingRoute
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _origin ?? const LatLng(41.6752, 26.5548),
              initialZoom: 14,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.etus.edirne.etus_mobile',
              ),
              if (_routeLine.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeLine,
                      strokeWidth: 5,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // 1) TÜM DURAKLAR KATMANI
                  if (_showStops)
                    for (final s in stops)
                      Marker(
                        point: LatLng(s.lat, s.lng),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openStopDetail(s),
                          child: Tooltip(
                            message: '${s.name}\nDokun: hatlar ve canlı otobüsler',
                            child: Center(
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade600,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  // 2) KALKIŞ
                  if (_origin != null)
                    Marker(
                      point: _origin!,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.trip_origin,
                          color: Colors.green, size: 36),
                    ),
                  // 3) VARIŞ
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 44,
                      height: 44,
                      child:
                          const Icon(Icons.place, color: Colors.red, size: 40),
                    ),
                  // 4) CANLI OTOBÜSLER
                  for (final b in buses)
                    Marker(
                      point: LatLng(b.lat, b.lng),
                      width: 40,
                      height: 40,
                      child: Tooltip(
                        message:
                            '${b.lineCode} • ${b.headSign}\n${b.plate} • ${b.minutesAway} dk',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Color(int.parse(
                                'FF${b.colorHex.length == 6 ? b.colorHex : '1D4ED8'}',
                                radix: 16)),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.directions_bus,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap katkıda bulunanlar'),
                ],
              ),
            ],
          ),
          // Canlı veri sorunlarını görünür kılan uyarı (yoksa hiç çizilmez).
          const Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: KentkartStatusBanner(),
          ),
          if (_loadingBuses)
            const Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_loadingCatalog)
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('ETUS hat/durakları yükleniyor...'),
                  ),
                ),
              ),
            ),
          if (_catalogError != null)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_catalogError!,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomSheet: _buildSelectionBar(stopCount: stops.length),
    );
  }

  Widget _buildSelectionBar({required int stopCount}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _endpointButton(
                  icon: Icons.trip_origin,
                  color: Colors.green,
                  label: 'Kalkış',
                  value: _originLabel,
                  active: _pickMode == _PickMode.origin,
                  onTap: () => setState(() {
                    _pickMode = _pickMode == _PickMode.origin
                        ? _PickMode.none
                        : _PickMode.origin;
                  }),
                  onSearch: () => _searchStop(isOrigin: true),
                ),
              ),
              IconButton(
                tooltip: 'Yer değiştir',
                onPressed: () => setState(() {
                  final o = _origin;
                  final ol = _originLabel;
                  _origin = _destination;
                  _originLabel = _destinationLabel.isEmpty
                      ? 'Seçilen kalkış'
                      : _destinationLabel;
                  _destination = o;
                  _destinationLabel = ol;
                  _routeLine = [];
                }),
                icon: const Icon(Icons.swap_vert),
              ),
              Expanded(
                child: _endpointButton(
                  icon: Icons.place,
                  color: Colors.red,
                  label: 'Varış',
                  value: _destinationLabel.isEmpty
                      ? 'Haritada dokun veya ara'
                      : _destinationLabel,
                  active: _pickMode == _PickMode.destination,
                  onTap: () => setState(() {
                    _pickMode = _pickMode == _PickMode.destination
                        ? _PickMode.none
                        : _PickMode.destination;
                  }),
                  onSearch: () => _searchStop(isOrigin: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_origin != null && _destination != null && !_loadingRoute)
                          ? _drawRoute
                          : null,
                  icon: const Icon(Icons.route, size: 18),
                  label: const Text('Güzergâh Çiz'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_origin != null && _destination != null)
                      ? () {
                          LocationService.startNavigation(
                              destLat: _destination!.latitude,
                              destLng: _destination!.longitude);
                        }
                      : null,
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text('Navigasyonu Başlat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
          if (_showStops && stopCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '📍 Haritadaki $stopCount durağa dokunarak o duraktan geçen hatları ve canlı otobüsleri görebilirsiniz.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
          if (_buses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '🕐 Canlı: yakınızdaki ${_buses.length} otobüs (${_buses.first.lineCode} ${_buses.first.minutesAway} dk) — 10 sn’de bir yenilenir',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _endpointButton({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required bool active,
    required VoidCallback onTap,
    required VoidCallback onSearch,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: onTap,
          onLongPress: onSearch,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: active ? color.withOpacity(0.12) : Colors.grey.shade100,
              border: Border.all(
                  color: active ? color : Colors.grey.shade300, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        TextButton(
          onPressed: onSearch,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact),
          child: const Text('Ara', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
