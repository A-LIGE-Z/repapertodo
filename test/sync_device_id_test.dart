import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('normalizes device ids into stable filename-safe values', () {
    final shortestAccepted = List.filled(minSyncDeviceIdLength, 'a').join();
    final tooShort = shortestAccepted.substring(1);
    final longPrefix = List.filled(maxSyncDeviceIdLength - 1, 'a').join();

    expect(normalizeSyncDeviceId(' Device A '), 'device-a');
    expect(normalizeSyncDeviceId(tooShort, fallback: ''), isEmpty);
    expect(normalizeSyncDeviceId(shortestAccepted), shortestAccepted);
    expect(normalizeSyncDeviceId('$longPrefix-tail'), longPrefix);
    expect(normalizeSyncDeviceId('${longPrefix}_tail'), longPrefix);
    expect(
      normalizeSyncDeviceId('${longPrefix}tail'),
      hasLength(maxSyncDeviceIdLength),
    );
    expect(normalizeSyncDeviceIdForDisplay(' Phone Device '), 'phone-device');
    expect(normalizeSyncDeviceIdForDisplay(tooShort), tooShort);
    expect(normalizeSyncDeviceIdForDisplay('!!!'), isEmpty);
    expect(
      normalizeSyncDeviceIdForDisplay('${longPrefix}tail'),
      hasLength(maxSyncDeviceIdLength),
    );
  });

  test('normalizes device sequence maps by highest valid sequence', () {
    final longDeviceId = List.filled(maxSyncDeviceIdLength, 'a').join();

    expect(
      normalizeSyncDeviceSequences({
        ' Device A ': 2,
        'device-a': 3,
        'bad': 9,
        'device-b': 0,
        'device-c': maxSyncDeviceSequence + 1,
        'device-d': maxSyncDeviceSequence,
        '$longDeviceId-one': 1,
        '$longDeviceId-two': 4,
      }),
      {
        'device-a': 3,
        'device-d': maxSyncDeviceSequence,
        longDeviceId: 4,
      },
    );
  });

  test('checks device sequence range boundaries', () {
    final maxWireSequence = int.parse(
      List.filled(syncDeviceSequenceWireWidth, '9').join(),
    );

    expect(
      maxSyncDeviceSequence.toString(),
      hasLength(syncDeviceSequenceWireWidth),
    );
    expect(maxSyncDeviceSequence, maxWireSequence);
    expect(isSyncDeviceSequenceInRange(1), isTrue);
    expect(isSyncDeviceSequenceInRange(maxSyncDeviceSequence), isTrue);
    expect(isSyncDeviceSequenceInRange(0), isFalse);
    expect(isSyncDeviceSequenceInRange(-1), isFalse);
    expect(isSyncDeviceSequenceInRange(maxSyncDeviceSequence + 1), isFalse);
  });
}
