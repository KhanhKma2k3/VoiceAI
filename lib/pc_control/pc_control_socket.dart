/// Kết nối WebSocket dùng chung cho cả bản điện thoại (role=controller) và
/// bản Windows Desktop (role=agent) của CÙNG app Flutter này.
///
/// Không cấu hình deviceId/token tay: `authToken` chính là JWT lấy từ
/// `ApiService.getToken()`. Relay Server verify token và tự nhóm các thiết
/// bị theo tài khoản.
library pc_control_socket;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class PcControlSocket {
  PcControlSocket({
    required this.relayUrl,
    required this.role, // 'agent' hoặc 'controller'
    required this.deviceName,
    required Future<String?> Function() getAuthToken,
    this.reconnectDelay = const Duration(seconds: 5),
  }) : _getAuthToken = getAuthToken;

  final String relayUrl;
  final String role;
  final String deviceName;
  final Duration reconnectDelay;
  final Future<String?> Function() _getAuthToken;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  /// Mọi message JSON nhận được từ relay (đã parse).
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// true khi đã 'registered' thành công với relay.
  Stream<bool> get connectionState => _connectionStateController.stream;

  Future<void> connect() async {
    if (_disposed) return;
    final token = await _getAuthToken();
    if (token == null) {
      // Chưa đăng nhập (hoặc vừa logout) -> thử lại sau, không báo lỗi ồn ào.
      _scheduleReconnect();
      return;
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      await _channel!.ready;

      _send({
        'type': 'register',
        'role': role,
        'authToken': token,
        'deviceName': deviceName,
      });

      _sub = _channel!.stream.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            if (msg['type'] == 'registered') {
              _connectionStateController.add(true);
            }
            _messageController.add(msg);
          } catch (_) {
            // bỏ qua message không hợp lệ
          }
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (_disposed) return;
    _connectionStateController.add(false);
    _sub?.cancel();
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, connect);
  }

  void _send(Map<String, dynamic> obj) {
    _channel?.sink.add(jsonEncode(obj));
  }

  /// Gửi lệnh điều khiển (dùng ở phía controller/điện thoại).
  void sendCommand({
    required String action,
    Map<String, dynamic> params = const {},
    String? targetAgentId,
    required String requestId,
  }) {
    _send({
      'type': 'command',
      if (targetAgentId != null) 'targetAgentId': targetAgentId,
      'requestId': requestId,
      'action': action,
      'params': params,
    });
  }

  /// Gửi kết quả thực thi lệnh (dùng ở phía agent/desktop).
  void sendResult({
    required String sourceConnId,
    required String requestId,
    required bool success,
    required String message,
    Map<String, dynamic>? data,
  }) {
    _send({
      'type': 'result',
      'sourceConnId': sourceConnId,
      'requestId': requestId,
      'success': success,
      'message': message,
      'data': data,
    });
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _messageController.close();
    _connectionStateController.close();
  }
}
