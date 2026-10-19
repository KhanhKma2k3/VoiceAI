/// Các model dữ liệu dùng chung cho tính năng Điều khiển PC.
library pc_control_models;

class AgentCommandResult {
  AgentCommandResult({required this.success, required this.message, this.data});

  factory AgentCommandResult.ok(String message, {Map<String, dynamic>? data}) =>
      AgentCommandResult(success: true, message: message, data: data);

  factory AgentCommandResult.fail(String message, {Map<String, dynamic>? data}) =>
      AgentCommandResult(success: false, message: message, data: data);

  final bool success;
  final String message;
  final Map<String, dynamic>? data;
}

/// 1 máy tính (agent) đang online, cùng tài khoản với điện thoại.
class PcAgentInfo {
  PcAgentInfo(this.id, this.name);
  final String id;
  final String name;
}
