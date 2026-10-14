import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/bus_journey_service.dart';
import '../services/geocoding_service.dart';
import '../services/kentkart_api.dart';
import '../services/location_service.dart';
import '../widgets/kentkart_status_banner.dart';
import '../widgets/stop_detail_sheet.dart';

/// Uygulama içi OpenStreetMap haritası:
/// - OSM döşemeleri (API anahtarı gerektirmez)
/// - Kentkart **tüm durak** katmanı (~390 durak: her hattın pathInfo
///   `busStopList` birleşimi; katalogdaki 50 durak yalnızca başlangıçtır)
/// - Kent genelindeki **tüm canlı araçlar** (her hattın pathInfo `busList`
///   birleşimi, 20 sn'de bir hafif `010000` kipiyle yenilenir)
/// - Hat bazında görünürlük filtresi + tek araç gizleme
/// - Gerçek yer araması (Nominatim): rastgele adres/sokak yazılabilir;
///   sahte eşleşme üretilmez, sonuç haritada işaretlenir
/// - Keyfî noktaya otobüs+yürüme planı (direkt / aktarmalı + yürüme m/dk)
class MapScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  /// Ana ekrandan gerçek bir yerle gelindiğinde varış hazır seçilir.
  final double? initialDestLat;
  final double? initialDestLng;
  final String? initialDestLabel;

  const MapScreen(
      {super.key,
      this.initialLat,
      this.initialLng,
      this.initialDestLat,
      this.initialDestLng,
      this.initialDestLabel});

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
  List<KentkartStop> _allStops = [];
  bool _loadingCatalog = true;
  bool _loadingStops = false;
  String? _catalogError;
  bool _showStops = true;

  /// Kent genelindeki tüm canlı araçlar.
  List<KentkartLiveBus> _allBuses = [];
  Timer? _busTimer;
  bool _loadingBuses = false;
  bool _showBuses = true;

  /// Görünürlük filtresi: gizlenen hat kodları + tekil araç ID'leri.
  final Set<String> _hiddenLines = {};
  final Set<String> _hiddenBuses = {};

  /// Hat kodu → renk (katalogdan).
  final Map<String, String> _routeColors = {};

  /// Hat kodu → güzergâh önbelleği ("1A-0" anahtarlı).
  final Map<String, KentkartPath> _pathCache = {};

  List<LatLng> _routeLine = [];
  List<LatLng> _routeLine2 = [];
  List<LatLng> _walkToBoard = [];
  List<LatLng> _walkFromAlight = [];
  bool _loadingRoute = false;

  BusJourneyResult? _journey;

  List<KentkartLiveBus> get _visibleBuses {
    if (!_showBuses) return const [];
    return _allBuses
        .where((b) =>
            !_hiddenLines.contains(b.lineCode) &&
            !_hiddenBuses.contains(b.busId))
        .toList();
  }

  List<KentkartStop> get _stops =>
      _allStops.isNotEmpty ? _allStops : (_catalog?.stops ?? const []);

  Map<String, int> get _busCounts {
    final m = <String, int>{};
    for (final b in _allBuses) {
      m[b.lineCode] = (m[b.lineCode] ?? 0) + 1;
    }
    return m;
  }

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
    if (widget.initialDestLat != null &&
        widget.initialDestLng != null) {
      _destination =
          LatLng(widget.initialDestLat!, widget.initialDestLng!);
      _destinationLabel =
          widget.initialDestLabel ?? 'Aranan konum';
    }
    await _loadCatalog();
    _startBusTimer();
    if (_origin != null && _destination != null) {
      // Katalog geldikten sonra plan yapılır; duraklar geç gelse de
      // _planJourney güncel listeyle tekrar çalışabilir.
      await _planJourney();
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final catalog = await KentkartApi.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _allStops = catalog.stops;
        for (final r in catalog.routes) {
          _routeColors[r.displayCode] = r.colorHex;
        }
        if (_origin == null && catalog.stops.isNotEmpty) {
          _origin = const LatLng(41.6752, 26.5548);
        }
      });
      // Tüm durak ağı arka planda genişletilir (46 hafif istek).
      _loadAllStops();
    } catch (e) {
      if (!mounted) return;
      setState(() => _catalogError =
          'Canlı durak listesi alınamadı; harita yine de kullanılabilir.');
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  Future<void> _loadAllStops() async {
    if (_catalog == null) return;
    setState(() => _loadingStops = true);
    try {
      final codes = _catalog!.routes.map((r) => r.displayCode).toList();
      final stops = await KentkartApi.fetchAllStops(lineCodes: codes);
      if (!mounted) return;
      if (stops.isNotEmpty) {
        // Katalogdaki 50 durağı koru, yeni gelenleri stopId ile birleştir.
        final merged = <String, KentkartStop>{
          for (final s in _catalog!.stops) s.stopId: s
        };
        for (final s in stops) {
          final prev = merged[s.stopId];
          if (prev == null) {
            merged[s.stopId] = s;
          } else if (prev.routes.isEmpty && s.routes.isNotEmpty) {
            merged[s.stopId] = KentkartStop(
              stopId: prev.stopId,
              name: prev.name,
              lat: prev.lat,
              lng: prev.lng,
              routes: s.routes,
            );
          }
        }
        final list = merged.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        setState(() => _allStops = list);
      }
    } catch (_) {
      // Katalog duraklarıyla devam; sessiz düşüş yok — banner zaten gösterir.
    } finally {
      if (mounted) setState(() => _loadingStops = false);
    }
  }

  void _startBusTimer() {
    _busTimer?.cancel();
    _busTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _loadBuses());
    _loadBuses();
  }

  /// Kent genelindeki tüm canlı araçları çeker (hat başına hafif istek).
  Future<void> _loadBuses() async {
    if (_catalog == null) return;
    if (mounted) setState(() => _loadingBuses = true);
    try {
      final codes = _catalog!.routes.map((r) => r.displayCode).toList();
      final buses = await KentkartApi.fetchAllLiveBuses(lineCodes: codes);
      if (mounted) setState(() => _allBuses = buses);
    } catch (_) {
      // Eski araçlar ekranda kalır; sağlık banner'ı hatayı gösterir.
    } finally {
      if (mounted) setState(() => _loadingBuses = false);
    }
  }

  /// Keyfî iki nokta arası otobüs+yürüme planı + güzergâh çizimi.
  Future<void> _planJourney() async {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null || _stops.isEmpty) return;
    setState(() {
      _loadingRoute = true;
      _journey = null;
    });
    try {
      final plan = BusJourneyService.plan(
        origin: o,
        destination: d,
        stops: _stops,
      );
      if (!mounted) return;
      setState(() => _journey = plan);

      // Güzergâh çizgisi: ilk direkt hattın gerçek polyline'ı, yoksa ilk
      // aktarma hattı. Yön sırası (biniş→iniş) path durak sırasıyla doğrulanır.
      _routeLine = [];
      _routeLine2 = [];
      _walkToBoard = [o];
      _walkFromAlight = [d];
      if (plan.direct.isNotEmpty) {
        final opt = plan.direct.first;
        _walkToBoard = [o, LatLng(opt.boardStop.lat, opt.boardStop.lng)];
        _walkFromAlight = [
          LatLng(opt.alightStop.lat, opt.alightStop.lng),
          d
        ];
        final line = await _fetchLineBetween(
            opt.lineCode, opt.boardStop.stopId, opt.alightStop.stopId);
        if (line != null && mounted) {
          setState(() => _routeLine =
              line.map((p) => LatLng(p.lat, p.lng)).toList());
          _fitToPoints([..._routeLine, o, d]);
        }
      } else if (plan.transfer.isNotEmpty) {
        final t = plan.transfer.first;
        _walkToBoard = [o, LatLng(t.boardStop.lat, t.boardStop.lng)];
        _walkFromAlight = [
          LatLng(t.alightStop.lat, t.alightStop.lng),
          d
        ];
        final l1 = await _fetchLineBetween(
            t.firstLine, t.boardStop.stopId, t.hubStop.stopId);
        final l2 = await _fetchLineBetween(
            t.secondLine, t.hubStop.stopId, t.alightStop.stopId);
        if (mounted) {
          setState(() {
            if (l1 != null) {
              _routeLine = l1.map((p) => LatLng(p.lat, p.lng)).toList();
            }
            if (l2 != null) {
              _routeLine2 = l2.map((p) => LatLng(p.lat, p.lng)).toList();
            }
          });
          final all = [..._routeLine, ..._routeLine2, o, d];
          if (all.length >= 2) _fitToPoints(all);
        }
      }
      if (!mounted) return;
      if (_routeLine.isEmpty && _routeLine2.isEmpty) {
        if (plan.hasOption) {
          // Hat bulundu ama polyline çekilemedi: yürüyüş kolları + bilgi.
          setState(() {
            _routeLine = [o, d];
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Canlı güzergâh çizilemedi; otobüs önerisi aşağıda listelendi.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bu noktaya 900 m içinde direkt otobüs bulunamadı. '
                'Yakından geçenler: ${plan.destLines.take(5).join(', ')}',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  /// Hattın iki durak arasını kapsayan yönün polyline'ı (önbellekli).
  Future<List<({double lat, double lng})>?> _fetchLineBetween(
      String code, String fromStopId, String toStopId) async {
    for (var dir = 0; dir <= 1; dir++) {
      final key = '$code-$dir';
      var path = _pathCache[key];
      path ??= await _safeFetchPath(code, dir);
      if (path == null) continue;
      _pathCache[key] = path;
      final ids = path.stops.map((s) => s.stopId).toList();
      final a = ids.indexOf(fromStopId);
      final b = ids.indexOf(toStopId);
      if (a >= 0 && b >= 0 && a < b && path.points.length >= 2) {
        return path.points;
      }
    }
    // Sıra tutmazsa ilk bulunabilen yönün çizgisi yine gösterilir.
    for (var dir = 0; dir <= 1; dir++) {
      final path = _pathCache['$code-$dir'];
      if (path != null && path.points.length >= 2) return path.points;
    }
    return null;
  }

  Future<KentkartPath?> _safeFetchPath(String code, int dir) async {
    try {
      return await KentkartApi.fetchPath(code, direction: dir);
    } catch (_) {
      return null;
    }
  }

  void _fitToPoints(List<LatLng> pts) {
    if (pts.isEmpty) return;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
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

  Color _colorOf(String? hex) {
    final clean =
        (hex != null && hex.length == 6) ? hex : '1D4ED8';
    return Color(int.parse('FF$clean', radix: 16));
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
            _routeLine2 = [];
            _journey = null;
          });
          _mapController.move(LatLng(stop.lat, stop.lng), 15);
        },
        onSetDestination: () {
          Navigator.pop(ctx);
          setState(() {
            _destination = LatLng(stop.lat, stop.lng);
            _destinationLabel = stop.name;
            _routeLine = [];
            _routeLine2 = [];
            _journey = null;
          });
          _planJourney();
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

  /// Canlı araca dokunulduğunda: bilgi + gizleme seçenekleri.
  void _openBusDetail(KentkartLiveBus bus) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final lineHidden = _hiddenLines.contains(bus.lineCode);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _colorOf(bus.colorHex),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      bus.lineCode,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bus.headSign.isEmpty ? 'Canlı araç' : bus.headSign,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Plaka: ${bus.plate.isEmpty ? '—' : bus.plate}'
                '${bus.minutesAway > 0 ? ' • ${bus.minutesAway} dk' : ''}'
                '${bus.stopsAway > 0 ? ' • ${bus.stopsAway} durak' : ''}',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _hiddenBuses.add(bus.busId));
                      },
                      icon: const Icon(Icons.visibility_off, size: 16),
                      label: const Text('Bu aracı gizle'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          if (lineHidden) {
                            _hiddenLines.remove(bus.lineCode);
                          } else {
                            _hiddenLines.add(bus.lineCode);
                          }
                        });
                      },
                      icon: Icon(lineHidden
                          ? Icons.visibility
                          : Icons.visibility_off),
                      label: Text(lineHidden
                          ? '${bus.lineCode} göster'
                          : '${bus.lineCode} gizle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Hat görünürlük filtresi: tek tek hat seçimi.
  void _openBusFilter() {
    final codes = _routeColors.keys.toList()..sort();
    final counts = _busCounts;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void toggle(String code) {
              setState(() {
                if (_hiddenLines.contains(code)) {
                  _hiddenLines.remove(code);
                } else {
                  _hiddenLines.add(code);
                }
              });
              setSheetState(() {});
            }

            return SizedBox(
              height: 560,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Hangi araçlar görünsün?',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      '${_visibleBuses.length}/${_allBuses.length} araç görünüyor'
                      '${_hiddenBuses.isNotEmpty ? ' • ${_hiddenBuses.length} tekil araç gizli' : ''}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _hiddenLines.clear();
                                _hiddenBuses.clear();
                              });
                              setSheetState(() {});
                            },
                            child: const Text('Tümünü göster'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() => _hiddenLines.addAll(codes));
                              setSheetState(() {});
                            },
                            child: const Text('Tümünü gizle'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hiddenBuses.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _hiddenBuses.clear());
                        setSheetState(() {});
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                          'Gizli tekil araçları temizle'),
                    ),
                  const Divider(height: 8),
                  Expanded(
                    child: ListView(
                      children: codes.map((code) {
                        final hidden =
                            _hiddenLines.contains(code);
                        final n = counts[code] ?? 0;
                        return SwitchListTile(
                          value: !hidden,
                          onChanged: (_) => toggle(code),
                          secondary: Container(
                            width: 40,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: _colorOf(_routeColors[code]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              code,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            n > 0
                                ? '$n araç seferde'
                                : 'şu an seferde araç yok',
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
      _routeLine2 = [];
      _journey = null;
    });
    if (_destination != null) _planJourney();
  }

  Future<void> _useMyLocation() async {
    final loc = await LocationService.getCurrentLocation();
    setState(() {
      _origin = LatLng(loc.latitude, loc.longitude);
      _originLabel = 'GPS konumunuz';
      _routeLine = [];
      _routeLine2 = [];
      _journey = null;
    });
    _mapController.move(_origin!, 15);
  }

  /// Durak + gerçek yer (Nominatim) araması. Sahte eşleşme üretilmez:
  /// durak bulunamazsa OSM sonuçları gösterilir, o da yoksa boş liste.
  void _searchPlace({required bool isOrigin}) {
    final stops = _stops;
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
        var osmResults = <GeocodedPlace>[];
        var osmLoading = false;
        String? osmError;
        var osmSearched = false;
        Timer? debounce;

        Future<void> doOsmSearch(
            void Function(void Function()) setSheetState) async {
          final q = controller.text.trim();
          if (q.length < 3) return;
          setSheetState(() {
            osmLoading = true;
            osmError = null;
          });
          try {
            final res = await GeocodingService.search(q);
            setSheetState(() {
              osmResults = res;
              osmSearched = true;
            });
          } catch (e) {
            setSheetState(() {
              osmError = 'Yer araması başarısız: $e';
              osmSearched = true;
            });
          } finally {
            setSheetState(() => osmLoading = false);
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              final q = controller.text.trim().toLowerCase();
              final local = q.isEmpty
                  ? stops.take(30)
                  : stops
                      .where((s) =>
                          s.name.toLowerCase().contains(q) ||
                          s.stopId.contains(q))
                      .take(15);
              return SizedBox(
                height: 560,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (_) {
                          setSheetState(() {});
                          debounce?.cancel();
                          debounce = Timer(
                              const Duration(milliseconds: 700),
                              () => doOsmSearch(setSheetState));
                        },
                        onSubmitted: (_) =>
                            doOsmSearch(setSheetState),
                        decoration: InputDecoration(
                          hintText: isOrigin
                              ? 'Kalkış ara: durak veya adres...'
                              : 'Varış ara: durak veya adres...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: osmLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'İnternette yer ara',
                                  icon: const Icon(Icons.travel_explore),
                                  onPressed: () =>
                                      doOsmSearch(setSheetState),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (local.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: Text(
                                'DURAKLAR (${local.length})',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          for (final s in local)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                isOrigin
                                    ? Icons.trip_origin
                                    : Icons.place,
                                color: isOrigin
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              title: Text(s.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: s.routes.isEmpty
                                  ? null
                                  : Text(
                                      s.routes.join(' • '),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              Colors.grey.shade600),
                                    ),
                              trailing: IconButton(
                                tooltip: 'Bu durağın hatları',
                                icon: const Icon(Icons.list_alt,
                                    size: 18),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openStopDetail(s);
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _setEndpoint(
                                    isOrigin: isOrigin,
                                    point:
                                        LatLng(s.lat, s.lng),
                                    label: s.name);
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Text(
                              osmSearched
                                  ? 'HARİTA YERLERİ (${osmResults.length})'
                                  : 'HARİTA YERLERİ (adres yazıp büyütece dokunun)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          if (osmError != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              child: Text(osmError!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.red)),
                            ),
                          if (!osmSearched && osmResults.isEmpty)
                            const Padding(
                              padding:
                                  EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Örn: "Meriç Köprüsü", "Balkan Kampüsü", "Kapıkule yolu" — ne yazarsanız haritada gerçek konumu bulunur.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          for (final p in osmResults)
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                  Icons.travel_explore,
                                  color: Colors.teal),
                              title: Text(p.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(p.fullName,
                                  maxLines: 2,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _setEndpoint(
                                    isOrigin: isOrigin,
                                    point: LatLng(p.lat, p.lng),
                                    label: p.name);
                              },
                            ),
                        ],
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

  void _setEndpoint(
      {required bool isOrigin,
      required LatLng point,
      required String label}) {
    setState(() {
      if (isOrigin) {
        _origin = point;
        _originLabel = label;
      } else {
        _destination = point;
        _destinationLabel = label;
      }
      _routeLine = [];
      _routeLine2 = [];
      _journey = null;
    });
    _mapController.move(point, 15);
    if (_origin != null && _destination != null) _planJourney();
  }

  @override
  void dispose() {
    _busTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buses = _visibleBuses;
    final stops = _stops;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edirne Haritası (OpenStreetMap)'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Hangi araçlar görünsün? (${buses.length})',
            onPressed: _openBusFilter,
            icon: Badge(
              label: Text('${buses.length}'),
              isLabelVisible: buses.isNotEmpty,
              child: Icon(
                  _hiddenLines.isEmpty && _hiddenBuses.isEmpty
                      ? Icons.directions_bus
                      : Icons.directions_bus_filled),
            ),
          ),
          IconButton(
            tooltip: _showStops
                ? 'Durak katmanını gizle'
                : 'Tüm durakları göster',
            onPressed: () =>
                setState(() => _showStops = !_showStops),
            icon: Icon(
                _showStops ? Icons.location_off : Icons.location_on),
          ),
          IconButton(
            tooltip: 'GPS konumumu al',
            onPressed: _useMyLocation,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Otobüs bul + güzergâh çiz',
            onPressed: _loadingRoute ? null : _planJourney,
            icon: _loadingRoute
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
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
              initialCenter:
                  _origin ?? const LatLng(41.6752, 26.5548),
              initialZoom: 14,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
              if (_routeLine2.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeLine2,
                      strokeWidth: 5,
                      color: Colors.green.shade700,
                    ),
                  ],
                ),
              if (_walkToBoard.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _walkToBoard,
                      strokeWidth: 3,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              if (_walkFromAlight.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _walkFromAlight,
                      strokeWidth: 3,
                      color: Colors.grey.shade600,
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
                            message:
                                '${s.name}\nDokun: hatlar ve canlı otobüsler',
                            child: Center(
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade600,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white,
                                      width: 2),
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
                      child: const Icon(Icons.place,
                          color: Colors.red, size: 40),
                    ),
                  // 4) CANLI OTOBÜSLER (tümü, filtreli)
                  for (final b in buses)
                    Marker(
                      point: LatLng(b.lat, b.lng),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openBusDetail(b),
                        child: Tooltip(
                          message:
                              '${b.lineCode} • ${b.headSign}\n${b.plate} • dokun: seçenekler',
                          child: Container(
                            decoration: BoxDecoration(
                              color: _colorOf(b.colorHex.isEmpty
                                  ? _routeColors[b.lineCode]
                                  : b.colorHex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                                Icons.directions_bus,
                                color: Colors.white,
                                size: 20),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                      '© OpenStreetMap katkıda bulunanlar'),
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
          if (_loadingStops)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 56),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                        'Tüm duraklar yükleniyor (${stops.length} bulundu)...'),
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
                        style:
                            const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
          if (_journey != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 218,
              child: _buildJourneyCard(),
            ),
        ],
      ),
      bottomSheet: _buildSelectionBar(stopCount: stops.length),
    );
  }

  Widget _buildJourneyCard() {
    final j = _journey!;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('OTOBÜS ÖNERİLERİ',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8)),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _journey = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                for (final d in j.direct.take(3))
                  _directRow(d),
                for (final t in j.transfer.take(2))
                  _transferRow(t),
                if (!j.hasOption)
                  Text(
                    j.destLines.isEmpty
                        ? 'Bu noktaya 900 m içinde otobüs durağı bulunamadı.'
                        : 'Direkt hat yok. Yakından geçenler: ${j.destLines.take(6).join(', ')} — varışa en yakın durağa yürüyüp bu hatlara binebilirsiniz.',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _directRow(DirectBusOption d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _colorOf(_routeColors[d.lineCode]),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(d.lineCode,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${d.boardStop.name} → ${d.alightStop.name}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('~${d.totalMinutes} dk',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '🚶 Binişe ${d.walkToBoardMeters} m (~${walkMinutes(d.walkToBoardMeters)} dk) • '
            '🚌 ${d.rideMinutes} dk • '
            '🚶 İnişten ${d.walkFromAlightMeters} m (~${walkMinutes(d.walkFromAlightMeters)} dk)',
            style: TextStyle(
                fontSize: 11, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Widget _transferRow(TransferBusOption t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.firstLine} → ${t.hubStop.name} aktarma → ${t.secondLine}',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '🚶 Binişe ${t.walkToBoardMeters} m • 🚌 ~${t.rideMinutes} dk • '
            '🚶 İnişten ${t.walkFromAlightMeters} m • Toplam ~${t.totalMinutes} dk',
            style: TextStyle(
                fontSize: 11, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar({required int stopCount}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.12), blurRadius: 12),
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
                  onSearch: () => _searchPlace(isOrigin: true),
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
                  _routeLine2 = [];
                  _journey = null;
                }),
                icon: const Icon(Icons.swap_vert),
              ),
              Expanded(
                child: _endpointButton(
                  icon: Icons.place,
                  color: Colors.red,
                  label: 'Varış',
                  value: _destinationLabel.isEmpty
                      ? 'Durak veya adres ara'
                      : _destinationLabel,
                  active:
                      _pickMode == _PickMode.destination,
                  onTap: () => setState(() {
                    _pickMode =
                        _pickMode == _PickMode.destination
                            ? _PickMode.none
                            : _PickMode.destination;
                  }),
                  onSearch: () =>
                      _searchPlace(isOrigin: false),
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
                          ? _planJourney
                          : null,
                  icon: const Icon(Icons.route, size: 18),
                  label: const Text('Otobüs Bul'),
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
                              destLat:
                                  _destination!.latitude,
                              destLng:
                                  _destination!.longitude);
                        }
                      : null,
                  icon:
                      const Icon(Icons.navigation, size: 18),
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
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _allBuses.isEmpty
                  ? '🕐 Canlı araçlar yükleniyor... (20 sn’de bir yenilenir)'
                  : '🕐 Canlı: kent genelinde ${_visibleBuses.length} araç görünüyor (toplam ${_allBuses.length}) — 20 sn’de bir yenilenir',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600),
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
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? color.withOpacity(0.12)
                  : Colors.grey.shade100,
              border: Border.all(
                  color: active ? color : Colors.grey.shade300,
                  width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        TextButton(
          onPressed: onSearch,
          style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact),
          child: const Text('Ara', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
