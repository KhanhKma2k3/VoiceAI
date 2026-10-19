library media_commands;

import 'dart:io';

import '../pc_control_models.dart';

class MediaCommands {
  static const _vkCodes = {
    'play_pause': 0xB3,
    'next': 0xB0,
    'prev': 0xB1,
    'volume_up': 0xAF,
    'volume_down': 0xAE,
    'mute': 0xAD,
  };

  Future<AgentCommandResult> mediaControl(Map<String, dynamic> params) async {
    final action = (params['action'] as String? ?? '').toLowerCase().trim();
    final vk = _vkCodes[action];
    if (vk == null) {
      return AgentCommandResult.fail(
        "Hành động media '${params['action']}' không được hỗ trợ. Chỉ hỗ trợ: ${_vkCodes.keys.join(', ')}",
      );
    }

    final vkHex = vk.toRadixString(16);
    final script = '''
Add-Type -TypeDefinition '
using System;
using System.Runtime.InteropServices;
public class VoiceAgentInput {
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
';
\$vk = [Convert]::ToByte("$vkHex", 16);
[VoiceAgentInput]::keybd_event(\$vk, 0, 0, [UIntPtr]::Zero);
Start-Sleep -Milliseconds 50;
[VoiceAgentInput]::keybd_event(\$vk, 0, 2, [UIntPtr]::Zero);
''';

    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      );
      if (result.exitCode != 0) {
        return AgentCommandResult.fail('Lỗi điều khiển media: ${result.stderr}');
      }
      return AgentCommandResult.ok('Đã thực hiện: $action');
    } catch (e) {
      return AgentCommandResult.fail('Lỗi điều khiển media: $e');
    }
  }
}
