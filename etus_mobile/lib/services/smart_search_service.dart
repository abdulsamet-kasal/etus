import 'dart:math';
import '../data/etus_data.dart';
import '../models/stop.dart';

/// Akıllı Arama Sonucu ve Eşleşme Gerekçesi
class SmartSearchResult {
  final Stop stop;
  final double score; // 0 - 100 arası benzerlik puanı
  final String matchedReason; // Kullanıcıya gösterilen açıklama (Örn: "Alışveriş / Sinema niyetiyle eşleşti")

  const SmartSearchResult({
    required this.stop,
    required this.score,
    required this.matchedReason,
  });
}

/// Kullanıcının Eksik/Hatalı Girdilerini ve Niyetlerini Anlayan Akıllı Motor
class SmartSearchService {
  /// Türkçe Karakterleri Normalize Etme (Arama toleransı için)
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();
  }

  /// Levenshtein Mesafesi (Yazım hatalarını yakalamak için)
  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  /// Benzerlik Oranı (0.0 - 1.0)
  static double _similarity(String s1, String s2) {
    int maxLen = max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    int dist = _levenshtein(s1, s2);
    return 1.0 - (dist / maxLen);
  }

  /// Genel Semantik Niyet Sözlüğü (Kullanıcı durak adı bilmese bile ne yapmak istediğini anlar)
  static final Map<String, List<String>> _intentCategories = {
    'avm': [
      'avm', 'alisveris', 'magaza', 'sinema', 'lcw', 'lcwaikiki', 'burger',
      'yemek ye', 'kahve', 'starbucks', 'kiyafet', 'market', 'migros'
    ],
    'hastane': [
      'doktor', 'hastane', 'hasta', 'muayene', 'tedavi', 'ilac', 'recete',
      'saglik', 'acil', 'poliklinik', 'randevu', 'rontgen', 'tahlil', 'hemsire'
    ],
    'universite': [
      'uni', 'universite', 'kampus', 'ogrenci', 'fakulte', 'ders', 'vize',
      'final', 'amfi', 'rektorluk', 'iibf', 'balkan', 'trakya uni', 'tip'
    ],
    'ulasim': [
      'otobus', 'otobusler', 'terminal', 'otogar', 'bilet', 'yolculuk',
      'sehir disi', 'metro turizm', 'pamukkale', 'kamil koc'
    ],
    'gezi_kafe': [
      'cay', 'kahve', 'kafe', 'kahvalti', 'dondurma', 'lozan', 'nehir',
      'meric', 'tarihi', 'kopru', 'tren gari', 'gezme', 'hava alma'
    ],
    'ibadet_tarih': [
      'cami', 'namaz', 'cuma', 'selimiye', 'mimar sinan', 'dua', 'muze',
      'kulliye', 'darussifa', 'tarihi yer'
    ],
  };

  /// Kullanıcının Girdisini Akıllıca Analiz Et
  static List<SmartSearchResult> search(String query) {
    final cleanQuery = normalize(query);
    if (cleanQuery.isEmpty) return [];

    final List<SmartSearchResult> results = [];
    final userTokens = cleanQuery.split(RegExp(r'\s+'));

    // 1. Aşama: Semantik Niyet Kontrolü
    String? detectedIntent;
    for (var entry in _intentCategories.entries) {
      for (var keyword in entry.value) {
        if (cleanQuery.contains(keyword) || _similarity(cleanQuery, keyword) > 0.8) {
          detectedIntent = entry.key;
          break;
        }
      }
      if (detectedIntent != null) break;
    }

    // 2. Aşama: Tüm Durakları Puanla
    for (var stop in EtusDatabase.stops.values) {
      double bestScore = 0.0;
      String matchReason = 'İsim benzerliği';

      final cleanStopName = normalize(stop.name);

      // A) Tam İsim Eşleşmesi
      if (cleanStopName.contains(cleanQuery)) {
        bestScore = max(bestScore, 95.0);
        matchReason = 'Doğrudan durak adı eşleşmesi';
      }

      // B) Eşanlamlılar ve Takma Adlar (Aliases)
      for (var alias in stop.aliases) {
        final cleanAlias = normalize(alias);

        if (cleanAlias == cleanQuery) {
          bestScore = max(bestScore, 100.0);
          matchReason = 'Tam lokasyon eşleşmesi: "${alias}"';
          break;
        } else if (cleanAlias.contains(cleanQuery) || cleanQuery.contains(cleanAlias)) {
          bestScore = max(bestScore, 88.0);
          matchReason = 'Kapsam eşleşmesi: "${alias}"';
        } else {
          // Yazım hatası toleransı (Fuzzy matching)
          final sim = _similarity(cleanQuery, cleanAlias);
          if (sim > 0.72) {
            double fuzzyScore = sim * 85.0;
            if (fuzzyScore > bestScore) {
              bestScore = fuzzyScore;
              matchReason = 'Yazım hatası düzeltildi ("${alias}" kast edilmiş olabilir)';
            }
          }
        }
      }

      // C) Kullanıcı Tokenları ile Kısmi Eşleşme (Örn: "tip uni" -> Tıp Fakültesi)
      for (var token in userTokens) {
        if (token.length < 2) continue;
        for (var alias in stop.aliases) {
          if (normalize(alias).contains(token)) {
            bestScore = max(bestScore, 75.0);
            matchReason = 'Kelime eşleşmesi: "$token"';
          }
        }
      }

      // D) Tespit edilen genel niyetle kategori eşleştirmesi
      if (detectedIntent != null) {
        if (detectedIntent == 'avm' && stop.category == 'avm') {
          bestScore = max(bestScore, 85.0);
          matchReason = '💡 Alışveriş / Sinema / AVM niyeti algılandı';
        } else if (detectedIntent == 'hastane' && stop.category == 'hastane') {
          bestScore = max(bestScore, 90.0);
          matchReason = '💡 Sağlık / Doktor / Hastane niyeti algılandı';
        } else if (detectedIntent == 'universite' && stop.category == 'universite') {
          bestScore = max(bestScore, 85.0);
          matchReason = '💡 Kampüs / Üniversite niyeti algılandı';
        } else if (detectedIntent == 'ulasim' && stop.category == 'ulasim') {
          bestScore = max(bestScore, 90.0);
          matchReason = '💡 Şehirlerarası Seyahat / Otogar niyeti algılandı';
        } else if (detectedIntent == 'gezi_kafe' && (stop.id == 'D_KARAAĞAC' || stop.id == 'D_GAZIMIHAL')) {
          bestScore = max(bestScore, 85.0);
          matchReason = '💡 Çay bahçesi / Nehir kıyısı / Gezi niyeti algılandı';
        } else if (detectedIntent == 'ibadet_tarih' && (stop.id == 'D_SELIMIYE' || stop.id == 'D_BAYEZID_KULLIYE')) {
          bestScore = max(bestScore, 85.0);
          matchReason = '💡 Cami / Tarihi Külliye ziyareti algılandı';
        }
      }

      if (bestScore >= 50.0) {
        results.add(SmartSearchResult(
          stop: stop,
          score: bestScore,
          matchedReason: matchReason,
        ));
      }
    }

    // Skora göre azalan sıralama (En yüksek eşleşme başta)
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
}
