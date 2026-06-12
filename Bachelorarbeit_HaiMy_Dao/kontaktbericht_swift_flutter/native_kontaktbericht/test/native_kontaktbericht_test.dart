import 'package:test/test.dart';
import 'package:native_kontaktbericht/native_kontaktbericht.dart';

void main() {
  test('extractFromFreeText returns structured result', () {
    final res = extractFromFreeText(
      'Gestern um 10 Uhr Telefonat mit Müller: Angebot für 50 Lizenzen.',
    );

    // res ist Map<String, dynamic>
    expect(res, isA<Map<String, dynamic>>());

    expect(res.isNotEmpty, isTrue);

    if (res.containsKey('bericht')) {
      final bericht = res['bericht'];
      expect(bericht, isA<Map>());
      final b = (bericht as Map).cast<String, dynamic>();
      expect(b.containsKey('inhalt') || b.containsKey('ansprechpartner'), isTrue);
    }

    // Wenn pendingQuestion existiert, soll es String? sein:
    if (res.containsKey('pendingQuestion')) {
      final pq = res['pendingQuestion'];
      expect(pq == null || pq is String, isTrue);
    }
  });
}
