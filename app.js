/**
 * ETUS Akıllı Rota & Google Maps Asistanı
 */

// Global State
let map;
let allStopMarkers = L.layerGroup();
let routePolylineLayer = L.layerGroup();
let userLocationMarker = null;

// Kullanıcının anlık konumu (Varsayılan: Saraçlar Caddesi / Edirne Merkez)
let userCoords = [41.6752, 26.5548];
let userLocationName = "Saraçlar Caddesi (Merkez)";
let nearestOriginStop = null;
let selectedDestinationStop = null;

// Haversine Formülü: İki koordinat arası mesafeyi metre cinsinden hesaplar
function calculateDistanceMeters(lat1, lon1, lat2, lon2) {
    const R = 6371e3; // Dünya yarıçapı (metre)
    const phi1 = (lat1 * Math.PI) / 180;
    const phi2 = (lat2 * Math.PI) / 180;
    const deltaPhi = ((lat2 - lat1) * Math.PI) / 180;
    const deltaLambda = ((lon2 - lon1) * Math.PI) / 180;

    const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
              Math.cos(phi1) * Math.cos(phi2) *
              Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return Math.round(R * c);
}

// En yakın durağı bulma
function findNearestStop(coords) {
    let nearest = null;
    let minDistance = Infinity;

    Object.values(ETUS_DATA.stops).forEach(stop => {
        const dist = calculateDistanceMeters(coords[0], coords[1], stop.coords[0], stop.coords[1]);
        if (dist < minDistance) {
            minDistance = dist;
            nearest = { ...stop, distanceMeters: dist };
        }
    });

    return nearest;
}

// Özel İkon Üreticisi
function createCustomPin(color, iconHtml, size = 32) {
    return L.divIcon({
        className: 'custom-div-icon',
        html: `
            <div style="
                background-color: ${color};
                width: ${size}px;
                height: ${size}px;
                border-radius: 50%;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                box-shadow: 0 4px 12px rgba(0,0,0,0.35);
                border: 2px solid white;
            ">
                ${iconHtml}
            </div>
        `,
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
        popupAnchor: [0, -size / 2]
    });
}

// Sayfa Yüklendiğinde
document.addEventListener('DOMContentLoaded', () => {
    initMap();
    renderAllStopsOnMap();
    setupLocationAndSearch();
    // Varsayılan olarak konumu belirle
    updateUserLocation(userCoords, "Saraçlar Caddesi (Varsayılan Konum)");
});

/**
 * 1. Harita Kurulumu (Edirne Odaklı)
 */
function initMap() {
    map = L.map('map', {
        zoomControl: false
    }).setView([41.6680, 26.5700], 13);

    L.control.zoom({ position: 'topright' }).addTo(map);

    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; OpenStreetMap &copy; CARTO',
        subdomains: 'abcd',
        maxZoom: 19
    }).addTo(map);

    allStopMarkers.addTo(map);
    routePolylineLayer.addTo(map);

    // Haritaya tıklayarak "Buradayım" diyebilme
    map.on('click', (e) => {
        const clickedCoords = [e.latlng.lat, e.latlng.lng];
        updateUserLocation(clickedCoords, "Haritada Seçilen Konum");
    });
}

/**
 * 2. Tüm ETUS Duraklarını Haritada Göster
 */
function renderAllStopsOnMap() {
    allStopMarkers.clearLayers();

    Object.values(ETUS_DATA.stops).forEach(stop => {
        const passingRoutes = ETUS_DATA.routes.filter(r => r.stopIds.includes(stop.id));

        const stopIcon = createCustomPin('#2563EB', `
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M8 7h8m-8 4h8m-4 4v4m-5-8h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v4a2 2 0 002 2z"></path>
            </svg>
        `, 26);

        const marker = L.marker(stop.coords, { icon: stopIcon });

        const badgesHtml = passingRoutes.map(line => `
            <span class="inline-block px-1.5 py-0.5 text-[11px] font-bold rounded text-white" style="background-color: ${line.color}">
                ${line.name}
            </span>
        `).join(' ');

        marker.bindPopup(`
            <div class="p-1 min-w-[210px]">
                <div class="text-[10px] font-bold text-blue-600 uppercase tracking-wider mb-0.5">ETUS Durağı</div>
                <div class="text-sm font-bold text-gray-800 mb-1">${stop.name}</div>
                <div class="text-xs text-gray-500 mb-2">${stop.desc || ''}</div>
                <div class="border-t pt-1.5 mb-2">
                    <div class="text-[11px] font-medium text-gray-500 mb-1">Geçen Otobüsler:</div>
                    <div class="flex flex-wrap gap-1">${badgesHtml || 'Aktif hat yok'}</div>
                </div>
                <button onclick="setDestinationDirect('${stop.id}')" class="w-full bg-blue-600 hover:bg-blue-700 text-white py-1.5 px-2 rounded-lg text-xs font-semibold transition flex items-center justify-center gap-1">
                    🎯 Buraya Gitmek İstiyorum
                </button>
            </div>
        `);

        allStopMarkers.addLayer(marker);
    });
}

/**
 * 3. Kullanıcı Konumu ve Arama Mantığı
 */
function setupLocationAndSearch() {
    const locateBtn = document.getElementById('locateBtn');
    const destInput = document.getElementById('destinationInput');
    const searchBtn = document.getElementById('searchRouteBtn');
    const suggestionsBox = document.getElementById('suggestionsBox');

    // GPS Konumu Al Butonu
    locateBtn.addEventListener('click', getCurrentGPSLocation);

    // Hedef Arama Kutusu Canlı Arama (Autocomplete)
    destInput.addEventListener('input', (e) => {
        const query = e.target.value.trim().toLowerCase();
        if (query.length < 2) {
            suggestionsBox.classList.add('hidden');
            return;
        }

        const matches = searchStopsAndPlaces(query);
        renderSuggestions(matches);
    });

    // Enter Tuşuna Basınca
    destInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            executeSearch();
        }
    });

    searchBtn.addEventListener('click', executeSearch);

    // Kısayol Butonları (Örn: Tıp Fakültesi, Erasta, Otogar)
    document.querySelectorAll('.quick-dest-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const destName = btn.dataset.target;
            destInput.value = destName;
            executeSearch();
        });
    });

    // Sayfa dışına tıklandığında önerileri kapat
    document.addEventListener('click', (e) => {
        if (!e.target.closest('#destinationWrapper')) {
            suggestionsBox.classList.add('hidden');
        }
    });
}

/**
 * Tarayıcıdan Gerçek GPS Konumunu Alma
 */
function getCurrentGPSLocation() {
    const statusText = document.getElementById('locationStatusText');
    const locateBtn = document.getElementById('locateBtn');

    if (!navigator.geolocation) {
        alert("Tarayıcınız coğrafi konum servisini desteklemiyor.");
        return;
    }

    locateBtn.disabled = true;
    statusText.innerHTML = `<span class="animate-pulse text-blue-600">📡 GPS uydularına bağlanılıyor...</span>`;

    navigator.geolocation.getCurrentPosition(
        (position) => {
            locateBtn.disabled = false;
            const lat = position.coords.latitude;
            const lng = position.coords.longitude;
            updateUserLocation([lat, lng], "Canlı GPS Konumunuz");
        },
        (error) => {
            locateBtn.disabled = false;
            let msg = "Konum alınamadı. Lütfen tarayıcı konum iznini onaylayın.";
            if (error.code === error.PERMISSION_DENIED) {
                msg = "Konum izni reddedildi. Haritaya tıklayarak konum belirleyebilirsiniz.";
            }
            alert(msg);
            statusText.innerHTML = `<span class="text-amber-600">⚠️ Konum izni yok (Haritaya tıklayabilirsiniz)</span>`;
        },
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    );
}

/**
 * Kullanıcı Konumunu Güncelleme ve En Yakın Durağı Belirleme
 */
function updateUserLocation(coords, label) {
    userCoords = coords;
    userLocationName = label;

    // En yakın ETUS durağını tespit et
    nearestOriginStop = findNearestStop(coords);

    // Konum Bilgi Alanını Güncelle
    const statusText = document.getElementById('locationStatusText');
    const nearestStopBadge = document.getElementById('nearestStopBadge');

    statusText.innerHTML = `<strong>📍 ${label}</strong>`;
    if (nearestOriginStop) {
        nearestStopBadge.innerHTML = `
            <div class="flex items-center gap-1.5 text-xs text-emerald-800 bg-emerald-50 border border-emerald-200 px-2.5 py-1.5 rounded-lg mt-1">
                <span>🚶 Size en yakın ETUS durağı:</span>
                <strong>${nearestOriginStop.name}</strong>
                <span class="bg-emerald-200 text-emerald-900 text-[10px] px-1.5 py-0.2 rounded font-bold">${nearestOriginStop.distanceMeters}m</span>
            </div>
        `;
    }

    // Haritada Kullanıcı Konum İşaretçisini Çiz (Mavi Nabız)
    if (userLocationMarker) {
        map.removeLayer(userLocationMarker);
    }

    const userIcon = L.divIcon({
        className: 'user-pulse-icon',
        html: `
            <div class="relative flex items-center justify-center">
                <span class="animate-ping absolute inline-flex h-8 w-8 rounded-full bg-blue-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-5 w-5 bg-blue-600 border-2 border-white shadow-lg"></span>
            </div>
        `,
        iconSize: [32, 32],
        iconAnchor: [16, 16]
    });

    userLocationMarker = L.marker(coords, { icon: userIcon, zIndexOffset: 2000 }).addTo(map);
    userLocationMarker.bindPopup(`<b>${label}</b><br><span class="text-xs text-gray-500">En yakın durak: ${nearestOriginStop ? nearestOriginStop.name : 'Bilinmiyor'}</span>`).openPopup();

    // Eğer hedef de seçiliyse rotayı yeniden çiz
    if (selectedDestinationStop) {
        calculateAndRenderJourney();
    } else {
        map.setView(coords, 15);
    }
}

// Semantik Niyet Sözlüğü (Kullanıcı durak adı bilmese bile ne yapmak istediğini anlar)
const INTENT_CATEGORIES = {
    'avm': ['avm', 'alisveris', 'magaza', 'sinema', 'lcw', 'burger', 'starbucks', 'yemek ye', 'market', 'migros'],
    'hastane': ['doktor', 'hastane', 'hasta', 'muayene', 'tedavi', 'ilac', 'recete', 'saglik', 'acil', 'poliklinik', 'randevu', 'tahlil', 'hemsire'],
    'universite': ['uni', 'universite', 'kampus', 'ogrenci', 'fakulte', 'ders', 'vize', 'final', 'rektorluk', 'iibf', 'balkan', 'trakya uni', 'tip'],
    'ulasim': ['otobus', 'otobusler', 'terminal', 'otogar', 'bilet', 'yolculuk', 'sehir disi', 'metro', 'pamukkale', 'kamil koc'],
    'gezi_kafe': ['cay', 'kahve', 'kafe', 'kahvalti', 'lozan', 'nehir', 'meric', 'tarihi', 'kopru', 'tren gari', 'gezme'],
    'ibadet_tarih': ['cami', 'namaz', 'cuma', 'selimiye', 'mimar sinan', 'dua', 'muze', 'kulliye', 'darussifa', 'tarihi yer']
};

function normalizeText(text) {
    return text.toLowerCase()
        .replace(/ç/g, 'c')
        .replace(/ğ/g, 'g')
        .replace(/ı/g, 'i')
        .replace(/İ/g, 'i')
        .replace(/ö/g, 'o')
        .replace(/ş/g, 's')
        .replace(/ü/g, 'u')
        .replace(/[^a-z0-9\s]/g, '')
        .trim();
}

// Levenshtein Mesafesi
function levenshteinDist(s1, s2) {
    if (s1 === s2) return 0;
    if (!s1.length) return s2.length;
    if (!s2.length) return s1.length;
    let v0 = Array(s2.length + 1).fill(0).map((_, i) => i);
    let v1 = Array(s2.length + 1).fill(0);
    for (let i = 0; i < s1.length; i++) {
        v1[0] = i + 1;
        for (let j = 0; j < s2.length; j++) {
            let cost = (s1[i] === s2[j]) ? 0 : 1;
            v1[j + 1] = Math.min(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost);
        }
        for (let j = 0; j <= s2.length; j++) v0[j] = v1[j];
    }
    return v1[s2.length];
}

function stringSimilarity(s1, s2) {
    const maxLen = Math.max(s1.length, s2.length);
    if (maxLen === 0) return 1.0;
    return 1.0 - (levenshteinDist(s1, s2) / maxLen);
}

/**
 * Arama Terimiyle Eşleşen Durak ve Yerleri Akıllı NLP ile Bulma
 */
function searchStopsAndPlaces(query) {
    const cleanQuery = normalizeText(query);
    if (!cleanQuery) return [];

    const userTokens = cleanQuery.split(/\s+/);
    const results = [];

    // Niyet Tespiti
    let detectedIntent = null;
    for (let [cat, keywords] of Object.entries(INTENT_CATEGORIES)) {
        for (let kw of keywords) {
            if (cleanQuery.includes(kw) || stringSimilarity(cleanQuery, kw) > 0.8) {
                detectedIntent = cat;
                break;
            }
        }
        if (detectedIntent) break;
    }

    Object.values(ETUS_DATA.stops).forEach(stop => {
        let bestScore = 0;
        let matchReason = "İsim benzerliği";
        const cleanStopName = normalizeText(stop.name);

        if (cleanStopName.includes(cleanQuery)) {
            bestScore = Math.max(bestScore, 95);
            matchReason = "Doğrudan durak adı eşleşmesi";
        }

        if (stop.aliases) {
            for (let alias of stop.aliases) {
                const cleanAlias = normalizeText(alias);
                if (cleanAlias === cleanQuery) {
                    bestScore = Math.max(bestScore, 100);
                    matchReason = `Tam lokasyon eşleşmesi: "${alias}"`;
                    break;
                } else if (cleanAlias.includes(cleanQuery) || cleanQuery.includes(cleanAlias)) {
                    bestScore = Math.max(bestScore, 88);
                    matchReason = `Kapsam eşleşmesi: "${alias}"`;
                } else {
                    const sim = stringSimilarity(cleanQuery, cleanAlias);
                    if (sim > 0.72) {
                        const fScore = sim * 85;
                        if (fScore > bestScore) {
                            bestScore = fScore;
                            matchReason = `Yazım hatası düzeltildi ("${alias}" kast edilmiş olabilir)`;
                        }
                    }
                }
            }
        }

        for (let token of userTokens) {
            if (token.length < 2) continue;
            if (stop.aliases) {
                for (let alias of stop.aliases) {
                    if (normalizeText(alias).includes(token)) {
                        bestScore = Math.max(bestScore, 75);
                        matchReason = `Kelime eşleşmesi: "${token}"`;
                    }
                }
            }
        }

        // Kategori Niyeti Eşleştirmesi
        if (detectedIntent) {
            if (detectedIntent === 'avm' && (stop.id === 'D_ERASTA' || stop.id === 'D_MARGI')) {
                bestScore = Math.max(bestScore, 90);
                matchReason = "💡 Alışveriş / Sinema / AVM niyeti algılandı";
            } else if (detectedIntent === 'hastane' && (stop.id === 'D_DEVLET_HASTANESI' || stop.id === 'D_BALKAN_KAMPUS')) {
                bestScore = Math.max(bestScore, 90);
                matchReason = "💡 Sağlık / Doktor / Hastane niyeti algılandı";
            } else if (detectedIntent === 'universite' && (stop.id === 'D_BALKAN_KAMPUS' || stop.id === 'D_AYSEKADIN')) {
                bestScore = Math.max(bestScore, 90);
                matchReason = "💡 Kampüs / Üniversite niyeti algılandı";
            } else if (detectedIntent === 'ulasim' && stop.id === 'D_OTOGAR') {
                bestScore = Math.max(bestScore, 95);
                matchReason = "💡 Şehirlerarası Otobüs / Otogar niyeti algılandı";
            } else if (detectedIntent === 'gezi_kafe' && (stop.id === 'D_KARAAĞAC' || stop.id === 'D_GAZIMIHAL')) {
                bestScore = Math.max(bestScore, 88);
                matchReason = "💡 Çay bahçesi / Tren garı / Gezi niyeti algılandı";
            } else if (detectedIntent === 'ibadet_tarih' && (stop.id === 'D_SELIMIYE' || stop.id === 'D_BAYEZID_KULLIYE')) {
                bestScore = Math.max(bestScore, 88);
                matchReason = "💡 Cami / Tarihi Külliye ziyareti algılandı";
            }
        }

        if (bestScore >= 50) {
            results.push({ stop: stop, score: bestScore, matchReason: matchReason });
        }
    });

    results.sort((a, b) => b.score - a.score);
    return results;
}

/**
 * Arama Öneri Listesini Çizme
 */
function renderSuggestions(matches) {
    const suggestionsBox = document.getElementById('suggestionsBox');
    suggestionsBox.innerHTML = '';

    if (matches.length === 0) {
        suggestionsBox.innerHTML = `<div class="p-3 text-xs text-gray-400">Edirne'de eşleşen durak veya yer bulunamadı.</div>`;
        suggestionsBox.classList.remove('hidden');
        return;
    }

    matches.slice(0, 5).forEach(item => {
        const stop = item.stop;
        const div = document.createElement('div');
        div.className = 'px-3.5 py-2.5 hover:bg-blue-50 cursor-pointer flex items-center justify-between border-b border-gray-100 last:border-none transition';
        div.innerHTML = `
            <div>
                <div class="text-xs font-bold text-gray-800 flex items-center gap-1.5">
                    <span>${stop.name}</span>
                </div>
                <div class="text-[11px] text-blue-600 font-medium">${item.matchReason}</div>
            </div>
            <span class="text-[10px] bg-blue-100 text-blue-800 font-bold px-2 py-0.5 rounded-full">%${Math.round(item.score)}</span>
        `;

        div.addEventListener('click', () => {
            document.getElementById('destinationInput').value = stop.name;
            selectedDestinationStop = stop;
            suggestionsBox.classList.add('hidden');
            calculateAndRenderJourney();
        });

        suggestionsBox.appendChild(div);
    });

    suggestionsBox.classList.remove('hidden');
}

/**
 * Doğrudan Hedef Belirleme (Harita Popup'ından vb.)
 */
window.setDestinationDirect = function(stopId) {
    const stop = ETUS_DATA.stops[stopId];
    if (!stop) return;
    document.getElementById('destinationInput').value = stop.name;
    selectedDestinationStop = stop;
    map.closePopup();
    calculateAndRenderJourney();
};

/**
 * Arama İcra Et
 */
function executeSearch() {
    const query = document.getElementById('destinationInput').value.trim();
    if (!query) {
        alert("Lütfen nereye gitmek istediğinizi yazınız (Örn: Tıp Fakültesi, Erasta, Otogar).");
        return;
    }

    const matches = searchStopsAndPlaces(query);
    if (matches.length > 0) {
        selectedDestinationStop = matches[0].stop;
        document.getElementById('suggestionsBox').classList.add('hidden');
        calculateAndRenderJourney();
    } else {
        alert(`"${query}" ile eşleşen bir durak bulunamadı. Lütfen önerilen yerlerden birini seçin.`);
    }
}

/**
 * 4. Rota, Otobüs ve Google Haritalar Mantığı
 */
function calculateAndRenderJourney() {
    if (!nearestOriginStop || !selectedDestinationStop) return;

    if (nearestOriginStop.id === selectedDestinationStop.id) {
        alert("Zaten gitmek istediğiniz durağın çok yakınındasınız!");
        return;
    }

    const originStopId = nearestOriginStop.id;
    const destStopId = selectedDestinationStop.id;

    const resultsArea = document.getElementById('resultsContainer');
    const emptyState = document.getElementById('emptyState');
    emptyState.classList.add('hidden');
    resultsArea.innerHTML = '';

    // Doğrudan giden ETUS hatlarını bul
    const directRoutes = [];

    ETUS_DATA.routes.forEach(route => {
        const fromIdx = route.stopIds.indexOf(originStopId);
        const toIdx = route.stopIds.indexOf(destStopId);

        if (fromIdx !== -1 && toIdx !== -1) {
            const isForward = fromIdx < toIdx;
            const subStops = isForward 
                ? route.stopIds.slice(fromIdx, toIdx + 1)
                : route.stopIds.slice(toIdx, fromIdx + 1).reverse();

            const stopCount = subStops.length;
            const busDurationMin = (stopCount - 1) * 3; // Ortalama durak başı 3 dk
            const walkDurationMin = Math.ceil(nearestOriginStop.distanceMeters / 80); // Yürüme hızı ~80m/dk
            const totalDurationMin = busDurationMin + walkDurationMin + 3;

            directRoutes.push({
                route: route,
                subStops: subStops,
                stopCount: stopCount,
                busDurationMin: busDurationMin,
                walkDurationMin: walkDurationMin,
                totalDurationMin: totalDurationMin,
                isForward: isForward
            });
        }
    });

    // Google Maps Transit URL'i (Canlı navigasyon için)
    // Origin: Kullanıcının gerçek koordinatları
    // Destination: Hedef durağın koordinatları
    const gmapsTransitUrl = `https://www.google.com/maps/dir/?api=1&origin=${userCoords[0]},${userCoords[1]}&destination=${selectedDestinationStop.coords[0]},${selectedDestinationStop.coords[1]}&travelmode=transit`;
    const gmapsWalkToStopUrl = `https://www.google.com/maps/dir/?api=1&origin=${userCoords[0]},${userCoords[1]}&destination=${nearestOriginStop.coords[0]},${nearestOriginStop.coords[1]}&travelmode=walking`;

    if (directRoutes.length > 0) {
        renderDirectJourneyResults(directRoutes, gmapsTransitUrl, gmapsWalkToStopUrl);
        // İlk rotayı haritada çiz
        drawCompleteJourneyOnMap(directRoutes[0]);
    } else {
        // Aktarmalı Hat Arama
        renderTransferJourney(originStopId, destStopId, gmapsTransitUrl);
    }
}

/**
 * Doğrudan Rota Sonuçlarını Kart Formatında Sunma + Google Maps Entegrasyonu
 */
function renderDirectJourneyResults(directList, gmapsTransitUrl, gmapsWalkToStopUrl) {
    const resultsArea = document.getElementById('resultsContainer');
    const primary = directList[0];

    const busBadges = directList.map(item => `
        <span class="inline-flex items-center px-3 py-1 rounded-lg text-white font-black text-sm shadow-sm" style="background-color: ${item.route.color}">
            ${item.route.name}
        </span>
    `).join(' ');

    const card = document.createElement('div');
    card.className = 'space-y-4';

    card.innerHTML = `
        <!-- GOOGLE MAPS AKSİYON KARTI -->
        <div class="bg-gradient-to-r from-blue-600 via-indigo-600 to-blue-700 text-white rounded-2xl p-4 sm:p-5 shadow-lg shadow-blue-500/25">
            <div class="flex items-center justify-between mb-2">
                <span class="text-[11px] font-bold tracking-wider uppercase bg-white/20 px-2 py-0.5 rounded-full">
                    Canlı Navigasyon
                </span>
                <span class="text-xs text-blue-100">Tahmini ~${primary.totalDurationMin} dk</span>
            </div>

            <h3 class="text-base sm:text-lg font-extrabold mb-1">
                ${selectedDestinationStop.name}
            </h3>
            <p class="text-xs text-blue-100 mb-4 leading-relaxed">
                Bu hedefe <strong>${directList.length} farklı ETUS hattı</strong> ile aktarmasız gidebilirsiniz.
            </p>

            <!-- Google Maps Butonu -->
            <a href="${gmapsTransitUrl}" target="_blank" rel="noopener noreferrer" 
               class="w-full bg-white hover:bg-slate-50 text-slate-900 font-bold py-3 px-4 rounded-xl flex items-center justify-center gap-2 shadow-md transition transform active:scale-[0.98]">
                <svg class="w-5 h-5 text-red-500" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/>
                </svg>
                <span>Google Maps'te Canlı Tarifi Başlat</span>
                <svg class="w-4 h-4 text-slate-400 ml-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                </svg>
            </a>
        </div>

        <!-- BİNEBİLECEĞİNİZ OTOBÜSLER -->
        <div class="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm">
            <div class="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Binebileceğiniz ETUS Otobüsleri:</div>
            <div class="flex flex-wrap gap-2 mb-3">
                ${busBadges}
            </div>
            <p class="text-xs text-slate-600">
                Bu hatlardan herhangi birine binebilirsiniz. Sefer aralıkları <strong>${primary.route.interval}</strong> arasındadır.
            </p>
        </div>

        <!-- ADIM ADIM YOLCULUK REHBERİ -->
        <div class="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm space-y-3">
            <div class="text-xs font-bold text-slate-400 uppercase tracking-wider">Adım Adım Yol Tarifi:</div>

            <!-- Adım 1: Yürüme -->
            <div class="flex items-start gap-3">
                <div class="w-7 h-7 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center font-bold text-xs shrink-0 mt-0.5">
                    1
                </div>
                <div class="text-xs flex-1">
                    <div class="font-bold text-slate-800">Biniş Durağına Yürüyün</div>
                    <div class="text-slate-500 mt-0.5">
                        Bulunduğunuz yerden <strong>${nearestOriginStop.name}</strong> durağına yürüyün 
                        <span class="text-amber-700 font-semibold">(~${nearestOriginStop.distanceMeters} metre, ${primary.walkDurationMin} dk)</span>.
                    </div>
                    <a href="${gmapsWalkToStopUrl}" target="_blank" class="inline-flex items-center gap-1 text-[11px] text-blue-600 hover:underline mt-1 font-medium">
                        Durağa yürüme tarifini Google Haritalar'da aç &rarr;
                    </a>
                </div>
            </div>

            <!-- Adım 2: Otobüs -->
            <div class="flex items-start gap-3">
                <div class="w-7 h-7 rounded-full bg-blue-100 text-blue-700 flex items-center justify-center font-bold text-xs shrink-0 mt-0.5">
                    2
                </div>
                <div class="text-xs flex-1">
                    <div class="font-bold text-slate-800">ETUS Otobüsüne Binin</div>
                    <div class="text-slate-500 mt-0.5">
                        <strong>${primary.route.name}</strong> (${primary.route.title}) otobüsüne binin.
                    </div>
                    <div class="mt-1 text-[11px] bg-slate-50 text-slate-600 p-2 rounded-lg border border-slate-100">
                        ⏱️ Yaklaşık <strong>${primary.busDurationMin} dk</strong> sürecek (${primary.stopCount} durak boyunca).
                    </div>
                </div>
            </div>

            <!-- Adım 3: İniş -->
            <div class="flex items-start gap-3">
                <div class="w-7 h-7 rounded-full bg-emerald-100 text-emerald-700 flex items-center justify-center font-bold text-xs shrink-0 mt-0.5">
                    3
                </div>
                <div class="text-xs flex-1">
                    <div class="font-bold text-slate-800">Hedef Durakta İnin</div>
                    <div class="text-slate-500 mt-0.5">
                        <strong>${selectedDestinationStop.name}</strong> durağında inin. Hedefinize ulaştınız!
                    </div>
                </div>
            </div>

            <!-- Durak Listesi Akordeonu -->
            <details class="mt-3 text-xs pt-2 border-t border-slate-100 group">
                <summary class="cursor-pointer font-medium text-blue-600 hover:text-blue-800 flex items-center justify-between select-none py-1">
                    <span>Geçilecek Durakların Tam Listesi (${primary.stopCount})</span>
                    <svg class="w-4 h-4 transform group-open:rotate-180 transition" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                    </svg>
                </summary>
                <div class="mt-2 pl-2 border-l-2 border-blue-300 space-y-1.5 max-h-44 overflow-y-auto">
                    ${primary.subStops.map((sId, i) => {
                        const st = ETUS_DATA.stops[sId];
                        const isFirst = i === 0;
                        const isLast = i === primary.subStops.length - 1;
                        return `
                            <div class="flex items-center gap-2 text-xs">
                                <span class="w-4 h-4 rounded-full ${isFirst ? 'bg-emerald-500 text-white' : (isLast ? 'bg-rose-500 text-white' : 'bg-slate-200 text-slate-600')} text-[9px] font-bold flex items-center justify-center">
                                    ${i + 1}
                                </span>
                                <span class="${isFirst || isLast ? 'font-bold text-slate-900' : 'text-slate-600'}">${st.name}</span>
                            </div>
                        `;
                    }).join('')}
                </div>
            </details>
        </div>
    `;

    resultsArea.appendChild(card);
}

/**
 * Aktarmalı Rota Durumu
 */
function renderTransferJourney(originStopId, destStopId, gmapsTransitUrl) {
    const resultsArea = document.getElementById('resultsContainer');
    let transfer = null;

    const fromRoutes = ETUS_DATA.routes.filter(r => r.stopIds.includes(originStopId));
    const toRoutes = ETUS_DATA.routes.filter(r => r.stopIds.includes(destStopId));

    for (let r1 of fromRoutes) {
        for (let r2 of toRoutes) {
            if (r1.id === r2.id) continue;
            const common = r1.stopIds.filter(id => r2.stopIds.includes(id));
            if (common.length > 0) {
                transfer = {
                    r1: r1,
                    r2: r2,
                    transferStop: ETUS_DATA.stops[common[0]]
                };
                break;
            }
        }
        if (transfer) break;
    }

    resultsArea.innerHTML = `
        <div class="bg-gradient-to-r from-amber-500 to-orange-600 text-white rounded-2xl p-4 sm:p-5 shadow-lg">
            <span class="text-[11px] font-bold tracking-wider uppercase bg-white/20 px-2 py-0.5 rounded-full mb-2 inline-block">
                1 Aktarmalı Güzergah
            </span>
            <h3 class="text-base font-bold mb-1">${selectedDestinationStop.name}</h3>
            <p class="text-xs text-amber-100 mb-4 leading-relaxed">
                Bu iki nokta arasında doğrudan sefer yapan tek bir otobüs bulunmuyor. Aktarma yaparak gidebilirsiniz.
            </p>
            <a href="${gmapsTransitUrl}" target="_blank" rel="noopener noreferrer" 
               class="w-full bg-white hover:bg-slate-50 text-slate-900 font-bold py-3 px-4 rounded-xl flex items-center justify-center gap-2 shadow-md transition">
                <svg class="w-5 h-5 text-red-500" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/>
                </svg>
                <span>Google Maps ile Canlı Aç</span>
            </a>
        </div>

        ${transfer ? `
            <div class="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm text-xs space-y-2 mt-3">
                <div class="font-bold text-slate-700">Aktarma Detayları:</div>
                <div class="p-2.5 bg-slate-50 rounded-xl space-y-2">
                    <div>1. <strong>${nearestOriginStop.name}</strong> durağından <span class="font-bold px-1.5 py-0.5 rounded text-white" style="background-color:${transfer.r1.color}">${transfer.r1.name}</span> hattına binin.</div>
                    <div>2. <strong>${transfer.transferStop.name}</strong> durağında inin (Aktarma Noktası).</div>
                    <div>3. Buradan <span class="font-bold px-1.5 py-0.5 rounded text-white" style="background-color:${transfer.r2.color}">${transfer.r2.name}</span> hattına geçip <strong>${selectedDestinationStop.name}</strong> durağına ulaşın.</div>
                </div>
            </div>
        ` : ''}
    `;
}

/**
 * 5. Haritada Yolculuğu Çizme (Yürüme + Otobüs Çizgisi)
 */
function drawCompleteJourneyOnMap(item) {
    routePolylineLayer.clearLayers();

    // 1. Kullanıcıdan biniş durağına yürüme kesik çizgisi (Gri/Mavi)
    const walkCoordinates = [userCoords, nearestOriginStop.coords];
    const walkPolyline = L.polyline(walkCoordinates, {
        color: '#64748B',
        weight: 3,
        dashArray: '5, 8',
        opacity: 0.8
    });
    routePolylineLayer.addLayer(walkPolyline);

    // 2. Otobüs rotası çizgisi (Renkli ve Kalın)
    const busCoordinates = item.subStops.map(id => ETUS_DATA.stops[id].coords);
    const busPolylineShadow = L.polyline(busCoordinates, {
        color: '#0F172A',
        weight: 7,
        opacity: 0.25,
        lineCap: 'round',
        lineJoin: 'round'
    });
    const busPolyline = L.polyline(busCoordinates, {
        color: item.route.color,
        weight: 5,
        opacity: 0.95,
        lineCap: 'round',
        lineJoin: 'round'
    });

    routePolylineLayer.addLayer(busPolylineShadow);
    routePolylineLayer.addLayer(busPolyline);

    // 3. Durak Pinleri
    // Biniş Durağı (Yeşil)
    const boardPin = createCustomPin('#10B981', `
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7"></path>
        </svg>
    `, 34);
    const boardMarker = L.marker(nearestOriginStop.coords, { icon: boardPin, zIndexOffset: 1000 });
    boardMarker.bindPopup(`<b>🟢 Biniş Durağınız:</b> ${nearestOriginStop.name}`);
    routePolylineLayer.addLayer(boardMarker);

    // İniş Durağı (Kırmızı)
    const dropPin = createCustomPin('#EF4444', `
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"></path>
        </svg>
    `, 34);
    const dropMarker = L.marker(selectedDestinationStop.coords, { icon: dropPin, zIndexOffset: 1000 });
    dropMarker.bindPopup(`<b>🔴 İniş Durağınız:</b> ${selectedDestinationStop.name}`);
    routePolylineLayer.addLayer(dropMarker);

    // Harita görünümünü tüm rotaya sığdır
    const allPoints = [userCoords, ...busCoordinates];
    map.fitBounds(L.polyline(allPoints).getBounds(), {
        padding: [60, 60],
        maxZoom: 15
    });
}
