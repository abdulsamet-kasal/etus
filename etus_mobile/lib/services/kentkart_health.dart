import 'package:flutter/foundation.dart';

/// Kentkart canlı servisinin sağlık durumu.
enum KentkartStatus {
  /// Henüz hiç istek yapılmadı.
  unknown,

  /// Son istekler beklendiği gibi yanıt verdi.
  ok,

  /// Kısmi sorun: bir uç hata verdi ya da yanıt şeması beklenenden farklı.
  degraded,

  /// Servise ulaşılamıyor (ağ/HTTP/auth).
  down,
}

/// Sorunun türü. Şema sorunları (drift) diğerlerinden ayrı ele alınır, çünkü
/// uygulamanın **sessizce** yerleşik veriye düşmesini engellemesi gereken şey
/// tam olarak budur.
enum KentkartIssueKind {
  /// Ağ/soket/zaman aşımı.
  network,

  /// HTTP 200 dışı yanıt.
  http,

  /// Yanıt JSON değil veya beklenen zarf yok (`result` gibi).
  payload,

  /// HTTP 200 ama `result.code != 0` şeklinde servis hatası.
  apiError,

  /// Alan eksik/kaybolmuş.
  schemaMissing,

  /// Alan var ama tipi değişmiş (örn. liste yerine nesne).
  schemaType,
}

/// Şema kaynaklı sorunlar (drift) bu türlerle temsil edilir.
const Set<KentkartIssueKind> _kSchemaKinds = {
  KentkartIssueKind.schemaMissing,
  KentkartIssueKind.schemaType,
};

/// Tek bir uç nokta için son doğrulama raporu.
class KentkartEndpointReport {
  final String endpoint;
  final DateTime checkedAt;
  final bool ok;

  /// Beklenen ama yanıtta bulunmayan alanlar.
  final List<String> missingFields;

  /// Alanın var olup tipi/şekli değişmiş olanları ("routeList: List beklenirdi, Map geldi").
  final List<String> typeChanges;

  /// Son hata mesajı (varsa).
  final String? error;

  const KentkartEndpointReport({
    required this.endpoint,
    required this.checkedAt,
    required this.ok,
    this.missingFields = const [],
    this.typeChanges = const [],
    this.error,
  });

  KentkartEndpointReport copyWith({
    DateTime? checkedAt,
    bool? ok,
    List<String>? missingFields,
    List<String>? typeChanges,
    String? error,
    bool clearError = false,
  }) {
    return KentkartEndpointReport(
      endpoint: endpoint,
      checkedAt: checkedAt ?? this.checkedAt,
      ok: ok ?? this.ok,
      missingFields: missingFields ?? this.missingFields,
      typeChanges: typeChanges ?? this.typeChanges,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Bu uçta şema bozulması tespit edildi mi?
  bool get schemaDrift => missingFields.isNotEmpty || typeChanges.isNotEmpty;
}

/// Kullanıcıya gösterilecek sorun kaydı.
class KentkartIssue {
  final String endpoint;
  final KentkartIssueKind kind;
  final String message;
  final DateTime at;

  const KentkartIssue({
    required this.endpoint,
    required this.kind,
    required this.message,
    required this.at,
  });

  bool get isSchemaDrift => _kSchemaKinds.contains(kind);

  /// Kullanıcı arayüzünde gösterilecek etiket.
  String get label {
    switch (kind) {
      case KentkartIssueKind.network:
        return 'Bağlantı';
      case KentkartIssueKind.http:
        return 'HTTP';
      case KentkartIssueKind.apiError:
        return 'Servis';
      case KentkartIssueKind.payload:
        return 'Yanıt biçimi';
      case KentkartIssueKind.schemaMissing:
        return 'Şema: eksik alan';
      case KentkartIssueKind.schemaType:
        return 'Şema: tip değişti';
    }
  }
}

/// Kentkart (service.kentkart.com) yanıtlarının beklenen şemaya uyup uymadığını
/// izleyen katman.
///
/// Neden gerekli: canlı veri çekilemediğinde uygulama yerleşik `etus_data.dart`
/// verisine düşüyor. Bu **doğru** bir davranış ama sessiz olduğunda kullanıcı
/// saatlerce eski veriyle yolculuk planladığını fark etmiyor. Bu sınıf şema
/// değişimini ve erişim sorunlarını kaydeder, arayüz de bunu görünür şekilde
/// bildirir.
class KentkartHealth extends ChangeNotifier {
  /// Uygulama genelinde paylaşılan örnek.
  static final KentkartHealth instance = KentkartHealth();

  KentkartHealth();

  static const int _maxIssues = 25;

  final Map<String, KentkartEndpointReport> _endpoints = {};
  final List<KentkartIssue> _issues = [];
  int _consecutiveFailures = 0;
  DateTime? _lastSuccessAt;
  DateTime? _lastFailureAt;

  /// Uç nokta bazlı son raporlar.
  Map<String, KentkartEndpointReport> get endpoints =>
      Map.unmodifiable(_endpoints);

  /// En yeni → en eski sırayla sorun kayıtları.
  List<KentkartIssue> get issues => List.unmodifiable(_issues);

  DateTime? get lastSuccessAt => _lastSuccessAt;
  DateTime? get lastFailureAt => _lastFailureAt;
  int get consecutiveFailures => _consecutiveFailures;

  /// En az bir uçta şema değişikliği tespit edildi mi?
  bool get hasSchemaDrift =>
      _endpoints.values.any((r) => r.schemaDrift) ||
      _issues.any((i) => i.isSchemaDrift);

  KentkartStatus get status {
    if (_endpoints.isEmpty) return KentkartStatus.unknown;
    final reports = _endpoints.values.toList();
    if (reports.any((r) => r.schemaDrift)) return KentkartStatus.degraded;
    if (reports.every((r) => !r.ok)) return KentkartStatus.down;
    if (_consecutiveFailures > 0) return KentkartStatus.degraded;
    return KentkartStatus.ok;
  }

  /// Canlı veri güvenilir şekilde kullanılabilir mi?
  bool get liveDataAvailable =>
      status != KentkartStatus.down && !hasSchemaDrift;

  /// Şema kayması olan alanların kısa özeti ("routeList alanı yok" gibi).
  List<String> get driftDetails {
    final out = <String>[];
    for (final r in _endpoints.values) {
      for (final f in r.missingFields) {
        out.add('$f alanı yanıtta yok');
      }
      for (final t in r.typeChanges) {
        out.add(t);
      }
    }
    return out;
  }

  String? get _lastSuccessLabel {
    final at = _lastSuccessAt;
    if (at == null) return null;
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Kullanıcıya gösterilecek uyarı metni; sorun yoksa `null`.
  String? get userMessage {
    switch (status) {
      case KentkartStatus.unknown:
      case KentkartStatus.ok:
        return null;
      case KentkartStatus.degraded:
        if (hasSchemaDrift) {
          final detail =
              driftDetails.isEmpty ? 'alan yapısı değişti' : driftDetails.first;
          return 'Kentkart canlı verisi beklenen biçimde gelmiyor ($detail). '
              'Canlı otobüs bilgileri güvenilmez olduğu için yerleşik ETUS verisi kullanılıyor.';
        }
        return 'Canlı veri güncellenemedi; son bilinen veriler gösteriliyor.'
            '${_lastSuccessLabel == null ? '' : ' (Son başarılı: $_lastSuccessLabel)'}';
      case KentkartStatus.down:
        return 'Kentkart canlı servisine ulaşılamıyor. Uygulama yerleşik ETUS hat verisiyle çalışıyor.';
    }
  }

  /// Kısa durum etiketi (rozet için).
  String get statusLabel {
    switch (status) {
      case KentkartStatus.unknown:
        return 'Canlı veri: bilinmiyor';
      case KentkartStatus.ok:
        return 'Canlı veri: bağlı';
      case KentkartStatus.degraded:
        return hasSchemaDrift ? 'Canlı veri: şema değişti' : 'Canlı veri: kısmi';
      case KentkartStatus.down:
        return 'Canlı veri: erişilemiyor';
    }
  }

  /// Bir yanıtın şemasını doğrular ve sonucu kaydeder.
  ///
  /// [requiredKeys] yanıtta bulunması zorunlu alanlar, [listKeys] ise liste
  /// olması gereken alanlardır. Eksik alan veya tip değişimi "şema kayması"
  /// olarak kaydedilir ve durum `degraded` olur.
  KentkartEndpointReport validatePayload({
    required String endpoint,
    required Map<String, dynamic> body,
    required Set<String> requiredKeys,
    Set<String> listKeys = const <String>{},
  }) {
    final missing = <String>[];
    for (final key in requiredKeys) {
      if (!body.containsKey(key) || body[key] == null) {
        missing.add(key);
      }
    }

    final typeChanges = <String>[];
    for (final key in listKeys) {
      final value = body[key];
      if (value != null && value is! List) {
        typeChanges.add('$key listesi yerine ${_typeName(value)} geldi');
      }
    }

    final ok = missing.isEmpty && typeChanges.isEmpty;
    final report = KentkartEndpointReport(
      endpoint: endpoint,
      checkedAt: DateTime.now(),
      ok: ok,
      missingFields: missing,
      typeChanges: typeChanges,
    );

    if (ok) {
      _recordSuccess(endpoint, report);
    } else {
      for (final field in missing) {
        _addIssue(KentkartIssue(
          endpoint: endpoint,
          kind: KentkartIssueKind.schemaMissing,
          message: '$endpoint yanıtında "$field" alanı yok',
          at: report.checkedAt,
        ));
      }
      for (final change in typeChanges) {
        _addIssue(KentkartIssue(
          endpoint: endpoint,
          kind: KentkartIssueKind.schemaType,
          message: '$endpoint yanıtında alan tipi değişti: $change',
          at: report.checkedAt,
        ));
      }
      _endpoints[endpoint] = report;
      notifyListeners();
    }
    return report;
  }

  /// Uç nokta için başarılı, şeması doğrulanmış bir yanıt kaydeder.
  void reportSuccess(String endpoint) {
    _recordSuccess(
      endpoint,
      KentkartEndpointReport(
        endpoint: endpoint,
        checkedAt: DateTime.now(),
        ok: true,
      ),
    );
  }

  /// Uç nokta için bir hatayı kaydeder.
  void reportFailure(
    String endpoint,
    Object error, {
    KentkartIssueKind kind = KentkartIssueKind.network,
  }) {
    final now = DateTime.now();
    final message = error.toString();

    // Ağ/HTTP hatası şema bilgisini geçersiz kılmaz: daha önce tespit edilen
    // eksik/tip değişmiş alanlar korunur, yoksa drift uyarısı kaybolurdu.
    final previous = _endpoints[endpoint];
    _endpoints[endpoint] = KentkartEndpointReport(
      endpoint: endpoint,
      checkedAt: now,
      ok: false,
      missingFields: previous?.missingFields ?? const [],
      typeChanges: previous?.typeChanges ?? const [],
      error: message,
    );

    _consecutiveFailures++;
    _lastFailureAt = now;
    _addIssue(KentkartIssue(
      endpoint: endpoint,
      kind: kind,
      message: '$endpoint başarısız: $message',
      at: now,
    ));
    notifyListeners();
  }

  void _recordSuccess(String endpoint, KentkartEndpointReport report) {
    _endpoints[endpoint] = report;
    _consecutiveFailures = 0;
    _lastSuccessAt = report.checkedAt;
    // Aynı uçtaki eski sorun kayıtlarını temizle (sorun çözüldü).
    _issues.removeWhere((i) => i.endpoint == endpoint);
    notifyListeners();
  }

  void _addIssue(KentkartIssue issue) {
    _issues.insert(0, issue);
    if (_issues.length > _maxIssues) {
      _issues.removeRange(_maxIssues, _issues.length);
    }
  }

  /// Testler ve "yeniden dene" için durumu sıfırlar.
  void reset() {
    _endpoints.clear();
    _issues.clear();
    _consecutiveFailures = 0;
    _lastSuccessAt = null;
    _lastFailureAt = null;
    notifyListeners();
  }

  static String _typeName(Object value) {
    if (value is Map) return 'nesne';
    if (value is List) return 'liste';
    if (value is String) return 'metin';
    if (value is num) return 'sayı';
    if (value is bool) return 'mantıksal değer';
    return value.runtimeType.toString();
  }
}
