import '../models/stop.dart';
import '../models/route_line.dart';

/// Edirne ETUS Durakları ve Hatları Gerçek Veritabanı
class EtusDatabase {
  // Tüm Edirne Durakları ve Semantik Anahtar Kelimeleri
  static final Map<String, Stop> stops = {
    'D_SARACLAR': const Stop(
      id: 'D_SARACLAR',
      name: 'Saraçlar Caddesi / Bankalar',
      latitude: 41.6752,
      longitude: 26.5548,
      category: 'meydan',
      description: 'Edirne Merkez, Çarşı, Bankalar ve Trafiğe Kapalı Cadde',
      aliases: [
        'saraclar', 'çarşı', 'carsi', 'merkez', 'sehir merkezi', 'bankalar',
        'ziraat', 'is bankasi', 'belediye', 'eski cami alti', 'meydan',
        'alisveris caddesi', 'trafiğe kapalı'
      ],
    ),
    'D_ERASTA': const Stop(
      id: 'D_ERASTA',
      name: 'Erasta AVM',
      latitude: 41.6662,
      longitude: 26.5684,
      category: 'avm',
      description: 'Talatpaşa Bulvarı, Erasta Alışveriş Merkezi',
      aliases: [
        'erasta', 'erasta avm', 'avm', 'alisveris', 'sinema', 'lcw',
        'burger', 'starbucks', 'magazalar', 'avmye', 'erastaya', 'avm gitmek'
      ],
    ),
    'D_BALKAN_KAMPUS': const Stop(
      id: 'D_BALKAN_KAMPUS',
      name: 'Trakya Üni. Balkan Yerleşkesi (Tıp Fakültesi / Rektörlük)',
      latitude: 41.6425,
      longitude: 26.6212,
      category: 'universite',
      description: 'Trakya Üniversitesi Ana Balkan Kampüsü, Tıp Fakültesi ve Hastanesi',
      aliases: [
        'balkan', 'balkan yerleskesi', 'tıp', 'tip', 'tip fakultesi', 'trakya tip',
        'universite', 'uni', 'rektorluk', 'kampus', 'kongre merkezi', 'ogrenci isleri',
        'saglik bilimleri', 'muhendislik', 'fen fakultesi', 'trakya universitesi'
      ],
    ),
    'D_DEVLET_HASTANESI': const Stop(
      id: 'D_DEVLET_HASTANESI',
      name: 'Sultan 1. Murat Devlet Hastanesi',
      latitude: 41.6688,
      longitude: 26.5955,
      category: 'hastane',
      description: 'Edirne Sultan 1. Murat Devlet Hastanesi Ana Kapı',
      aliases: [
        'devlet hastanesi', 'hastane', '1 murat', 'murat devlet', 'doktor',
        'muayene', 'acil', 'poliklinik', 'saglik', 'tedavi', 'hastaneye'
      ],
    ),
    'D_OTOGAR': const Stop(
      id: 'D_OTOGAR',
      name: 'Edirne Şehirlerarası Otobüs Terminali (Otogar)',
      latitude: 41.6372,
      longitude: 26.6342,
      category: 'ulasim',
      description: 'Edirne Otobüs Terminali Ana Girişi',
      aliases: [
        'otogar', 'terminal', 'otobusler', 'sehirlerarasi', 'bilet',
        'yolculuk', 'metro', 'pamukkale', 'kamil koc', 'kale', 'otogara'
      ],
    ),
    'D_KARAAĞAC': const Stop(
      id: 'D_KARAAĞAC',
      name: 'Karaağaç Meydanı / Tren Garı (Güzel Sanatlar)',
      latitude: 41.6522,
      longitude: 26.5255,
      category: 'tarihi',
      description: 'Tarihi Tren Garı, Rektörlük Güzel Sanatlar Kampüsü & Kafeler',
      aliases: [
        'karaagac', 'karaağaç', 'tren gari', 'gar', 'guzel sanatlar', 'lozan',
        'lozan aniti', 'kahvalti', 'kafe', 'cay bahcesi', 'meric otesi'
      ],
    ),
    'D_SELIMIYE': const Stop(
      id: 'D_SELIMIYE',
      name: 'Selimiye Camii / Eski Cami',
      latitude: 41.6780,
      longitude: 26.5589,
      category: 'tarihi',
      description: 'Mimar Sinan Selimiye Camii ve Meydan Parkı',
      aliases: [
        'selimiye', 'eski cami', 'cami', 'mimar sinan', 'arasta', 'namaz',
        'tarihi meydan', 'uc serefeli', 'selimiyeye', 'sinan'
      ],
    ),
    'D_AYSEKADIN': const Stop(
      id: 'D_AYSEKADIN',
      name: 'Ayşekadın Yerleşkesi / Karakol',
      latitude: 41.6602,
      longitude: 26.5821,
      category: 'universite',
      description: 'Trakya Üniversitesi İktisadi ve İdari Bilimler Fakültesi',
      aliases: [
        'aysekadin', 'ayşekadın', 'iibf', 'aysekadin kampus', 'fakulte',
        'karakol', 'aysekadin karakolu', 'yurtlar bolgesi'
      ],
    ),
    'D_MARGI': const Stop(
      id: 'D_MARGI',
      name: 'Margi Outlet / Migros',
      latitude: 41.6644,
      longitude: 26.5714,
      category: 'avm',
      description: 'Margi Outlet Alışveriş Merkezi ve İstasyon Oteller Mevkii',
      aliases: [
        'margi', 'margi outlet', 'migros', 'istasyon', 'outlet', 'otel',
        'margiye', 'sinema margi'
      ],
    ),
    'D_SUKRUPASA_GOLET': const Stop(
      id: 'D_SUKRUPASA_GOLET',
      name: 'Şükrüpaşa Gölet Parkı',
      latitude: 41.6723,
      longitude: 26.5848,
      category: 'meydan',
      description: 'Şükrüpaşa Gölet Mevkii, Yürüyüş Yolu ve Dinlenme Alanı',
      aliases: [
        'sukrupasa', 'şükrüpaşa', 'golet', 'gölet', 'baris parki', 'park',
        'yuruyus', 'kafeterya golet'
      ],
    ),
    'D_GAZIMIHAL': const Stop(
      id: 'D_GAZIMIHAL',
      name: 'Gazimihal Hareket Merkezi',
      latitude: 41.6756,
      longitude: 26.5412,
      category: 'ulasim',
      description: 'Gazimihal Otobüs Hareket Noktası ve Tunca/Meriç Kıyısı',
      aliases: [
        'gazimihal', 'meric', 'kopru', 'kaleici', 'kaleici bati',
        'tarihi kopru', 'gazimihale'
      ],
    ),
    'D_KIYIK': const Stop(
      id: 'D_KIYIK',
      name: 'Kıyık Caddesi / Çarşı',
      latitude: 41.6853,
      longitude: 26.5702,
      category: 'meydan',
      description: 'Tarihi Kıyık Caddesi ve Tepe Mevkii',
      aliases: [
        'kiyik', 'kıyık', 'kiyik caddesi', 'kiyik carsi', 'bucuktepe', 'kiyiga'
      ],
    ),
    'D_BAYEZID_KULLIYE': const Stop(
      id: 'D_BAYEZID_KULLIYE',
      name: 'II. Bayezid Külliyesi (Sağlık Müzesi)',
      latitude: 41.6865,
      longitude: 26.5414,
      category: 'tarihi',
      description: 'Sultan II. Bayezid Külliyesi, Tarihi Darüşşifa ve Sağlık Müzesi',
      aliases: [
        'kulliye', 'külliye', 'saglik muzesi', 'darussifa', 'darüşşifa',
        'bayezid', '2 bayezid', 'yildirim', 'muze'
      ],
    ),
    'D_SARAYICI': const Stop(
      id: 'D_SARAYICI',
      name: 'Sarayiçi (Kırkpınar Er Meydanı / Saray)',
      latitude: 41.6912,
      longitude: 26.5562,
      category: 'tarihi',
      description: 'Tarihi Kırkpınar Güreş Alanı ve Edirne Sarayı Kalıntıları',
      aliases: [
        'sarayici', 'sarayiçi', 'kirkpinar', 'kırkpınar', 'er meydani',
        'gures', 'güreş', 'edirne sarayi', 'tavuk ormani'
      ],
    ),
    'D_KYK_YURTLAR': const Stop(
      id: 'D_KYK_YURTLAR',
      name: 'Sultan Çelebi Mehmet KYK Yurdu / TOKİ',
      latitude: 41.6892,
      longitude: 26.5880,
      category: 'universite',
      description: 'Fırınlarsırtı TOKİ ve KYK Öğrenci Yurtları Bölgesi',
      aliases: [
        'kyk', 'yurt', 'yurtlar', 'celebi mehmet', 'ogrenci yurdu',
        'firinlarsirti', 'toki', 'kiz yurdu', 'erkek yurdu'
      ],
    ),
    'D_ECZACILIK': const Stop(
      id: 'D_ECZACILIK',
      name: 'Eczacılık & Diş Hekimliği Fakültesi',
      latitude: 41.6441,
      longitude: 26.6178,
      category: 'universite',
      description: 'Balkan Yerleşkesi Diş Hekimliği ve Eczacılık Bölümü',
      aliases: [
        'eczacilik', 'dis', 'diş', 'dis hekimligi', 'dis hastanesi',
        'eczacilik fakultesi'
      ],
    ),
  };

  // Gerçek ETUS Hatları
  static final List<RouteLine> routes = [
    const RouteLine(
      id: '3',
      name: 'Hat 3',
      title: 'Gazimihal - Saraçlar - Erasta - Devlet Hastanesi - Tıp Fakültesi - Otogar',
      description: 'Şehrin en popüler hattı. Çarşıdan AVM\'ye, Üniversiteye ve Otogara kesintisiz gider.',
      colorValue: 0xFF2563EB, // Mavi
      interval: '7-10 dk',
      stopIds: [
        'D_GAZIMIHAL',
        'D_SARACLAR',
        'D_ERASTA',
        'D_MARGI',
        'D_AYSEKADIN',
        'D_DEVLET_HASTANESI',
        'D_BALKAN_KAMPUS',
        'D_OTOGAR',
      ],
    ),
    const RouteLine(
      id: '1A',
      name: 'Hat 1A',
      title: 'Gazimihal - Saraçlar - Karaağaç (Güzel Sanatlar)',
      description: 'Merkezden Karaağaç çay bahçelerine ve Güzel Sanatlar kampüsüne giden ana hat.',
      colorValue: 0xFFDC2626, // Kırmızı
      interval: '10-15 dk',
      stopIds: [
        'D_GAZIMIHAL',
        'D_SARACLAR',
        'D_KARAAĞAC',
      ],
    ),
    const RouteLine(
      id: '1T',
      name: 'Hat 1T',
      title: 'Gazimihal - Saraçlar - Talatpaşa - Ayşekadın - Otogar (Ekspres)',
      description: 'Şehir merkezi ile Şehirlerarası Otogar arasında en hızlı ekspres hat.',
      colorValue: 0xFF7C3AED, // Mor
      interval: '12-15 dk',
      stopIds: [
        'D_GAZIMIHAL',
        'D_SARACLAR',
        'D_ERASTA',
        'D_AYSEKADIN',
        'D_OTOGAR',
      ],
    ),
    const RouteLine(
      id: '2A',
      name: 'Hat 2A',
      title: 'Şükrüpaşa - Devlet Hastanesi - Diş Hekimliği - Balkan Kampüsü - Otogar',
      description: 'Şükrüpaşa ve Gölet mahallelerini hastanelere ve üniversiteye bağlayan hat.',
      colorValue: 0xFF059669, // Yeşil
      interval: '15-20 dk',
      stopIds: [
        'D_SUKRUPASA_GOLET',
        'D_DEVLET_HASTANESI',
        'D_ECZACILIK',
        'D_BALKAN_KAMPUS',
        'D_OTOGAR',
      ],
    ),
    const RouteLine(
      id: '3A',
      name: 'Hat 3A',
      title: 'Sarayiçi - Selimiye - Saraçlar - Erasta - Tıp Fakültesi - Otogar',
      description: 'Sarayiçi Kırkpınar er meydanından başlayıp Selimiye ve Tıp Fakültesine gider.',
      colorValue: 0xFFD97706, // Amber
      interval: '15-20 dk',
      stopIds: [
        'D_SARAYICI',
        'D_SELIMIYE',
        'D_SARACLAR',
        'D_ERASTA',
        'D_AYSEKADIN',
        'D_BALKAN_KAMPUS',
        'D_OTOGAR',
      ],
    ),
    const RouteLine(
      id: '3C',
      name: 'Hat 3C',
      title: 'Karaağaç - Saraçlar - Erasta - Devlet Hastanesi - Otogar',
      description: 'Karaağaç bölgesinden doğrudan Devlet Hastanesine ve Otogara sefer yapar.',
      colorValue: 0xFFDB2777, // Pembe
      interval: '20-25 dk',
      stopIds: [
        'D_KARAAĞAC',
        'D_GAZIMIHAL',
        'D_SARACLAR',
        'D_ERASTA',
        'D_DEVLET_HASTANESI',
        'D_OTOGAR',
      ],
    ),
    const RouteLine(
      id: '5A',
      name: 'Hat 5A',
      title: 'Gazimihal - Kıyık - Şükrüpaşa Gölet - Devlet Hastanesi - Balkan Yerleşkesi - Otogar',
      description: 'Kıyık ve Gölet üzerinden Tıp Fakültesi ve Otogar aksını takip eder.',
      colorValue: 0xFF0891B2, // Cyan
      interval: '15-20 dk',
      stopIds: [
        'D_GAZIMIHAL',
        'D_SELIMIYE',
        'D_KIYIK',
        'D_SUKRUPASA_GOLET',
        'D_DEVLET_HASTANESI',
        'D_BALKAN_KAMPUS',
        'D_OTOGAR',
      ],
    ),
    const RouteLine(
      id: '5B',
      name: 'Hat 5B',
      title: 'KYK Yurtları (Çelebi Mehmet) - Selimiye - Saraçlar - Devlet Hastanesi',
      description: 'Fırınlarsırtı TOKİ ve KYK Yurtlarından Devlet Hastanesine ve Çarşıya ulaşım.',
      colorValue: 0xFF4F46E5, // İndigo
      interval: '15-20 dk',
      stopIds: [
        'D_KYK_YURTLAR',
        'D_KIYIK',
        'D_SELIMIYE',
        'D_SARACLAR',
        'D_DEVLET_HASTANESI',
      ],
    ),
    const RouteLine(
      id: '7E',
      name: 'Hat 7E',
      title: 'Sağlık Müzesi (Külliye) - Saraçlar - Erasta - Balkan Kampüsü - Otogar',
      description: 'Tarihi Sultan II. Bayezid Darüşşifasından Erasta ve Balkan Kampüsüne gider.',
      colorValue: 0xFFEA580C, // Turuncu
      interval: '20-30 dk',
      stopIds: [
        'D_BAYEZID_KULLIYE',
        'D_GAZIMIHAL',
        'D_SARACLAR',
        'D_ERASTA',
        'D_BALKAN_KAMPUS',
        'D_OTOGAR',
      ],
    ),
  ];
}
