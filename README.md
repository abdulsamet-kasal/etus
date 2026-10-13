# 🚌 ETUS — Edirne Toplu Ulaşım Akıllı Rota & Google Maps Asistanı

![Platform](https://img.shields.io/badge/platform-Web%20%7C%20Flutter-blue)
![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![City](https://img.shields.io/badge/şehir-Edirne-red)

Edirne şehiriçi toplu ulaşım sistemi (**ETUS**) için geliştirilmiş, çok platformlu (**Web + Flutter mobil**) akıllı rota bulucu.

Kullanıcı durak adını bilmese veya yanlış yazsa bile **niyet/semantik arama motoru** hedefi anlar, **GPS ile en yakın biniş durağını** bulur ve tek tıkla **Google Haritalar toplu taşıma navigasyonunu** başlatır.

---

## 📑 İçindekiler

- [Öne Çıkan Özellikler](#-öne-çıkan-özellikler)
- [Nasıl Çalışır](#-nasıl-çalışır)
- [Niyet Algılama Tablosu](#-niyet-algılama-tablosu)
- [Desteklenen ETUS Hatları](#-desteklenen-etus-hatları)
- [Proje Yapısı](#-proje-yapısı)
- [Hızlı Başlangıç (Web)](#-hızlı-başlangıç-web)
- [Mobil Uygulama (Flutter)](#-mobil-uygulama-flutter)
- [PWA Olarak Kurma](#-pwa-olarak-kurma)
- [Konum / GPS Notları](#-konum--gps-notları)
- [Google Maps Entegrasyonu](#-google-maps-entegrasyonu)
- [Veri Modeli ve Yeni Durak/Hat Ekleme](#-veri-modeli-ve-yeni-durakhat-ekleme)
- [Sınırlamalar ve Yol Haritası](#-sınırlamalar-ve-yol-haritası)
- [Katkıda Bulunma](#-katkıda-bulunma)
- [Lisans](#-lisans)

---

## 🌟 Öne Çıkan Özellikler

### 1. 🧠 Akıllı semantik + hata toleranslı arama

Klasik "birebir durak adı eşleştirme" yerine 3 katmanlı arama yapılır (`app.js` + `smart_search_service.dart`):

1. **Doğrudan eşleşme:** Durak adı veya alias sorguyu içeriyorsa yüksek skor (95–100).
2. **Alias + token eşleşmesi:** `data.js` içindeki her durağın `aliases` listesindeki kelimeler tek tek kontrol edilir.
3. **Niyet algılama:** `doktor`, `avm`, `vize`, `bilet`, `çay`, `namaz` gibi günlük dildeki kelimeler kategoriye çevrilip ilgili durağa yönlendirilir.
4. **Yazım hatası toleransı:** Türkçe karakter normalizasyonu (`ç→c`, `ğ→g`, `ı→i`, `ö→o`, `ş→s`, `ü→u`) + **Levenshtein uzaklığı** ile `ersta`, `karaagac`, `otgar`, `tip fakiltesi` gibi girdiler düzeltilir.

Her sonuçta **güven skoru + gerekçe** gösterilir. Örnek: `💡 Alışveriş / Sinema niyeti algılandı (%90)`.

### 2. 📍 Otomatik GPS + en yakın durak

- Tarayıcıda `navigator.geolocation`, mobilde `geolocator` paketi kullanılır.
- **Haversine formülü** ile 18 durak arasından size en yakın biniş durağı ve metre cinsinden yürüme mesafesi hesaplanır.
- GPS yoksa/izin verilmezse **haritaya tıklayarak** konum seçilebilir. Varsayılan konum: Saraçlar Caddesi (Merkez).

### 3. 🗺️ Google Haritalar canlı navigasyon

Her rota sonucu için 2 hazır link üretilir:

- Biniş durağına **yürüme** tarifi (`travelmode=walking`)
- Hedefe **toplu taşıma** tarifi (`travelmode=transit`)

Web'de butonla yeni sekmede, mobilde `url_launcher` ile Google Maps uygulamasında açılır.

### 4. �🗺️ İnteraktif Leaflet haritası (Web)

- CARTO Voyager altlığı, özel pin tasarımları.
- Mavi nabız = sizin konumunuz, yeşil ✓ = biniş durağı, kırmızı ● = iniş durağı.
- Gri kesik çizgi = yürüme, renkli kalın çizgi = otobüs güzergâhı.
- Her durak popup'ında geçen hatlar + **"🎯 Buraya Gitmek İstiyorum"** kısayolu.

### 5. ⚡ Tek tıkla popüler noktalar

Arama kutusunun altında hazır çipler: Erasta AVM, Tıp Fakültesi, Otogar, Devlet Hastanesi, Karaağaç, Selimiye.

---

## ⚙️ Nasıl Çalışır?

### Arama akışı

```text
Kullanıcı girdisi
  → normalizeText (küçük harf + Türkçe normalize + noktalama temizliği)
  → niyet kategorisini bul (avm / hastane / universite / ulasim / gezi_kafe / ibadet_tarih)
  → her durak için skorla (isim + alias + token + niyet + Levenshtein)
  → skoru ≥ 50 olanları sırala → ilk 5'ini öneri kutusunda göster
```

### Rota akışı

```text
userCoords + hedef durak
  → en yakın biniş durağı (Haversine)
  → aynı hatta iki durak da varsa: DİREKT ROTA
      · durak sayısı × 3 dk = otobüs süresi
      · mesafe / 80 m-dk = yürüme süresi + 3 dk buffer
  → yoksa: ortak durak üzerinden 1 AKTARMALI öneri ara
  → bulunamazsa bile Google Maps transit linki her zaman sunulur
```

---

## 🧭 Niyet Algılama Tablosu

| Ne yazarsanız | Nereye yönlendirilir | Kategori |
|---|---|---|
| `doktor`, `hastane`, `acil`, `muayene`, `randevu`, `ilaç` | Sultan 1. Murat Devlet Hastanesi / Tıp Fakültesi | hastane |
| `avm`, `alışveriş`, `sinema`, `lcw`, `migros`, `market` | Erasta AVM / Margi Outlet | avm |
| `uni`, `kampüs`, `fakülte`, `vize`, `final`, `rektörlük`, `tıp` | Trakya Üni. Balkan Yerleşkesi / Ayşekadın | universite |
| `otobüs`, `terminal`, `otogar`, `bilet`, `yolculuk` | Edirne Otogarı | ulasim |
| `çay`, `kahve`, `kahvaltı`, `lozan`, `gar`, `gezme`, `nehir` | Karaağaç Meydanı / Tren Garı | gezi_kafe |
| `cami`, `namaz`, `selimiye`, `müze`, `külliye`, `tarihi` | Selimiye Camii / II. Bayezid Külliyesi | ibadet_tarih |

---

## 🚌 Desteklenen ETUS Hatları

Toplam **18 durak**, **9 hat** (`data.js` + `etus_data.dart` içinde tanımlı):

| Hat | Güzergâh Özeti | Sefer Aralığı |
|---|---|---|
| **Hat 3** | Gazimihal – Saraçlar – Erasta – Devlet Hastanesi – Tıp Fakültesi – Otogar | 7–10 dk |
| **Hat 1A** | Gazimihal – Saraçlar – Karaağaç | 10–15 dk |
| **Hat 1T** (Ekspres) | Gazimihal – Saraçlar – Ayşekadın – Otogar | 12–15 dk |
| **Hat 2A** | Pazartesi Pazarı – Şükrüpaşa – Devlet Hastanesi – Tıp Fakültesi – Otogar | 15–20 dk |
| **Hat 3A** | Sarayiçi (Kırkpınar) – Selimiye – Saraçlar – Tıp Fakültesi – Otogar | 15–20 dk |
| **Hat 3C** | Karaağaç – Saraçlar – Devlet Hastanesi – Otogar | 20–25 dk |
| **Hat 5A** | Gazimihal – Kıyık – Şükrüpaşa Gölet – Devlet Hastanesi – Kampüs – Otogar | 15–20 dk |
| **Hat 5B** | KYK Yurtları – Selimiye – Saraçlar – Devlet Hastanesi | 15–20 dk |
| **Hat 7E** | Sağlık Müzesi (Külliye) – Saraçlar – Erasta – Tıp Fakültesi – Otogar | 20–30 dk |

> Not: Hat ve saat bilgileri uygulamaya gömülü statik veridir; ETUS resmi tarifesi değişirse `data.js` ve `etus_mobile/lib/data/etus_data.dart` birlikte güncellenmelidir.

---

## 📂 Proje Yapısı

```text
etus/
├── index.html              # Tailwind + Leaflet web arayüzü
├── app.js                  # Harita, GPS, NLP arama ve rota mantığı (web)
├── data.js                 # 18 durak + 9 hat (ETUS_DATA)
├── server.js               # Sıfır bağımlılıklı Node.js statik sunucu
├── manifest.json           # PWA kurulum dosyası
├── README.md               # Bu dosya
├── LICENSE                 # MIT lisansı
├── .gitignore              # Flutter / Node / IDE kuralları
└── etus_mobile/            # Flutter mobil uygulaması
    ├── pubspec.yaml        # geolocator, url_launcher bağımlılıkları
    ├── android/app/src/main/AndroidManifest.xml  # Konum + Maps izinleri
    └── lib/
        ├── main.dart                 # Material 3 giriş noktası
        ├── data/etus_data.dart       # Web ile aynı durak/hat verisi (Dart)
        ├── models/stop.dart / route_line.dart
        ├── services/
        │   ├── smart_search_service.dart  # normalize + Levenshtein + niyet
        │   └── location_service.dart      # GPS + Haversine
        ├── widgets/route_card.dart / quick_chip.dart
        └── screens/home_screen.dart
```

---

## 🚀 Hızlı Başlangıç (Web)

### Gereksinimler

- [Node.js](https://nodejs.org/) (herhangi güncel sürüm yeterli — ek `npm install` gerekmez, sunucu sıfır bağımlılıklıdır).

### Çalıştırma

```powershell
# Proje kökünde:
node server.js
```

Tarayıcıda açın: **http://localhost:3000**

### Kullanım

1. Sağ üstteki **"Konumumu Al (GPS)"** butonuna basın veya haritada konumunuza tıklayın.
2. Arama kutusuna hedefi yazın (`Tıp Fakültesi`, `ersta`, `doktor`, `otogar`...) veya hazır çiplerden birine tıklayın.
3. Öneriler arasından hedefi seçin → biniş durağı, otobüs hatları ve adım adım tarif kartlarda listelenir.
4. **"Google Maps'te Canlı Tarifi Başlat"** ile navigasyonu açın.

---

## 📱 Mobil Uygulama (Flutter)

### Gereksinimler

- Flutter SDK 3.0+
- Android Studio / VS Code + emülatör veya fiziksel cihaz

### Çalıştırma

```bash
cd etus_mobile
flutter pub get
flutter run
```

### Release APK alma

```bash
cd etus_mobile
flutter build apk --release
```

Çıktı: `etus_mobile/build/app/outputs/flutter-apk/app-release.apk`

Android izinleri (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET` + Maps `queries`) `AndroidManifest.xml` içinde hazır tanımlıdır.

---

## 📲 PWA Olarak Kurma

Web sürümü PWA desteklidir (`manifest.json`):

- **Android/Chrome:** Menü → "Ana ekrana ekle" / "Uygulamayı yükle".
- **iOS/Safari:** Paylaş → "Ana Ekrana Ekle".
- **Masaüstü Chrome/Edge:** Adres çubuğundaki yükle simgesi.

---

## 📡 Konum / GPS Notları

- GPS, tarayıcı güvenlik politikası gereği yalnızca **`localhost` veya HTTPS** üzerinde çalışır. `file://` ile açılan sayfada konum alınamaz — mutlaka `node server.js` ile serve edin.
- Konum izni reddedilirse uygulama haritaya tıklayarak manuel konum seçimine düşer, tüm rota özellikleri çalışmaya devam eder.

---

## 🗺️ Google Maps Entegrasyonu

Uygulama kendi rota tahmini yapar, canlı navigasyonu Google Maps'e devreder. Üretilen URL formatı:

```text
# Toplu taşıma (konum → hedef durak)
https://www.google.com/maps/dir/?api=1&origin={lat},{lng}&destination={lat},{lng}&travelmode=transit

# Yürüme (konum → biniş durağı)
https://www.google.com/maps/dir/?api=1&origin={lat},{lng}&destination={lat},{lng}&travelmode=walking
```

---

## 🧩 Veri Modeli ve Yeni Durak/Hat Ekleme

Yeni durak eklemek için **iki dosyayı da** güncelleyin: `data.js` ve `etus_mobile/lib/data/etus_data.dart`.

```js
"D_YENI_DURAK": {
  id: "D_YENI_DURAK",
  name: "Örnek Durak",
  aliases: ["ornek", "ornek durak", "kısayol"],
  coords: [41.6700, 26.5600],
  desc: "Kısa açıklama"
}
```

Yeni hat eklemek için ilgili `routes` dizisine `stopIds` sırasıyla ekleyin. Renk (`color`) hem harita çizgisinde hem rozetlerde kullanılır.

---

## ⚠️ Sınırlamalar ve Yol Haritası

- Süre tahminleri sabittir (durak başı ~3 dk, yürüme ~80 m/dk) — canlı trafik/sefer verisi yoktur.
- Hat verisi statiktir; resmi ETUS değişikleri elle işlenmelidir.
- Planlananlar: durak favorileri, hat bazlı filtreleme, karanlık mod, iOS build dokümantasyonu, ekran görüntüleri/demo GIF'i.

---

## 🤝 Katkıda Bulunma

1. Repoyu fork'layın, yeni dal açın (`git checkout -b ozellik/yeni-durak`).
2. Web + mobil veriyi birlikte güncelleyin.
3. `node server.js` ile web'i, `flutter run` ile mobili test edin.
4. Pull request açın.

Hata bildirimi veya yeni durak/hat önerisi için GitHub **Issues** bölümünü kullanın.

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) ile lisanslanmıştır.

---

<p align="center">Edirne için ❤️ ile geliştirildi · ETUS Ulaşım Rehberi + Google Maps Entegrasyonu</p>
