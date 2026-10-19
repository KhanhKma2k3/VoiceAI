library controller_service;

import 'dart:async';
import 'dart:math';

import 'pc_control_models.dart';
import 'pc_control_socket.dart';

class PcCommandResult {
  PcCommandResult({required this.success, required this.message, this.data});
  final bool success;
  final String message;
  final Map<String, dynamic>? data;
}

class ControllerService {
  ControllerService({
    required String relayUrl,
    required String deviceName,
    required Future<String?> Function() getAuthToken,
  }) {
    _socket = PcControlSocket(
      relayUrl: relayUrl,
      role: 'controller',
      deviceName: deviceName,
      getAuthToken: getAuthToken,
    );
  }

  late final PcControlSocket _socket;
  final _agentsController = StreamController<List<PcAgentInfo>>.broadcast();
  final _pending = <String, Completer<PcCommandResult>>{};
  final _random = Random();

  /// Danh sách PC đang online của tài khoản hiện tại — cập nhật realtime.
  Stream<List<PcAgentInfo>> get agentsOnline => _agentsController.stream;

  Stream<bool> get connectionState => _socket.connectionState;

  Future<void> start() async {
    _socket.messages.listen(_handleMessage);
    await _socket.connect();
  }

  void stop() => _socket.dispose();

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'agents_online') {
      final list = (msg['agents'] as List)
          .map((a) => PcAgentInfo(a['id'] as String, a['name'] as String))
          .toList();
      _agentsController.add(list);
      return;
    }
    if (msg['type'] == 'result') {
      final requestId = msg['requestId'] as String?;
      final completer = requestId != null ? _pending.remove(requestId) : null;
      completer?.complete(PcCommandResult(
        success: msg['success'] as bool? ?? false,
        message: msg['message'] as String? ?? '',
        data: (msg['data'] as Map?)?.cast<String, dynamic>(),
      ));
    }
  }

  /// Gửi 1 lệnh tới PC. [targetAgentId] có thể bỏ trống nếu chỉ có 1 PC
  /// online — relay tự chọn.
  Future<PcCommandResult> sendCommand({
    required String action,
    Map<String, dynamic> params = const {},
    String? targetAgentId,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final requestId = 'req-${DateTime.now().millisecondsSinceEpoch}-${_random.nextInt(9999)}';
    final completer = Completer<PcCommandResult>();
    _pending[requestId] = completer;

    _socket.sendCommand(
      action: action,
      params: params,
      targetAgentId: targetAgentId,
      requestId: requestId,
    );

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(requestId);
        return PcCommandResult(success: false, message: 'Hết thời gian chờ phản hồi từ PC.');
      },
    );
  }
}
