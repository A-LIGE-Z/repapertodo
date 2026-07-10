import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/model/external_uri_targets.dart';

void main() {
  test('normalizes supported external URI targets', () {
    expect(
      normalizeExternalUriTarget(
        ' www.example.com/paper ',
        allowBareWww: true,
      ),
      'https://www.example.com/paper',
    );
    expect(
      normalizeExternalUriTarget('HTTPS://example.com/paper'),
      'HTTPS://example.com/paper',
    );
    expect(
      normalizeExternalUriTarget('mailto:paper@example.com'),
      'mailto:paper@example.com',
    );
    expect(
      normalizeExternalUriTarget('https://example.com/%E2%82%ACpath'),
      'https://example.com/%E2%82%ACpath',
    );
  });

  test('rejects unsafe external URI targets', () {
    for (final target in [
      '',
      'www.example.com/paper',
      'ftp://example.com/file',
      'javascript:alert(1)',
      'https:///missing-host',
      'https://user@example.com/paper',
      'https://example.com%3A443/paper',
      'https://example.com/%',
      'https://example.com/%A',
      'https://example.com/%ZZ',
      'https://example.com/%0Apaper',
      'https://example.com/%C2%85paper',
      'https://example.com/\u0085paper',
      '\nhttps://example.com/paper',
      'https://example.com/paper\t',
      'mailto:',
      'mailto:paper%ZZ@example.com',
      'mailto:?subject=paper',
      'mailto://paper@example.com',
      'mailto://example.com/paper@example.com',
    ]) {
      expect(normalizeExternalUriTarget(target), isNull, reason: target);
    }
    expect(
      normalizeExternalUriTarget(
        ' \nwww.example.com/paper ',
        allowBareWww: true,
      ),
      isNull,
    );
  });

  test('detects encoded authority separators only for web URI authorities', () {
    expect(
      hasEncodedExternalUriAuthoritySeparator(
        'https://example.com%3A443/paper',
      ),
      true,
    );
    expect(
      hasEncodedExternalUriAuthoritySeparator(
        'https://example.com/%3A/path',
      ),
      false,
    );
    expect(
      hasEncodedExternalUriAuthoritySeparator('mailto:paper%40example.com'),
      false,
    );
  });
}
