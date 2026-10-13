# AGENTS.md — ETUS Asistanı Ajan Günlüğü

> Bu dosya, bu depoda çalışan ajanların **her adımda ne yaptığını** kayıt altına alır.
> Her işlem tamamlandıktan sonra en alta yeni bir kayıt eklenir.
> Uzman ajan referansları: `C:\Users\abdul\.agency-agents` (The Agency) —
> bu projede özellikle `engineering/mobile-app-builder` ve `design/ui-designer` ajan
> kişilikleri kullanılır (offline-first, platform-uyumlu, tutarlı tasarım sistemi).

## Kayıtlar

### 2026-10-13 — v1.1.0: Gerçek hat verisi ve yolculuk motoru
- 20 gerçek ETUS hattı + durak dizileri `etus_mobile/lib/data/etus_data.dart` içine alındı (kaynak: Edirne Jet Haber kataloğu + belediye "Otobüs Saatleri 2025" PDF'i).
- `journey_service.dart`: doğrudan + tek aktarmalı rota, mesafe/süre/bekleme hesabı.
- `route_card.dart` çok bacaklı kart arayüzü. flutter analyze temiz, 6/6 test, release APK.
- Push: commit `890d095`, GitHub Release **v1.1.0** (`ETUS-v1.1.0.apk`, 20.823.484 bayt).

### 2026-10-13 — Ajan kurulumu ve API araştırması
- `C:\Users\abdul\.agency-agents` dizini incelendi; `engineering-mobile-app-builder` ve `design-ui-designer` ajan dosyaları okunarak çalışma kişilikleri benimsendi (offline-first mimari, Material tasarım sistemi, 44dp dokunma hedefi).
- Edirne/ETUS veri kaynakları araştırıldı (researcher-web ajanı).
- **Kentkart API canlı olarak doğrulandı** (curl, HTTP 200):
  - `GET /rl1/web/nearest/find?region=013&lang=tr` → 23 hat + 50 durak (Edirne)
  - `GET /rl1/web/pathInfo?region=013&lang=tr&direction=0&displayRouteCode=1A&resultType=111111` → güzergâh polyline (84 nokta), 31 durak, program
  - `GET /rl1/web/nearest/bus?region=013&lang=tr&lat=..&lng=..&busStopId=20001` → **canlı otobüs konumları** (5 araç, plate/lat/lng/timeDiff)
- Topluluk GTFS: `Egezenn/kk-gtfs` deposunda `data/edirne.zip` (48 KB) mevcut (resmî değil, Kentkart'tan üretilmiş).
- Karar: uygulama **Kentkart API**'yi canlı kaynak, yerleşik `etus_data.dart`'ı çevrimdışı yedek olarak kullanacak.

### 2026-10-13 — v1.2.0: Canlı API, OSM harita, navigasyon düzeltmesi
- `etus_mobile/lib/services/kentkart_api.dart` eklendi: hat/durak kataloğu (`/web/nearest/find`), güzergâh polyline + duraklar (`/web/pathInfo`), **canlı otobüsler** (`/web/nearest/bus`) — hepsi region=013 (Edirne).
- `etus_mobile/lib/screens/map_screen.dart` eklendi: **uygulama içi OpenStreetMap** (flutter_map, API anahtarsız), kalkış/varış seçimi (dokunarak veya durak aramasıyla), güzergâh çizimi, 10 sn'de bir yenilenen canlı otobüs işaretçileri, GPS butonu, yer değiştir.
- **Navigasyon düzeltmesi:** `LocationService.startNavigation()` eklendi — öncelik sırası `google.navigation:q=` (anında turn-by-turn) → web `dir_action=navigate` → `geo:` fallback. Eski davranış (sadece yol tarifi ekranı açmak) artık ana buton değil; toplu taşıma seçeneği ayrı butona taşındı.
- **Kalkış/varış değiştirilebilir:** ana ekranda kalkış GPS yerine elle seçilebilir (arama bottom sheet'i, `KALKIŞ NOKTANIZ • Değiştir`), harita ekranında her iki uç da seçilebilir + yer değiştir butonu.
- Tasarım: harita FAB'ı (hedef seçildiğinde), kalkış kartı durumu (GPS/elle), rota kartında ikincil "Toplu Taşıma" butonu.
- Dep bağımlılıkları: `http`, `flutter_map`, `latlong2`. Sürüm `1.2.0+3`.
- Ajan kullanımı: `engineering/mobile-app-builder` (offline-first, platform-uyumlu) + `design/ui-designer` (tutarlı kart/tipografi) kişilikleri; tüm adımlar bu günlüğe işlendi.
