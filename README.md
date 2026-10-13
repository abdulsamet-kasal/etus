# 🚌 ETUS - Edirne Toplu Ulaşım Akıllı Rota & Google Maps Asistanı

![GitHub release (latest by date)](https://img.shields.io/badge/release-v1.0.0-blue)
![Platform](https://img.shields.io/badge/platform-Flutter%20%7C%20Web-blue)
![License](https://img.shields.io/badge/license-MIT-green)

Edirne Şehiriçi Toplu Ulaşım Sistemi (**ETUS**) için geliştirilmiş, akıllı niyet/semantik arama motoruna ve canlı **Google Haritalar** toplu taşıma entegrasyonuna sahip çok platformlu (Web & Flutter Mobil) rota bulucu uygulaması.

---

## 🌟 Öne Çıkan Özellikler

### 1. 🧠 Akıllı Semantik Niyet Algılama (Smart NLP & Fuzzy Matching)
Kullanıcı durak adını bilmese veya yanlış/eksik yazsa bile ne yapmak istediğini anlar:
- **Niyet / Kategori Çözümleme**:
  - `doktor`, `hastane`, `muayene`, `acil` $\rightarrow$ **Sultan 1. Murat Devlet Hastanesi** veya **Tıp Fakültesi**
  - `avm`, `alisveris`, `sinema`, `lcw` $\rightarrow$ **Erasta AVM** veya **Margi Outlet**
  - `tip`, `uni`, `kampus`, `vize`, `rektorluk` $\rightarrow$ **Trakya Üni. Balkan Yerleşkesi (Tıp Fakültesi)**
  - `bilet`, `otobus`, `terminal` $\rightarrow$ **Edirne Otogarı**
  - `cay`, `lozan`, `gar`, `kahvalti` $\rightarrow$ **Karaağaç Meydanı / Tren Garı**
  - `namaz`, `cami` $\rightarrow$ **Selimiye Camii**
  - `yurt`, `kyk` $\rightarrow$ **Sultan Çelebi Mehmet KYK Yurdu**
- **Yazım Hatası Toleransı (Levenshtein Distance)**:
  - `ersta`, `karaagac`, `tip fakiltesi`, `otgar`, `saraclr` gibi eksik ve Türkçe karaktersiz girdilerde en yakın durağı tespit eder.
- **Şeffaf Güven Skoru**:
  - Eşleşme nedenini kullanıcıya gösterir *(Örn: 💡 "%95 - Alışveriş / Sinema niyeti algılandı")*.

### 2. 📍 Otomatik GPS Konum Tespiti
- Açılır menülerden durak aramakla uğraşmanıza gerek yoktur.
- GPS üzerinden anlık konumunuzu alır ve **Haversine formülüyle** size en yakın ETUS biniş durağını ve yürüme mesafesini hesaplar.

### 3. 🗺️ Google Haritalar (Google Maps) Canlı Navigasyon
- Her rota için tek tıkla **Google Haritalar Toplu Taşıma (Transit)** navigasyonunu başlatır:
  - Biniş durağına yürüyüş adımları
  - Binilecek ETUS otobüsü ve sefer aralığı
  - İneceğiniz durak ve tahmini varış süresi

### 4. 🚌 Gerçek Edirne ETUS Hatları
- **Hat 3**: Gazimihal ↔ Saraçlar ↔ Erasta ↔ Sultan 1. Murat Devlet Hastanesi ↔ Balkan Kampüsü (Tıp Fakültesi) ↔ Otogar
- **Hat 1A**: Gazimihal ↔ Saraçlar ↔ Karaağaç (Güzel Sanatlar / Tren Garı)
- **Hat 1T**: Gazimihal ↔ Saraçlar ↔ Talatpaşa ↔ Ayşekadın ↔ Otogar (Ekspres)
- **Hat 2A**: Pazartesi Pazarı ↔ Şükrüpaşa ↔ Devlet Hastanesi ↔ Tıp Fakültesi ↔ Otogar
- **Hat 3A**: Sarayiçi (Kırkpınar) ↔ Selimiye ↔ Saraçlar ↔ Tıp Fakültesi ↔ Otogar
- **Hat 3C**: Karaağaç ↔ Saraçlar ↔ Devlet Hastanesi ↔ Otogar
- **Hat 5A**: Gazimihal ↔ Kıyık ↔ Şükrüpaşa Gölet ↔ Devlet Hastanesi ↔ Balkan Kampüsü ↔ Otogar
- **Hat 5B**: KYK Yurtları (Çelebi Mehmet) ↔ Selimiye ↔ Saraçlar ↔ Devlet Hastanesi
- **Hat 7E**: Sağlık Müzesi (II. Bayezid Külliyesi) ↔ Saraçlar ↔ Erasta ↔ Balkan Kampüsü ↔ Otogar

---

## 📂 Proje Yapısı

```text
etus/
├── index.html                    # Modern Leaflet.js & Tailwind CSS Web Arayüzü
├── app.js                        # Web NLP Arama & Rota Mantığı
├── data.js                       # Edirne ETUS Durak & Hat Veritabanı
├── server.js                     # Sıfır bağımlılıklı Node.js HTTP Sunucusu
├── .gitignore                    # Flutter & Web için gitignore kuralları
├── .github/workflows/
│   └── build-apk.yml             # GitHub Actions Otomatik APK Derleme & Release
└── etus_mobile/                  # Flutter Mobil Uygulaması
    ├── pubspec.yaml              # geolocator, url_launcher paketleri
    ├── android/                  # Android Manifest & Konum izinleri
    └── lib/
        ├── main.dart             # Material 3 Giriş Noktası
        ├── data/etus_data.dart   # Gerçek Hatlar & Duraklar
        ├── models/               # Stop & RouteLine modelleri
        ├── services/             # SmartSearchService & LocationService
        ├── widgets/              # RouteCard & QuickChip bileşenleri
        └── screens/home_screen.dart # Ana Sayfa
```

---

## 🚀 Çalıştırma Rehberi

### 1. Web Sürümünü Çalıştırma
```powershell
node server.js
```
Tarayıcınızda [http://localhost:3000](http://localhost:3000) adresine gidin.

### 2. Flutter Mobil Uygulamasını Çalıştırma
```powershell
cd etus_mobile
flutter pub get
flutter run
```

### 3. Android APK Derleme
```powershell
cd etus_mobile
flutter build apk --release
```
Derlenen APK çıktısı `etus_mobile/build/app/outputs/flutter-apk/app-release.apk` dizininde oluşturulur.

---

## 📦 GitHub Actions ile Otomatik APK Release

Repo GitHub'a yüklendiğinde, `.github/workflows/build-apk.yml` sayesinde her sürüm etiketinde (`v*`) otomatik olarak Android Release APK derlenir ve GitHub Releases bölümünde doğrudan indirilebilir olarak yayınlanır.
