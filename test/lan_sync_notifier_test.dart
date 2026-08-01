import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/sync/lan_sync_notifier.dart';

void main() {
  test('LanSyncNotifier initializes and disposes cleanly', () async {
    final notifier = LanSyncNotifier(port: 23905);
    await notifier.startListening(
      selfDeviceId: 'device-a',
      onRemoteChange: (deviceId, maxSeq) {},
    );
    await notifier.notifyLocalChange(deviceId: 'device-a', maxSeq: 10);
    await notifier.dispose();
  });
}
