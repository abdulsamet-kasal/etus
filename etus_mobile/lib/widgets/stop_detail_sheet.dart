import 'dart:async';

import 'package:flutter/material.dart';

import '../services/kentkart_api.dart';
import 'kentkart_status_banner.dart';

/// Bir durağa dokunulduğunda açılan detay sayfası:
/// o duraktan geçen hatlar + yaklaşan canlı otobüsler.
///
/// Haritadan bağımsız çalışır; bu sayede hem haritada hem (istenirse) durak
/// listesinde kullanılabilir ve tek başına test edilebilir.
class StopDetailSheet extends StatefulWidget {
  final KentkartStop stop;

  /// Durağı kalkış olarak ayarla (sheet kapanır).
  final VoidCallback onSetOrigin;

  /// Durağı varış olarak ayarla (sheet kapanır).
  final VoidCallback onSetDestination;

  /// Bu durağa navigasyon başlat (sheet kapanır).
  final VoidCallback onNavigate;

  /// Canlı verinin otomatik yenilenme aralığı. `null` verilirse otomatik
  /// yenileme kapanır (testler için).
  final Duration? refreshInterval;

  const StopDetailSheet({
    super.key,
    required this.stop,
    required this.onSetOrigin,
    required this.onSetDestination,
    required this.onNavigate,
    this.refreshInterval = const Duration(seconds: 15),
  });

  @override
  State<StopDetailSheet> createState() => _StopDetailSheetState();
}

class _StopDetailSheetState extends State<StopDetailSheet> {
  KentkartStopDetail? _detail;
  bool _loading = true;
  String? _error;
  DateTime? _updatedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    final interval = widget.refreshInterval;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final detail = await KentkartApi.fetchStopDetail(
        stopId: widget.stop.stopId,
        lat: widget.stop.lat,
        lng: widget.stop.lng,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _error = null;
        _updatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      // Hatayı KentkartApi zaten KentkartHealth'e kaydetti; burada kullanıcıya
      // gösteriyoruz ki "veri yok" ile "veri bozuk" ayırt edilebilsin.
      setState(() => _error = 'Durak bilgisi alınamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _updatedLabel {
    final at = _updatedAt;
    if (at == null) return '';
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Color _colorOf(String hex) {
    final clean = hex.length == 6 ? hex : '1D4ED8';
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildHeader(detail),
              const SizedBox(height: 8),
              const KentkartStatusBanner(),
              if (_error != null) _buildError(),
              const SizedBox(height: 4),
              _sectionTitle('BU DURAKTAN GEÇEN HATLAR',
                  detail == null ? null : '${detail.lines.length}'),
              const SizedBox(height: 6),
              ..._buildLines(detail),
              const SizedBox(height: 14),
              _sectionTitle('YAKLAŞAN CANLI OTOBÜSLER',
                  detail == null ? null : '${detail.buses.length}'),
              const SizedBox(height: 6),
              ..._buildBuses(detail),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onSetOrigin,
                      icon: const Icon(Icons.trip_origin, size: 16),
                      label: const Text('Kalkış yap'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: Colors.green.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onSetDestination,
                      icon: const Icon(Icons.place, size: 16),
                      label: const Text('Varış yap'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: widget.onNavigate,
                icon: const Icon(Icons.navigation, size: 18),
                label: const Text('Bu durağa navigasyon başlat'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(KentkartStopDetail? detail) {
    return Row(
      children: [
        const Icon(Icons.location_on, color: Colors.indigo, size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail?.name ?? widget.stop.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'Durak no: ${widget.stop.stopId}'
                '${_updatedLabel.isEmpty ? '' : ' • Son güncelleme: $_updatedLabel'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (_loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            tooltip: 'Yenile',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh, size: 20),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: const TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLines(KentkartStopDetail? detail) {
    if (detail == null) {
      return [
        Text(
          _loading ? 'Hatlar yükleniyor...' : 'Hat bilgisi yok.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ];
    }
    if (detail.lines.isEmpty) {
      return [
        Text('Bu durak için hat kaydı bulunamadı.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ];
    }
    return detail.lines.map(_lineRow).toList();
  }

  List<Widget> _buildBuses(KentkartStopDetail? detail) {
    if (detail == null) {
      return [
        Text(
          _loading ? 'Otobüsler sorgulanıyor...' : '-',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ];
    }
    if (detail.buses.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Şu an bu durağa yaklaşan otobüs bildirilmiyor. '
                  'Sefer saatlerine bakmayı deneyin.',
                  style:
                      TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return detail.buses.map(_busRow).toList();
  }

  Widget _sectionTitle(String text, String? count) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              count,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _lineRow(KentkartStopLine line) {
    final color = _colorOf(line.colorHex);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 38),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              line.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.headSigns.isEmpty
                  ? 'Yön bilgisi yok'
                  : line.headSigns.join('  ·  '),
              style: const TextStyle(fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _busRow(KentkartLiveBus bus) {
    final color = _colorOf(bus.colorHex);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child:
                const Icon(Icons.directions_bus, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${bus.lineCode}  •  ${bus.headSign}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${bus.plate.isEmpty ? 'Plaka yok' : bus.plate} • ${bus.stopsAway} durak uzakta',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Text(
              '${bus.minutesAway} dk',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.green.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
