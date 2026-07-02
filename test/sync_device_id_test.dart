import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('normalizes device ids into stable filename-safe values', () {
    final longPrefix = List.filled(63, 'a').join();

    expect(normalizeSyncDeviceId(' Device A '), 'device-a');
    expect(normalizeSyncDeviceId('bad', fallback: ''), isEmpty);
    expect(normalizeSyncDeviceId('$longPrefix-tail'), longPrefix);
    expect(normalizeSyncDeviceId('${longPrefix}_tail'), longPrefix);
    expect(normalizeSyncDeviceId('${longPrefix}tail'), hasLength(64));
  });

  test('normalizes device sequence maps by highest valid sequence', () {
    expect(
      normalizeSyncDeviceSequences({
        ' Device A ': 2,
        'device-a': 3,
        'bad': 9,
        'device-b': 0,
      }),
      {'device-a': 3},
    );
  });
}
