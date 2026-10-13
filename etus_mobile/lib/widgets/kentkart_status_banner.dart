import 'package:flutter/material.dart';

import '../services/kentkart_health.dart';

/// Kentkart canlı verisinde sorun varsa **görünür** uyarı gösterir.
///
/// Uygulama canlı veriye ulaşamadığında yerleşik `etus_data.dart` verisine
/// düşüyor; bu banner sayesinde kullanıcı eski veriyle yolculuk planladığını
/// fark eder. Sağlık durumu sorunsuzsa hiçbir şey çizilmez.
class KentkartStatusBanner extends StatefulWidget {
  /// Testlerde/önizlemede farklı bir sağlık nesnesi verilebilir.
  final KentkartHealth? health;

  /// Ayrıntı listesini başlangıçta açık göster.
  final bool initiallyExpanded;

  const KentkartStatusBanner({
    super.key,
    this.health,
    this.initiallyExpanded = false,
  });

  @override
  State<KentkartStatusBanner> createState() => _KentkartStatusBannerState();
}

class _KentkartStatusBannerState extends State<KentkartStatusBanner> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final health = widget.health ?? KentkartHealth.instance;

    return ListenableBuilder(
      listenable: health,
      builder: (context, _) {
        final message = health.userMessage;
        if (message == null) return const SizedBox.shrink();

        final isDown = health.status == KentkartStatus.down;
        final isDrift = health.hasSchemaDrift;
        final accent = isDown
            ? Colors.red.shade700
            : (isDrift ? Colors.deepOrange.shade700 : Colors.orange.shade800);
        final icon = isDown
            ? Icons.cloud_off
            : (isDrift ? Icons.schema_outlined : Icons.sync_problem);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: isDown ? Colors.red.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          health.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (health.issues.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                    label: Text(
                      _expanded
                          ? 'Ayrıntıları gizle'
                          : 'Ayrıntılar (${health.issues.length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: health.issues.take(6).map((issue) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• [${issue.label}] ${issue.message}',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: Colors.grey.shade800,
                          ),
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
  }
}
