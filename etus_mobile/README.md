# 🚌 ETUS Akıllı Rota & Google Maps Asistanı (Flutter)

Edirne Şehiriçi Toplu Ulaşım Sistemi (ETUS) için geliştirilmiş, akıllı niyet/semantik arama motoruna ve canlı Google Haritalar entegrasyonuna sahip Flutter mobil uygulaması.

---

## 📱 Temel Özellikler

1. **📍 Otomatik GPS Konum Tespiti**:
   - `geolocator` kullanarak kullanıcının anlık konumunu alır.
   - Haversine formülüyle kullanıcıya en yakın ETUS biniş durağını metre cinsinden hesaplar (Örn: *Saraçlar Caddesi - 110 metre*).

2. **🧠 Akıllı Semantik Niyet ve Hata Toleranslı Arama (Smart Search NLP)**:
   - Kullanıcı tam durak adı yazmasa bile nereye gitmek istediğini anlar:
     - *"doktor"*, *"muayene"*, *"hastane"* $\rightarrow$ **Sultan 1. Murat Devlet Hastanesi**
     - *"avm"*, *"alisveris"*, *"sinema"*, *"ersta"* (yazım hatası) $\rightarrow$ **Erasta AVM**
     - *"tip"*, *"uni"*, *"balkan"*, *"kampus"* $\rightarrow$ **Trakya Üni. Balkan Yerleşkesi (Tıp Fakültesi)**
     - *"bilet"*, *"otobus"*, *"yolculuk"* $\rightarrow$ **Edirne Otogarı**
     - *"cay"*, *"kahvalti"*, *"gar"*, *"karaagac"* $\rightarrow$ **Karaağaç Meydanı / Tren Garı**
     - *"namaz"*, *"cami"* $\rightarrow$ **Selimiye Camii**
   - Eşleşme gerekçesini ve güven skorunu kullanıcıya şeffafça gösterir (💡 *"%95 - Alışveriş / Sinema niyetiyle eşleşti"*).

3. **🗺️ Google Haritalar Canlı Navigasyon Entegrasyonu**:
   - Bulunan her ETUS rotası için tek tıkla canlı navigasyon:
   - `url_launcher` ile Google Haritalar doğrudan **Toplu Taşıma (Transit)** modunda açılır.
   - Biniş durağına yürüyüş adımları ve inilecek durak Google Maps'te canlı gösterilir.

4. **🚌 Gerçek ETUS Hatları**:
   - **Hat 3**, **Hat 1A**, **Hat 1T**, **Hat 2A**, **Hat 3A**, **Hat 3C**, **Hat 5A**, **Hat 5B**, **Hat 7E** hatları ve tüm ara durakları.

---

## 🛠️ Kurulum ve Çalıştırma

### Gereksinimler
- Flutter SDK (3.0+)
- Android Studio / VS Code veya fiziksel telefon / emülatör

### Adımlar

1. Bağımlılıkları yükleyin:
   ```bash
   cd etus_mobile
   flutter pub get
   ```

2. Cihazınızda veya emülatörde çalıştırın:
   ```bash
   flutter run
   ```

3. APK Çıktısı Alma:
   ```bash
   flutter build apk --release
   ```
