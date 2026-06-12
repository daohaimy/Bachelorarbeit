import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_kontaktbericht/native_kontaktbericht.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('extract works', (tester) async {
    final res = extractFromFreeText('Telefonat mit Müller gestern um 10.');
    expect(res.isNotEmpty, true);
  });
}
