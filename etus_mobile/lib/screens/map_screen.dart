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

/// Edirne toplu ulaşım haritası — sade tasarım.
///
/// - Üstte tek arama kartı (kalkış / varış + değiştir)
/// - Altta iki düğme: Otobüs Bul + Git
/// - Kent genelindeki tüm canlı araçlar (20 sn yenileme, hat filtresi)
/// - Tüm duraklar (~390), gerçek yer araması (Photon + Nominatim)
/// - Keyfî noktaya otobüs+yürüme önerisi
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
      // Katalog duraklarıyla devam; banner hatayı gösterir.
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
          setState(() => _routeLine = [o, d]);
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
    final clean = (hex != null && hex.length == 6) ? hex : '1D4ED8';
    return Color(int.parse('FF$clean', radix: 16));
  }

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
            _clearRoute();
          });
          _mapController.move(LatLng(stop.lat, stop.lng), 15);
        },
        onSetDestination: () {
          Navigator.pop(ctx);
          setState(() {
            _destination = LatLng(stop.lat, stop.lng);
            _destinationLabel = stop.name;
            _clearRoute();
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

  void _clearRoute() {
    _routeLine = [];
    _routeLine2 = [];
    _walkToBoard = [];
    _walkFromAlight = [];
    _journey = null;
  }

  void _openBusDetail(KentkartLiveBus bus) {
    final lineHidden = _hiddenLines.contains(bus.lineCode);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _lineBadge(bus.lineCode, size: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bus.headSign.isEmpty ? 'Canlı araç' : bus.headSign,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Plaka: ${bus.plate.isEmpty ? '—' : bus.plate}'
              '${bus.minutesAway > 0 ? '  •  ${bus.minutesAway} dk' : ''}'
              '${bus.stopsAway > 0 ? '  •  ${bus.stopsAway} durak' : ''}',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _hiddenBuses.add(bus.busId));
                    },
                    icon: const Icon(Icons.visibility_off, size: 17),
                    label: const Text('Aracı gizle'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                  ),
                ),
                const SizedBox(width: 10),
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
                    label: Text(lineHidden ? 'Hattı göster' : 'Hattı gizle'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hat görünürlük filtresi — hat içinde arama + tek tek seçim.
  void _openBusFilter() {
    final codes = _routeColors.keys.toList()..sort();
    final counts = _busCounts;
    final query = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final q = query.text.trim().toLowerCase();
          final shown = q.isEmpty
              ? codes
              : codes.where((c) => c.toLowerCase().contains(q)).toList();
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
            height: 600,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_visibleBuses.length}/${_allBuses.length} araç görünüyor',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                if (_hiddenBuses.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _hiddenBuses.clear());
                      setSheetState(() {});
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(
                        '${_hiddenBuses.length} gizli aracı geri getir'),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: TextField(
                    controller: query,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Hat ara (örn: 1A)',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
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
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(
                                () => _hiddenLines.addAll(codes));
                            setSheetState(() {});
                          },
                          child: const Text('Tümünü gizle'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (ctx, i) {
                      final code = shown[i];
                      final hidden =
                          _hiddenLines.contains(code);
                      final n = counts[code] ?? 0;
                      return SwitchListTile(
                        value: !hidden,
                        onChanged: (_) => toggle(code),
                        secondary: _lineBadge(code, size: 13),
                        title: Text(
                          n > 0 ? '$n araç seferde' : 'Seferde araç yok',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _lineBadge(String code, {double size = 12}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _colorOf(_routeColors[code]),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        code,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size,
        ),
      ),
    );
  }

  void _onMapTap(TapPosition tap, LatLng point) {
    if (_pickMode == _PickMode.none) return;
    final isOrigin = _pickMode == _PickMode.origin;
    setState(() {
      if (isOrigin) {
        _origin = point;
        _originLabel = 'Seçilen konum...';
      } else {
        _destination = point;
        _destinationLabel = 'Seçilen konum...';
      }
      _pickMode = _PickMode.none;
      _clearRoute();
    });
    // Dokunulan noktanın gerçek adresi arka planda gelir.
    GeocodingService.reverse(point.latitude, point.longitude)
        .then((name) {
      if (!mounted || name == null) return;
      setState(() {
        if (isOrigin) {
          if (_origin == point) _originLabel = name;
        } else {
          if (_destination == point) _destinationLabel = name;
        }
      });
    });
    if (_origin != null && _destination != null) _planJourney();
  }

  Future<void> _useMyLocation() async {
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _origin = LatLng(loc.latitude, loc.longitude);
      _originLabel = 'Konumum';
      _clearRoute();
    });
    _mapController.move(_origin!, 15);
  }

  /// Durak + gerçek yer araması (Photon + Nominatim, debounce'lu).
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var osmResults = <GeocodedPlace>[];
        var osmLoading = false;
        String? osmError;
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
            setSheetState(() => osmResults = res);
          } catch (e) {
            setSheetState(
                () => osmError = 'Yer araması başarısız, tekrar deneyin.');
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
                  ? stops.take(20)
                  : stops
                      .where((s) =>
                          s.name.toLowerCase().contains(q) ||
                          s.stopId.contains(q) ||
                          s.routes.any((r) =>
                              r.toLowerCase().contains(q)))
                      .take(12);
              return SizedBox(
                height: 600,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (_) {
                          setSheetState(() {});
                          debounce?.cancel();
                          debounce = Timer(
                              const Duration(milliseconds: 600),
                              () => doOsmSearch(setSheetState));
                        },
                        onSubmitted: (_) =>
                            doOsmSearch(setSheetState),
                        decoration: InputDecoration(
                          hintText: isOrigin
                              ? 'Nereden? Durak veya adres yazın'
                              : 'Nereye? Durak veya adres yazın',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: osmLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(
                                            strokeWidth: 2),
                                  ),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (local.isNotEmpty)
                            _sheetHeader(
                                'DURAKLAR', Icons.directions_bus),
                          for (final s in local)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                isOrigin
                                    ? Icons.trip_origin
                                    : Icons.place,
                                color: isOrigin
                                    ? Colors.green.shade700
                                    : Colors.red.shade600,
                                size: 20,
                              ),
                              title: Text(s.name,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              subtitle: s.routes.isEmpty
                                  ? null
                                  : Text(s.routes.join('  •  '),
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color:
                                              Colors.grey.shade600)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _setEndpoint(
                                    isOrigin: isOrigin,
                                    point:
                                        LatLng(s.lat, s.lng),
                                    label: s.name);
                              },
                            ),
                          _sheetHeader('ADRES VE YERLER',
                              Icons.travel_explore),
                          if (osmError != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: Text(osmError!,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.red)),
                            ),
                          if (osmResults.isEmpty && !osmLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Text(
                                'En az 3 harf yazın; Edirne içindeki adres, cadde ve önemli yerler burada listelenir.',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey),
                              ),
                            ),
                          for (final p in osmResults)
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                  Icons.location_on_outlined,
                                  color: Colors.teal,
                                  size: 20),
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(p.fullName,
                                  maxLines: 2,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5)),
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

  Widget _sheetHeader(String text, IconData icon) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
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
      _clearRoute();
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
        title: const Text('Edirne Ulaşım',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: '${buses.length} araç görünüyor — filtrele',
            onPressed: _openBusFilter,
            icon: Badge(
              label: Text('${buses.length}'),
              isLabelVisible: buses.isNotEmpty,
              child: const Icon(Icons.directions_bus),
            ),
          ),
          IconButton(
            tooltip:
                _showStops ? 'Durakları gizle' : 'Durakları göster',
            onPressed: () =>
                setState(() => _showStops = !_showStops),
            icon: Icon(_showStops
                ? Icons.layers
                : Icons.layers_outlined),
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
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              if (_walkFromAlight.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _walkFromAlight,
                      strokeWidth: 3,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
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
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade500,
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
                  if (_origin != null)
                    Marker(
                      point: _origin!,
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.trip_origin,
                          color: Colors.green, size: 38),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.place,
                          color: Colors.red, size: 42),
                    ),
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
                              '${b.lineCode} • ${b.headSign}\nDokun: seçenekler',
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
          // Üst: arama kartı + durum bandı
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchCard(),
                const SizedBox(height: 6),
                const KentkartStatusBanner(),
                if (_pickMode != _PickMode.none)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _pickHint(),
                  ),
                if (_loadingStops)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _pill(
                        'Tüm duraklar yükleniyor (${stops.length})...'),
                  ),
                if (_catalogError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _pill(_catalogError!,
                        warning: true),
                  ),
              ],
            ),
          ),
          // Sağ alt: konumum düğmesi
          Positioned(
            right: 12,
            bottom: 196,
            child: FloatingActionButton.small(
              heroTag: 'myLoc',
              tooltip: 'Konumuma git',
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue.shade700,
              onPressed: _useMyLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
          if (_journey != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 128,
              child: _buildJourneyCard(),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(
          buses: buses, stopCount: stops.length),
    );
  }

  Widget _pill(String text, {bool warning = false}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: warning
            ? Colors.orange.shade50
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: warning
                ? Colors.orange.shade200
                : Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 2))
        ],
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center),
    );
  }

  Widget _pickHint() {
    final text = _pickMode == _PickMode.origin
        ? 'Kalkış için haritada bir noktaya dokunun'
        : 'Varış için haritada bir noktaya dokunun';
    return InkWell(
      onTap: () => setState(() => _pickMode = _PickMode.none),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade700,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$text  •  Vazgeç',
            style: const TextStyle(
                fontSize: 12.5,
                color: Colors.white,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Üst arama kartı: kalkış / varış satırları + değiştir.
  Widget _buildSearchCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _searchRow(
                  dot: Colors.green.shade600,
                  icon: Icons.trip_origin,
                  value: _originLabel,
                  hint: 'Nereden?',
                  active: _pickMode == _PickMode.origin,
                  onTap: () => setState(() {
                    _pickMode = _pickMode == _PickMode.origin
                        ? _PickMode.none
                        : _PickMode.origin;
                  }),
                  onSearch: () =>
                      _searchPlace(isOrigin: true),
                ),
                Divider(
                    height: 1,
                    indent: 44,
                    color: Colors.grey.shade200),
                _searchRow(
                  dot: Colors.red.shade600,
                  icon: Icons.place,
                  value: _destinationLabel.isEmpty
                      ? ''
                      : _destinationLabel,
                  hint: 'Nereye?',
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
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kalkış ile varışı değiştir',
            onPressed: () => setState(() {
              final o = _origin;
              final ol = _originLabel;
              _origin = _destination;
              _originLabel = _destinationLabel.isEmpty
                  ? 'Nereden?'
                  : _destinationLabel;
              _destination = o;
              _destinationLabel = ol == 'Konumunuz'
                  ? ''
                  : ol;
              _clearRoute();
            }),
            icon: const Icon(Icons.swap_vert),
          ),
        ],
      ),
    );
  }

  Widget _searchRow({
    required Color dot,
    required IconData icon,
    required String value,
    required String hint,
    required bool active,
    required VoidCallback onTap,
    required VoidCallback onSearch,
  }) {
    final empty = value.isEmpty;
    return InkWell(
      onTap: onSearch,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color:
              active ? dot.withOpacity(0.08) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: dot, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                empty ? hint : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: empty
                      ? FontWeight.normal
                      : FontWeight.w600,
                  color: empty
                      ? Colors.grey.shade500
                      : Colors.black87,
                ),
              ),
            ),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.touch_app,
                  size: 17,
                  color: active
                      ? dot
                      : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJourneyCard() {
    final j = _journey!;
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxHeight: 230),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('ÖNERİLEN OTOBÜSLER',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _journey = null),
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
                for (final d in j.direct.take(3))
                  _directRow(d),
                for (final t in j.transfer.take(2))
                  _transferRow(t),
                if (!j.hasOption)
                  Padding(
                    padding:
                        const EdgeInsets.only(right: 8),
                    child: Text(
                      j.destLines.isEmpty
                          ? 'Bu noktaya 900 m içinde otobüs durağı bulunamadı.'
                          : 'Direkt hat yok. Yakından geçenler: ${j.destLines.take(6).join(', ')}',
                      style: const TextStyle(fontSize: 13),
                    ),
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
      margin:
          const EdgeInsets.only(bottom: 8, right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _lineBadge(d.lineCode, size: 12),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${d.boardStop.name} → ${d.alightStop.name}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('~${d.totalMinutes} dk',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          _timeline(steps: [
            _Step(
                'Yürü ${d.walkToBoardMeters} m',
                walkMinutes(d.walkToBoardMeters)),
            _Step(
                'Otobüs ${d.lineCode}', d.rideMinutes),
            _Step(
                'Yürü ${d.walkFromAlightMeters} m',
                walkMinutes(d.walkFromAlightMeters)),
          ]),
        ],
      ),
    );
  }

  Widget _transferRow(TransferBusOption t) {
    return Container(
      margin:
          const EdgeInsets.only(bottom: 8, right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _lineBadge(t.firstLine, size: 11),
              const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward,
                    size: 14),
              ),
              _lineBadge(t.secondLine, size: 11),
              const Spacer(),
              Text('~${t.totalMinutes} dk',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${t.boardStop.name} → ${t.hubStop.name} aktarma → ${t.alightStop.name}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _timeline(steps: [
            _Step('Yürü ${t.walkToBoardMeters} m',
                walkMinutes(t.walkToBoardMeters)),
            _Step('Otobüs', t.rideMinutes),
            _Step(
                'Yürü ${t.walkFromAlightMeters} m',
                walkMinutes(t.walkFromAlightMeters)),
          ]),
        ],
      ),
    );
  }

  Widget _timeline({required List<_Step> steps}) {
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            const Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: 3),
              child: Icon(Icons.more_horiz,
                  size: 13, color: Colors.grey),
            ),
          Icon(
            i == 1
                ? Icons.directions_bus
                : Icons.directions_walk,
            size: 14,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${steps[i].label} (${steps[i].minutes} dk)',
              style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  /// Alt eylem çubuğu: iki düğme + ince durum satırı.
  Widget _buildBottomBar(
      {required List<KentkartLiveBus> buses,
      required int stopCount}) {
    final ready =
        _origin != null && _destination != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14,
          14 + 0), // SafeArea padding ayrıca
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 14),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: ready && !_loadingRoute
                        ? _planJourney
                        : null,
                    icon: _loadingRoute
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child:
                                CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                          )
                        : const Icon(Icons.route,
                            size: 19),
                    label: const Text('Otobüs Bul',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: ready
                        ? () {
                            LocationService
                                .startNavigation(
                                    destLat: _destination!
                                        .latitude,
                                    destLng: _destination!
                                        .longitude);
                          }
                        : null,
                    icon: const Icon(Icons.navigation,
                        size: 19),
                    label: const Text('Git',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.green.shade600,
                      foregroundColor: Colors.white,
                      minimumSize:
                          const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _loadingCatalog
                  ? 'Yükleniyor...'
                  : '$stopCount durak  •  ${buses.length} canlı araç'
                      '${_loadingBuses ? ' (güncelleniyor)' : ''}',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step {
  final String label;
  final int minutes;
  _Step(this.label, this.minutes);
}
