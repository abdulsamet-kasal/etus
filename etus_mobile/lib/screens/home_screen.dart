import 'package:flutter/material.dart';
import '../models/stop.dart';
import '../models/route_line.dart';
import '../data/etus_data.dart';
import '../services/smart_search_service.dart';
import '../services/location_service.dart';
import '../services/journey_service.dart';
import '../widgets/quick_chip.dart';
import '../widgets/route_card.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _smartSuggestions = [];
      });
      return;
    }

    final results = SmartSearchService.search(query);
    setState(() {
      _smartSuggestions = results;
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
  void _executeSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen gitmek istediğiniz yeri yazın.')),
      );
      return;
    }

    final results = SmartSearchService.search(query);
    if (results.isNotEmpty) {
      final top = results.first;
      _selectDestination(top.stop, top.matchedReason);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$query" için uygun bir yer veya durak anlaşılamadı.')),
      );
    }
  }

  /// ETUS Hatlarını ve Yolculuk Seçeneklerini Hesapla (doğrudan + aktarmalı)
  void _calculateJourneys() {
    if (_userLocation == null || _selectedDestination == null) return;

    final originStop = _userLocation!.nearestStop;
    final destStop = _selectedDestination!;

    if (originStop.id == destStop.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zaten gitmek istediğiniz durağın çok yakınındasınız!')),
      );
      return;
    }

    final options = JourneyService.findJourneys(
      originPlace: originStop,
      destinationPlace: destStop,
      walkMeters: _userLocation!.distanceToStopMeters,
      maxResults: 6,
    );

    setState(() {
      _journeyOptions = options;
    });
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. MEVCUT KONUM GÖSTERGE KARTI
            _buildLocationCard(),

            const SizedBox(height: 16),

            // 2. AKILLI HEDEF ARAMA KUTUSU (Semantik NLP Destekli)
            _buildSearchBox(),

            // 3. ANLIK AKILLI ÖNERİ LİSTESİ (Kullanıcı Yazarken)
            if (_smartSuggestions.isNotEmpty) _buildSuggestionsList(),

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

  /// Mevcut Konum Kartı
  Widget _buildLocationCard() {
    final loc = _userLocation;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
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
                'MEVCUT KONUMUNUZ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade500,
                ),
              ),
              if (_isLoadingLocation)
                Text(
                  'GPS alınıyor...',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  loc?.label ?? 'Konum belirleniyor...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          if (loc != null) ...[
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
                  const Text('🚶 En yakın durak: ', style: TextStyle(fontSize: 11, color: Colors.black87)),
                  Expanded(
                    child: Text(
                      loc.nearestStop.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${loc.distanceToStopMeters}m',
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
          hintText: 'Nereye gitmek istiyorsunuz? (Örn: hastane, avm, tip, uni...)',
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
        children: _smartSuggestions.take(4).map((item) {
          return ListTile(
            dense: true,
            leading: Icon(
              item.score >= 85 ? Icons.auto_awesome : Icons.place,
              color: item.score >= 85 ? Colors.amber.shade700 : Colors.blue,
              size: 20,
            ),
            title: Text(
              item.stop.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              '${item.matchedReason} (%${item.score.round()})',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _selectDestination(item.stop, item.matchedReason),
          );
        }).toList(),
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
            originStop: _userLocation!.nearestStop,
            destinationStop: _selectedDestination!,
            userLat: _userLocation!.latitude,
            userLng: _userLocation!.longitude,
          );
        }),
      ],
    );
  }
}
