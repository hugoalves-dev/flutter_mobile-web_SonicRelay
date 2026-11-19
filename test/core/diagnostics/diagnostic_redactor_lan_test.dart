import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/diagnostic_redactor.dart';

void main() {
  test('redactor removes lan secrets', () {
    const input =
        'Authorization: SonicRelay-Lan Zm9vYmFyYmF6cXV4 credential=c2VjcmV0 '
        'sec=ECAwQFBgcICQoA {"sec":"ECAwQFBgcICQoA","credential":"c2VjcmV0"} '
        'typed 0E85-HHQJ-20G3-0G2G';

    final result = DiagnosticRedactor.redact(input);

    expect(result, isNot(contains('Zm9vYmFyYmF6cXV4')));
    expect(result, isNot(contains('c2VjcmV0')));
    expect(result, isNot(contains('ECAwQFBgcICQoA')));
    expect(result, isNot(contains('0E85-HHQJ-20G3-0G2G')));
  });

  test('lan keys are sensitive', () {
    expect(DiagnosticRedactor.isSensitiveKey('credential'), isTrue);
    expect(DiagnosticRedactor.isSensitiveKey('sec'), isTrue);
  });
}
