import 'dart:async';

import 'package:flutter/material.dart';
import '../models/stop.dart';
import '../models/route_line.dart';
import '../data/etus_data.dart';
import '../services/geocoding_service.dart';
import '../services/smart_search_service.dart';
import '../services/location_service.dart';
import '../services/journey_service.dart';
import '../services/kentkart_health.dart';
import '../widgets/kentkart_status_banner.dart';
import '../widgets/quick_chip.dart';
import '../widgets/route_card.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  UserLocationResult? _userLocation;
  bool _isLoadingLocation = false;

  List<SmartSearchResult> _smartSuggestions = [];
  Stop? _selectedDestination;
  String? _selectedMatchReason;
  List<JourneyOption> _journeyOptions = [];

  /// Gerçek yer sonuçları (Nominatim). Yerel eşleşme zayıfsa bunlar gösterilir;
  /// sahte durak eşleşmesi üretilmez.
  List<GeocodedPlace> _osmSuggestions = [];
  bool _osmLoading = false;
  Timer? _osmDebounce;

  /// Elle seçilen kalkış (GPS yerine kullanıcı başka durak seçebilir)
  Stop? _customOrigin;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _osmDebounce?.cancel();
    super.dispose();
  }

  /// Konum Bilgisini Al (GPS veya Yedek)
  Future<void> _fetchLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    final loc = await LocationService.getCurrentLocation();

    setState(() {
      _userLocation = loc;
      _isLoadingLocation = false;
    });

    if (_selectedDestination != null) {
      _calculateJourneys();
    }
  }

  /// Arama Metni Değiştiğinde Akıllı Arama Motorunu Çalıştır
  ///
  /// Yerel sonuçlar güven skoru 60+ ise gösterilir; düşük skorlu zorlama
  /// eşleşmeler gizlenir (sahte sonuç şikâyeti). Gerçek adresler Nominatim
  /// ile aranır ve ayrı bölümde listelenir.
  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _osmDebounce?.cancel();
      setState(() {
        _smartSuggestions = [];
        _osmSuggestions = [];
        _osmLoading = false;
      });
      return;
    }

    final results = SmartSearchService.search(query)
        .where((r) => r.score >= 60)
        .toList();
    setState(() {
      _smartSuggestions = results;
    });

    // Gerçek yer araması (debounce 700 ms, en az 3 harf).
    _osmDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _osmSuggestions = [];
        _osmLoading = false;
      });
      return;
    }
    _osmDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      setState(() => _osmLoading = true);
      try {
        final places = await GeocodingService.search(query.trim());
        if (!mounted) return;
        // Kullanıcı yazmaya devam ettiyse eski sonucu gösterme.
        if (_searchController.text.trim() != query.trim()) return;
        setState(() => _osmSuggestions = places);
      } catch (_) {
        if (!mounted) return;
        setState(() => _osmSuggestions = []);
      } finally {
        if (mounted) setState(() => _osmLoading = false);
      }
    });
  }

  /// Hedef Belirle ve Rotayı Hesapla
  void _selectDestination(Stop stop, String reason) {
    setState(() {
      _selectedDestination = stop;
      _selectedMatchReason = reason;
      _searchController.text = stop.name;
      _smartSuggestions = [];
    });
    FocusScope.of(context).unfocus();
    _calculateJourneys();
  }

  /// Doğrudan veya Akıllı En İyi Eşleşmeyi Arama
  ///
  /// Güven skoru 70+ yerel eşleşme yoksa sahte durak seçilmez; önce gerçek
  /// yer (OSM) denenir, o da yoksa kullanıcı haritaya yönlendirilir.
  Future<void> _executeSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen gitmek istediğiniz yeri yazın.')),
      );
      return;
    }

    final results = SmartSearchService.search(query);
    final strong =
        results.where((r) => r.score >= 70).toList();
    if (strong.isNotEmpty) {
      final top = strong.first;
      _selectDestination(top.stop, top.matchedReason);
      return;
    }

    // Yerel güvenilir eşleşme yok → gerçek yeri dene.
    try {
      final places = await GeocodingService.search(query);
      if (!mounted) return;
      if (places.isNotEmpty) {
        _openPlaceOnMap(places.first);
        return;
      }
    } catch (_) {
      // OSM hatası aşağıda dürüstçe bildirilir.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '"$query" için kayıtlı durak bulunamadı; haritada aratarak gerçek konumu seçebilirsiniz.')),
    );
  }

  /// Gerçek bir adresi haritada varış olarak açar.
  void _openPlaceOnMap(GeocodedPlace place) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          initialLat: _userLocation?.latitude,
          initialLng: _userLocation?.longitude,
          initialDestLat: place.lat,
          initialDestLng: place.lng,
          initialDestLabel: place.name,
        ),
      ),
    );
  }

  /// Kalkış noktasını belirle (GPS veya elle seçilen durak)
  Stop get _originStop =>
      _customOrigin ?? _userLocation?.nearestStop ?? EtusDatabase.stops.values.first;

  /// ETUS Hatlarını ve Yolculuk Seçeneklerini Hesapla (doğrudan + aktarmalı)
  void _calculateJourneys() {
    if (_selectedDestination == null) return;
    if (_userLocation == null && _customOrigin == null) return;

    final originStop = _originStop;
    final destStop = _selectedDestination!;

    if (originStop.id == destStop.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zaten gitmek istediğiniz durağın çok yakınındasınız!')),
      );
      return;
    }

    // Yürüme mesafesi: GPS varsa GPS→kalkış, yoksa 0 (kullanıcı zaten durakta)
    int walkMeters;
    if (_customOrigin != null) {
      if (_userLocation != null) {
        walkMeters = originStop.distanceTo(
            _userLocation!.latitude, _userLocation!.longitude);
      } else {
        walkMeters = 0;
      }
    } else {
      walkMeters = _userLocation!.distanceToStopMeters;
    }

    final options = JourneyService.findJourneys(
      originPlace: originStop,
      destinationPlace: destStop,
      walkMeters: walkMeters,
      maxResults: 6,
    );

    setState(() {
      _journeyOptions = options;
    });
  }

  /// Kalkış durağını elle seç (GPS yerine)
  void _openOriginPicker() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              final q = controller.text.trim();
              final results = q.isEmpty
                  ? EtusDatabase.stops.values
                      .take(30)
                      .map((s) => SmartSearchResult(
                          stop: s,
                          score: 0,
                          matchedReason: 'Durak'))
                      .toList()
                  : SmartSearchService.search(q);
              return SizedBox(
                height: 520,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Kalkış Noktası Seç',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Kalkış durağı ara (örn: sarayiçi)...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.my_location, color: Colors.green),
                      title: const Text('GPS konumum (otomatik)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(_userLocation?.label ?? 'Konum alınıyor...'),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _customOrigin = null);
                        _calculateJourneys();
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        children: results.take(25).map((r) {
                          return ListTile(
                            leading: const Icon(Icons.trip_origin,
                                color: Colors.green),
                            title: Text(r.stop.name,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(r.matchedReason,
                                style: const TextStyle(fontSize: 11)),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() => _customOrigin = r.stop);
                              _calculateJourneys();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.directions_bus, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'ETUS Asistanı',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Edirne',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Akıllı Rota & Google Maps',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapScreen(
                    initialLat: _userLocation?.latitude,
                    initialLng: _userLocation?.longitude,
                  ),
                ),
              );
            },
            icon: Icon(Icons.map, color: Colors.blue.shade700),
            tooltip: 'Haritayı Aç (OpenStreetMap)',
          ),
          IconButton(
            onPressed: _isLoadingLocation ? null : _fetchLocation,
            icon: _isLoadingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.my_location, color: Colors.blue.shade700),
            tooltip: 'GPS Konumunu Güncelle',
          ),
        ],
      ),
      floatingActionButton: _selectedDestination == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      initialLat: _userLocation?.latitude,
                      initialLng: _userLocation?.longitude,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('Haritada Gör'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 0. CANLI VERİ SAĞLIĞI — sorun varsa görünür uyarı çıkar.
            _buildHealthSection(),

            // 1. MEVCUT KONUM GÖSTERGE KARTI
            _buildLocationCard(),

            const SizedBox(height: 16),

            // 2. AKILLI HEDEF ARAMA KUTUSU (Semantik NLP Destekli)
            _buildSearchBox(),

            // 3. ANLIK AKILLI ÖNERİ LİSTESİ (yerel + gerçek harita yerleri)
            if (_smartSuggestions.isNotEmpty ||
                _osmSuggestions.isNotEmpty ||
                _osmLoading ||
                _searchController.text.trim().length >= 3)
              _buildSuggestionsList(),

            const SizedBox(height: 14),

            // 4. HIZLI SEÇİM KISAYOLLARI
            _buildQuickShortcuts(),

            const SizedBox(height: 20),

            // 5. ANLAŞILAN HEDEF BİLGİLENDİRME ROZETİ
            if (_selectedDestination != null) _buildSelectedDestinationBanner(),

            const SizedBox(height: 16),

            // 6. ROTA VE OTOBÜS SONUÇLARI
            _buildResultsSection(),
          ],
        ),
      ),
    );
  }

  /// Canlı veri sağlığı uyarısı. Sorun yoksa hiç yer kaplamaz.
  Widget _buildHealthSection() {
    return ListenableBuilder(
      listenable: KentkartHealth.instance,
      builder: (context, _) {
        if (KentkartHealth.instance.userMessage == null) {
          return const SizedBox.shrink();
        }
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: KentkartStatusBanner(),
        );
      },
    );
  }

  /// Mevcut Konum Kartı (kalkış noktası — elle değiştirilebilir)
  Widget _buildLocationCard() {
    final loc = _userLocation;
    final origin = _originStop;
    final isCustom = _customOrigin != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isCustom ? Colors.green.shade300 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'KALKIŞ NOKTANIZ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade500,
                ),
              ),
              TextButton.icon(
                onPressed: _openOriginPicker,
                icon: const Icon(Icons.edit_location_alt, size: 14),
                label: Text(isCustom ? 'Değiştir' : 'GPS • Değiştir'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(isCustom ? Icons.trip_origin : Icons.location_on,
                  size: 16,
                  color: isCustom ? Colors.green.shade700 : Colors.blue.shade700),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isCustom
                      ? origin.name
                      : (loc?.label ?? 'Konum belirleniyor...'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                const Text('🚶 Biniş durağı: ',
                    style: TextStyle(fontSize: 11, color: Colors.black87)),
                Expanded(
                  child: Text(
                    origin.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isCustom
                        ? (loc != null
                            ? '${origin.distanceTo(loc.latitude, loc.longitude)}m'
                            : 'seçili')
                        : '${loc?.distanceToStopMeters ?? 0}m',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Akıllı Arama Input Alanı
  Widget _buildSearchBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _executeSearch(),
        decoration: InputDecoration(
          hintText: 'Nereye? Durak, adres veya yer yazın (örn: Meriç Köprüsü)...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, color: Colors.blue.shade700),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.blue),
            onPressed: _executeSearch,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  /// Akıllı Öneri Listesi (Canlı Algılama)
  ///
  /// Üstte güvenilir yerel duraklar, altta gerçek harita yerleri (OSM).
  /// Eşleşme yoksa boş liste yerine "haritada ara" önerisi çıkar.
  Widget _buildSuggestionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._smartSuggestions.take(4).map((item) {
            return ListTile(
              dense: true,
              leading: Icon(
                item.score >= 85 ? Icons.auto_awesome : Icons.place,
                color:
                    item.score >= 85 ? Colors.amber.shade700 : Colors.blue,
                size: 20,
              ),
              title: Text(
                item.stop.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                '${item.matchedReason} (%${item.score.round()})',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () =>
                  _selectDestination(item.stop, item.matchedReason),
            );
          }),
          if (_osmLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Haritada gerçek yer aranıyor...',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          for (final p in _osmSuggestions.take(3))
            ListTile(
              dense: true,
              leading:
                  const Icon(Icons.travel_explore, color: Colors.teal, size: 20),
              title: Text(
                p.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                'Harita konumu • dokun: otobüs önerisi',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              trailing: const Icon(Icons.map, size: 18),
              onTap: () => _openPlaceOnMap(p),
            ),
          if (_smartSuggestions.isEmpty &&
              !_osmLoading &&
              _searchController.text.trim().length >= 3)
            ListTile(
              dense: true,
              leading:
                  const Icon(Icons.map_outlined, color: Colors.green, size: 20),
              title: const Text(
                'Haritada ara',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: const Text(
                'Kayıtlı durak yoksa gerçek konumu haritada bulup otobüs önerisi alın',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                final q = _searchController.text.trim();
                if (q.isEmpty) return;
                if (_osmSuggestions.isNotEmpty) {
                  _openPlaceOnMap(_osmSuggestions.first);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapScreen(
                        initialLat: _userLocation?.latitude,
                        initialLng: _userLocation?.longitude,
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  /// Hızlı Lokasyon Kısayolları
  Widget _buildQuickShortcuts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'POPÜLER YERLER',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            QuickChip(
              label: 'Erasta AVM',
              iconEmoji: '🛍️',
              onTap: () => _selectDestination(
                EtusDatabase.stops['D_ERASTA']!,
                'Erasta AVM Kısayolu',
              ),
            ),
            QuickChip(
              label: 'Tıp Fakültesi',
              iconEmoji: '🎓',
              onTap: () => _selectDestination(
                EtusDatabase.stops['D_BALKAN_KAMPUS']!,
                'Balkan Kampüsü / Tıp Kısayolu',
              ),
            ),
            QuickChip(
              label: 'Otogar',
              iconEmoji: '🚌',
              onTap: () => _selectDestination(
                EtusDatabase.stops['D_OTOGAR']!,
                'Edirne Otogarı Kısayolu',
              ),
            ),
            QuickChip(
              label: 'Devlet Hastanesi',
              iconEmoji: '🏥',
              onTap: () => _selectDestination(
                EtusDatabase.stops['D_DEVLET_HASTANESI']!,
                'Sultan 1. Murat Hastanesi Kısayolu',
              ),
            ),
            QuickChip(
              label: 'Karaağaç',
              iconEmoji: '☕',
              onTap: () => _selectDestination(
                EtusDatabase.stops['D_KARAAĞAC']!,
                'Karaağaç Tren Garı Kısayolu',
              ),
            ),
            QuickChip(
              label: 'Selimiye',
              iconEmoji: '🕌',
              onTap: () => _selectDestination(
                EtusDatabase.stops['D_SELIMIYE']!,
                'Selimiye Camii Kısayolu',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Seçilen ve Algılanan Hedef Bildirimi
  Widget _buildSelectedDestinationBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hedef: ${_selectedDestination!.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (_selectedMatchReason != null)
                  Text(
                    _selectedMatchReason!,
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Yolculuk Sonuçları Bölümü
  Widget _buildResultsSection() {
    if (_selectedDestination == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.directions, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nereye Gitmek İstiyorsunuz?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Arama kutusuna gitmek istediğiniz yeri yazın. Tam adını bilmeseniz bile uygulama nereye gitmek istediğinizi anlar ve uygun ETUS otobüslerini listeler.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (_journeyOptions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade200),
        ),          child: Column(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber, size: 32),
              const SizedBox(height: 8),
              const Text(
                'Hat Bulunamadı',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${_selectedDestination!.name} için bu saatte planlanabilir bir yolculuk bulunamadı. Google Maps ile canlı toplu taşıma tarifesi görebilirsiniz.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                if (_userLocation != null && _selectedDestination != null) {
                  LocationService.launchGoogleMapsTransit(
                    originLat: _userLocation!.latitude,
                    originLng: _userLocation!.longitude,
                    destLat: _selectedDestination!.latitude,
                    destLng: _selectedDestination!.longitude,
                  );
                }
              },
              icon: const Icon(Icons.navigation, size: 16),
              label: const Text('Google Maps ile Canlı Aç'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'YOLCULUK ÖNERİLERİ (${_journeyOptions.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(
                '${_journeyOptions.where((j) => j.isDirect).length} doğrudan • ${_journeyOptions.where((j) => !j.isDirect).length} aktarmalı',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._journeyOptions.map((journey) {
          return RouteCard(
            journey: journey,
            originStop: _originStop,
            destinationStop: _selectedDestination!,
            userLat: _userLocation?.latitude ?? _originStop.latitude,
            userLng: _userLocation?.longitude ?? _originStop.longitude,
          );
        }),
      ],
    );
  }
}
