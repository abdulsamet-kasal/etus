import 'package:flutter_test/flutter_test.dart';
import 'package:etus_mobile/services/kentkart_health.dart';

/// Canlı sağlık katmanının en kritik davranışı: Kentkart yanıt şeması
/// değiştiğinde bunu **sessizce yutmamak** ve uygulamanın yerleşik veriye
/// düştüğünü görünür kılmak.
void main() {
  const endpoint = '/web/nearest/bus';
  const requiredKeys = {'result', 'busList', 'routeList'};
  const listKeys = {'busList', 'routeList'};

  late KentkartHealth health;

  setUp(() {
    health = KentkartHealth();
  });

  group('Başlangıç durumu', () {
    test('hiç istek yapılmadan durum unknown ve uyarı yok', () {
      expect(health.status, KentkartStatus.unknown);
      expect(health.userMessage, isNull);
      expect(health.hasSchemaDrift, isFalse);
      expect(health.liveDataAvailable, isTrue);
    });
  });

  group('Şema doğrulama', () {
    test('beklenen alanlar varsa sağlıklı sayılır', () {
      final report = health.validatePayload(
        endpoint: endpoint,
        body: const {
          'result': {'code': 0},
          'busList': [],
          'routeList': [],
        },
        requiredKeys: requiredKeys,
        listKeys: listKeys,
      );

      expect(report.ok, isTrue);
      expect(health.status, KentkartStatus.ok);
      expect(health.userMessage, isNull);
      expect(health.hasSchemaDrift, isFalse);
      expect(health.liveDataAvailable, isTrue);
    });

    test('zorunlu alan kaybolduğunda şema kayması tespit edilir', () {
      health.validatePayload(
        endpoint: endpoint,
        body: const {
          'result': {'code': 0},
          'busList': [],
          // 'routeList' yok — servis şeması değişmiş olabilir
        },
        requiredKeys: requiredKeys,
        listKeys: listKeys,
      );

      expect(health.status, KentkartStatus.degraded);
      expect(health.hasSchemaDrift, isTrue);
      expect(health.liveDataAvailable, isFalse);
      expect(health.userMessage, isNotNull);
      expect(health.userMessage, contains('routeList'));
      expect(health.driftDetails, contains('routeList alanı yanıtta yok'));
      expect(
        health.issues.any((i) => i.kind == KentkartIssueKind.schemaMissing),
        isTrue,
      );
    });

    test('alanın tipi değiştiğinde (liste yerine nesne) tespit edilir', () {
      health.validatePayload(
        endpoint: endpoint,
        body: const {
          'result': {'code': 0},
          'busList': {'beklenmeyen': true},
          'routeList': [],
        },
        requiredKeys: requiredKeys,
        listKeys: listKeys,
      );

      expect(health.hasSchemaDrift, isTrue);
      expect(health.status, KentkartStatus.degraded);
      expect(
        health.issues.any((i) => i.kind == KentkartIssueKind.schemaType),
        isTrue,
      );
      expect(health.driftDetails.first, contains('busList'));
    });

    test('şema düzeldiğinde uyarı temizlenir', () {
      void send(List<dynamic>? busList) {
        health.validatePayload(
          endpoint: endpoint,
          body: {
            'result': const {'code': 0},
            'busList': busList,
            'routeList': const [],
          },
          requiredKeys: requiredKeys,
          listKeys: listKeys,
        );
      }

      send(null); // busList yok → drift
      expect(health.hasSchemaDrift, isTrue);

      send(const []); // şema düzeldi
      expect(health.hasSchemaDrift, isFalse);
      expect(health.status, KentkartStatus.ok);
      expect(health.userMessage, isNull);
      expect(health.issues, isEmpty);
    });
  });

  group('Erişim sorunları', () {
    test('hiçbir uç yanıt vermiyorsa durum down olur', () {
      health.reportFailure(
        endpoint,
        'HTTP 500',
        kind: KentkartIssueKind.http,
      );

      expect(health.status, KentkartStatus.down);
      expect(health.consecutiveFailures, 1);
      expect(health.lastFailureAt, isNotNull);
      expect(health.userMessage, isNotNull);
      expect(health.issues.first.kind, KentkartIssueKind.http);
      expect(health.issues.first.label, 'HTTP');
    });

    test('ağ hatası daha önce tespit edilen şema kaymasını silmez', () {
      // 1) Şema bozuldu
      health.validatePayload(
        endpoint: endpoint,
        body: const {
          'result': {'code': 0},
          'busList': [],
        },
        requiredKeys: requiredKeys,
        listKeys: listKeys,
      );
      expect(health.hasSchemaDrift, isTrue);

      // 2) Ardından ağ tamamen düştü
      health.reportFailure(
        endpoint,
        'SocketException',
        kind: KentkartIssueKind.network,
      );

      expect(health.hasSchemaDrift, isTrue,
          reason: 'şema bilgisi korunmalı, yoksa drift uyarısı kaybolur');
      expect(health.driftDetails, contains('routeList alanı yanıtta yok'));
      expect(health.status, KentkartStatus.degraded);
    });

    test('başarılı istek ardışık hata sayacını sıfırlar', () {
      health.reportFailure(endpoint, 'zaman aşımı',
          kind: KentkartIssueKind.network);
      expect(health.consecutiveFailures, 1);

      health.reportSuccess(endpoint);
      expect(health.consecutiveFailures, 0);
      expect(health.status, KentkartStatus.ok);
      expect(health.lastSuccessAt, isNotNull);
      expect(health.issues, isEmpty);
    });
  });

  group('Bildirim', () {
    test('her durum değişiminde dinleyiciler tetiklenir', () {
      var notifications = 0;
      void listener() => notifications++;
      health.addListener(listener);

      health.validatePayload(
        endpoint: endpoint,
        body: const {
          'result': {'code': 0},
          'busList': [],
          'routeList': [],
        },
        requiredKeys: requiredKeys,
        listKeys: listKeys,
      );
      health.reportFailure(endpoint, 'hata');
      health.reset();

      health.removeListener(listener);
      expect(notifications, 3);
    });

    test('reset() durumu temizler', () {
      health.reportFailure(endpoint, 'hata');
      expect(health.status, KentkartStatus.down);

      health.reset();
      expect(health.status, KentkartStatus.unknown);
      expect(health.issues, isEmpty);
      expect(health.endpoints, isEmpty);
      expect(health.userMessage, isNull);
    });
  });
}
