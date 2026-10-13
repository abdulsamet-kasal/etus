/**
 * Edirne ETUS (Edirne Toplu Ulaşım Sistemi) Gerçek Hat ve Durak Verileri
 */

const ETUS_DATA = {
    // Edirne'deki Gerçek ETUS Durakları ve Önemli Noktalar
    stops: {
        "D_GAZIMIHAL": {
            id: "D_GAZIMIHAL",
            name: "Gazimihal Hareket Merkezi",
            aliases: ["gazimihal", "meriç", "köprü", "kaleiçi batı", "tarihi köprü"],
            coords: [41.6756, 26.5412],
            desc: "Gazimihal Otobüs Hareket Noktası & Nehir Kenarı"
        },
        "D_SARACLAR": {
            id: "D_SARACLAR",
            name: "Saraçlar Caddesi / Bankalar (Şehir Merkezi)",
            aliases: ["saraçlar", "çarşı", "merkez", "bankalar", "ziraat", "trafiğe kapalı", "belediye"],
            coords: [41.6752, 26.5548],
            desc: "Şehir Merkezi, Tarihi Çarşı ve Bankalar Mevkii"
        },
        "D_SELIMIYE": {
            id: "D_SELIMIYE",
            name: "Selimiye Camii / Eski Cami",
            aliases: ["selimiye", "eski cami", "üç şerefeli", "meydan", "tarihi cami", "arasta"],
            coords: [41.6780, 26.5589],
            desc: "Mimar Sinan Selimiye Camii Meydanı & Eski Cami"
        },
        "D_ORDUEVI": {
            id: "D_ORDUEVI",
            name: "Orduevi / Atatürk Anıtı",
            aliases: ["orduevi", "atatürk anıtı", "heykel", "fatih heykeli", "askeri gazino"],
            coords: [41.6728, 26.5583],
            desc: "Talatpaşa Bulvarı, Orduevi ve Anıt Kavşağı"
        },
        "D_ERASTA": {
            id: "D_ERASTA",
            name: "Erasta AVM",
            aliases: ["erasta", "erasta avm", "avm", "sinema", "lcw", "alışveriş"],
            coords: [41.6662, 26.5684],
            desc: "Talatpaşa Bulvarı, Erasta Alışveriş Merkezi Girişi"
        },
        "D_MARGI": {
            id: "D_MARGI",
            name: "Margi Outlet / Migros",
            aliases: ["margi", "outlet", "migros", "istasyon mevkii", "margi avm"],
            coords: [41.6644, 26.5714],
            desc: "Margi Alışveriş Alanı & Şehirlerarası Otobüs Yazıhaneleri"
        },
        "D_AYSEKADIN": {
            id: "D_AYSEKADIN",
            name: "Ayşekadın Yerleşkesi / Karakol",
            aliases: ["ayşekadın", "iibf", "fakülte", "ayşekadın kampüs", "trakya iibf", "karakol"],
            coords: [41.6602, 26.5821],
            desc: "Trakya Üniversitesi Ayşekadın Yerleşkesi & Ayşekadın Karakolu"
        },
        "D_DEVLET_HASTANESI": {
            id: "D_DEVLET_HASTANESI",
            name: "Sultan 1. Murat Devlet Hastanesi",
            aliases: ["devlet hastanesi", "hastane", "1. murat", "murat devlet", "sağlık", "poliklinik", "acil"],
            coords: [41.6688, 26.5955],
            desc: "Edirne Sultan 1. Murat Devlet Hastanesi Ana Kapı & Poliklinikler"
        },
        "D_SUKRUPASA_GOLET": {
            id: "D_SUKRUPASA_GOLET",
            name: "Şükrüpaşa Gölet Parkı",
            aliases: ["şükrüpaşa", "gölet", "şükrüpaşa mahallesi", "gölet parkı", "barış parkı"],
            coords: [41.6723, 26.5848],
            desc: "Şükrüpaşa Gölet Mevkii ve Sosyal Tesisler"
        },
        "D_KIYIK": {
            id: "D_KIYIK",
            name: "Kıyık Caddesi / Çarşı",
            aliases: ["kıyık", "kıyık caddesi", "kıyık tepe", "buçuktepe"],
            coords: [41.6853, 26.5702],
            desc: "Tarihi Kıyık Caddesi ve Çarşısı"
        },
        "D_BALKAN_KAMPUS": {
            id: "D_BALKAN_KAMPUS",
            name: "Trakya Üni. Balkan Yerleşkesi (Tıp Fakültesi / Rektörlük)",
            aliases: ["balkan yerleşkesi", "tıp fakültesi", "tıp", "rektörlük", "üniversite", "kongre merkezi", "trakya tıp", "kampüs"],
            coords: [41.6425, 26.6212],
            desc: "Trakya Üniversitesi Ana Balkan Kampüsü, Tıp Fakültesi & Hastanesi"
        },
        "D_ECZACILIK": {
            id: "D_ECZACILIK",
            name: "Eczacılık & Diş Hekimliği Fakültesi",
            aliases: ["eczacılık", "diş hekimliği", "diş fakültesi", "eczacılık fakültesi"],
            coords: [41.6441, 26.6178],
            desc: "Balkan Yerleşkesi Diş Hekimliği ve Eczacılık Blokları"
        },
        "D_OTOGAR": {
            id: "D_OTOGAR",
            name: "Edirne Şehirlerarası Otobüs Terminali (Otogar)",
            aliases: ["otogar", "terminal", "otobüs terminali", "şehirlerarası", "metro", "pamukkale", "kamil koç"],
            coords: [41.6372, 26.6342],
            desc: "Edirne Şehirlerarası Otobüs Terminali Ana Girişi"
        },
        "D_KARAAĞAC": {
            id: "D_KARAAĞAC",
            name: "Karaağaç Meydanı / Tren Garı (Güzel Sanatlar)",
            aliases: ["karaağaç", "tarihi tren garı", "tren garı", "güzel sanatlar", "lozan", "karaağaç merkez", "kafeteryalar"],
            coords: [41.6522, 26.5255],
            desc: "Tarihi Karaağaç Tren Garı, Rektörlük Güzel Sanatlar & Kafeler Bölgesi"
        },
        "D_SARAYICI": {
            id: "D_SARAYICI",
            name: "Sarayiçi (Kırkpınar Er Meydanı / Tarihi Saray)",
            aliases: ["sarayiçi", "kırkpınar", "er meydanı", "edirne sarayı", "kanuni köprüsü", "tavuk ormanı"],
            coords: [41.6912, 26.5562],
            desc: "Tarihi Kırkpınar Yağlı Güreşleri Er Meydanı ve Edirne Yeni Sarayı"
        },
        "D_BAYEZID_KULLIYE": {
            id: "D_BAYEZID_KULLIYE",
            name: "II. Bayezid Külliyesi (Sağlık Müzesi)",
            aliases: ["sağlık müzesi", "bayezid külliyesi", "darüşşifa", "yıldırım", "2. bayezid", "tunca köprüsü"],
            coords: [41.6865, 26.5414],
            desc: "Sultan II. Bayezid Külliyesi Sağlık Müzesi ve Tarihi Darüşşifa"
        },
        "D_PAZARTESI_PAZARI": {
            id: "D_PAZARTESI_PAZARI",
            name: "Pazartesi Pazarı / Barutluk",
            aliases: ["pazartesi pazarı", "semt pazarı", "barutluk", "pazar yeri"],
            coords: [41.6738, 26.5742],
            desc: "Edirne Kapalı Pazar Yeri & Pazartesi Pazarı Alanı"
        },
        "D_KYK_YURTLAR": {
            id: "D_KYK_YURTLAR",
            name: "Sultan Çelebi Mehmet KYK Yurdu / Fırınlarsırtı TOKİ",
            aliases: ["kyk", "öğrenci yurdu", "çelebi mehmet yurdu", "fırınlarsırtı", "toki", "kız yurdu", "erkek yurdu"],
            coords: [41.6892, 26.5880],
            desc: "KYK Öğrenci Yurtları Bölgesi & TOKİ Konutları"
        }
    },

    // Güncel Gerçek ETUS Hatları ve Güzergah Rotaları
    routes: [
        {
            id: "3",
            name: "Hat 3",
            title: "Gazimihal - Saraçlar - Erasta - Devlet Hastanesi - Tıp Fakültesi - Otogar",
            desc: "Edirne'nin en yoğun ana arter hattıdır. Çarşıdan Üniversiteye ve Otogara kesintisiz gider.",
            color: "#2563EB", // Canlı Mavi
            interval: "7 - 10 dk",
            stopIds: [
                "D_GAZIMIHAL",
                "D_SARACLAR",
                "D_ORDUEVI",
                "D_ERASTA",
                "D_MARGI",
                "D_AYSEKADIN",
                "D_DEVLET_HASTANESI",
                "D_BALKAN_KAMPUS",
                "D_OTOGAR"
            ]
        },
        {
            id: "1A",
            name: "Hat 1A",
            title: "Gazimihal - Saraçlar - Karaağaç - Serakent",
            desc: "Karaağaç ve Üniversite Güzel Sanatlar Fakültesi'ne giden ana hat.",
            color: "#DC2626", // Kırmızı
            interval: "10 - 15 dk",
            stopIds: [
                "D_GAZIMIHAL",
                "D_SARACLAR",
                "D_ORDUEVI",
                "D_KARAAĞAC"
            ]
        },
        {
            id: "1T",
            name: "Hat 1T",
            title: "Gazimihal - Saraçlar - Talatpaşa - Ayşekadın - Otogar (Ekspres)",
            desc: "Gazimihal ve merkezden Otogar'a direkt hızlı bağlantı hattı.",
            color: "#7C3AED", // Mor
            interval: "12 - 15 dk",
            stopIds: [
                "D_GAZIMIHAL",
                "D_SARACLAR",
                "D_ORDUEVI",
                "D_ERASTA",
                "D_AYSEKADIN",
                "D_OTOGAR"
            ]
        },
        {
            id: "2A",
            name: "Hat 2A",
            title: "Pazartesi Pazarı - Şükrüpaşa - Devlet Hastanesi - Tıp Fakültesi - Otogar",
            desc: "Yeni yerleşim bölgesi, Şükrüpaşa ve hastaneler üzerinden Otogar bağlantısı.",
            color: "#059669", // Zümrüt Yeşili
            interval: "15 - 20 dk",
            stopIds: [
                "D_PAZARTESI_PAZARI",
                "D_SUKRUPASA_GOLET",
                "D_DEVLET_HASTANESI",
                "D_ECZACILIK",
                "D_BALKAN_KAMPUS",
                "D_OTOGAR"
            ]
        },
        {
            id: "3A",
            name: "Hat 3A",
            title: "Sarayiçi - Selimiye - Saraçlar - Erasta - Tıp Fakültesi - Otogar",
            desc: "Sarayiçi Kırkpınar bölgesinden başlayıp şehir merkezi ve kampüsü bağlar.",
            color: "#D97706", // Amber / Turuncu
            interval: "15 - 20 dk",
            stopIds: [
                "D_SARAYICI",
                "D_SELIMIYE",
                "D_SARACLAR",
                "D_ORDUEVI",
                "D_ERASTA",
                "D_AYSEKADIN",
                "D_BALKAN_KAMPUS",
                "D_OTOGAR"
            ]
        },
        {
            id: "3C",
            name: "Hat 3C",
            title: "Karaağaç - Saraçlar - Erasta - Devlet Hastanesi - Otogar",
            desc: "Karaağaç bölgesinden Devlet Hastanesi ve Otogara doğrudan ulaşım sağlar.",
            color: "#DB2777", // Pembe
            interval: "20 - 25 dk",
            stopIds: [
                "D_KARAAĞAC",
                "D_GAZIMIHAL",
                "D_SARACLAR",
                "D_ORDUEVI",
                "D_ERASTA",
                "D_DEVLET_HASTANESI",
                "D_OTOGAR"
            ]
        },
        {
            id: "5A",
            name: "Hat 5A",
            title: "Gazimihal - Kıyık - Şükrüpaşa Gölet - Devlet Hastanesi - Balkan Kampüsü - Otogar",
            desc: "Kıyık ve Şükrüpaşa mahallelerini üniversite ve otogara bağlayan hat.",
            color: "#0891B2", // Camgöbeği (Cyan)
            interval: "15 - 20 dk",
            stopIds: [
                "D_GAZIMIHAL",
                "D_SELIMIYE",
                "D_KIYIK",
                "D_SUKRUPASA_GOLET",
                "D_DEVLET_HASTANESI",
                "D_BALKAN_KAMPUS",
                "D_OTOGAR"
            ]
        },
        {
            id: "5B",
            name: "Hat 5B",
            title: "KYK Yurtları (Çelebi Mehmet) - Selimiye - Saraçlar - Devlet Hastanesi",
            desc: "Fırınlarsırtı TOKİ ve KYK yurtlarından Devlet Hastanesi ve merkeze ulaşım.",
            color: "#4F46E5", // İndigo
            interval: "15 - 20 dk",
            stopIds: [
                "D_KYK_YURTLAR",
                "D_KIYIK",
                "D_SELIMIYE",
                "D_SARACLAR",
                "D_DEVLET_HASTANESI"
            ]
        },
        {
            id: "7E",
            name: "Hat 7E",
            title: "Sağlık Müzesi (Külliye) - Saraçlar - Erasta - Tıp Fakültesi - Otogar",
            desc: "Tarihi II. Bayezid Külliyesi / Darüşşifa bölgesinden Üniversite ve Otogara gider.",
            color: "#EA580C", // Koyu Turuncu
            interval: "20 - 30 dk",
            stopIds: [
                "D_BAYEZID_KULLIYE",
                "D_GAZIMIHAL",
                "D_SARACLAR",
                "D_ORDUEVI",
                "D_ERASTA",
                "D_BALKAN_KAMPUS",
                "D_OTOGAR"
            ]
        }
    ]
};
