import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LAN-based real-time synchronization notifier for RePaperTodo.
///
/// Broadcasts lightweight UDP notifications across the local network when
/// local state/operation logs are updated, allowing nearby Windows and Android
/// instances to trigger instant incremental synchronization.
class LanSyncNotifier {
  LanSyncNotifier({
    int port = 23901,
    RawDatagramSocket? socketOverride,
  })  : _port = port,
        _socket = socketOverride;

  final int _port;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _isListening = false;

  /// Starts listening for LAN sync notifications on UDP port [_port].
  Future<void> startListening({
    required String selfDeviceId,
    required void Function(String remoteDeviceId, int maxSeq) onRemoteChange,
  }) async {
    if (_isListening) return;
    try {
      _socket ??= await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket?.broadcastEnabled = true;
      _isListening = true;

      _subscription = _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _socket?.receive();
          if (dg == null) return;
          try {
            final message = utf8.decode(dg.data);
            final json = jsonDecode(message) as Map<String, dynamic>;
            if (json['type'] == 'repapertodo_sync') {
              final remoteDeviceId = json['deviceId'] as String?;
              final maxSeq = json['maxSeq'] as int?;
              if (remoteDeviceId != null &&
                  remoteDeviceId != selfDeviceId &&
                  maxSeq != null) {
                onRemoteChange(remoteDeviceId, maxSeq);
              }
            }
          } catch (_) {
            // Ignore malformed UDP datagrams
          }
        }
      });
    } catch (_) {
      // Best-effort LAN binding
    }
  }

  /// Broadcasts a local change notification to the LAN.
  Future<void> notifyLocalChange({
    required String deviceId,
    required int maxSeq,
  }) async {
    try {
      final payload = utf8.encode(jsonEncode({
        'type': 'repapertodo_sync',
        'deviceId': deviceId,
        'maxSeq': maxSeq,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
      final target = InternetAddress('255.255.255.255');
      _socket?.send(payload, target, _port);
    } catch (_) {
      // Best-effort UDP send
    }
  }

  /// Closes the underlying UDP socket and releases resources.
  Future<void> dispose() async {
    _isListening = false;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}
