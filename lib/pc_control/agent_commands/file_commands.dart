library file_commands;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../pc_control_models.dart';

class FileCommands {
  FileCommands({required this.sandboxDir, this.allowDeleteFiles = false});

  final String sandboxDir;
  final bool allowDeleteFiles;

  String _resolveSafePath(String? relativePath) {
    final normalizedSandbox = p.normalize(p.absolute(sandboxDir));
    final target = p.normalize(p.absolute(p.join(sandboxDir, relativePath ?? '.')));
    if (target != normalizedSandbox && !p.isWithin(normalizedSandbox, target)) {
      throw Exception('Đường dẫn nằm ngoài thư mục sandbox cho phép.');
    }
    return target;
  }

  Future<void> _ensureSandbox() async {
    final dir = Directory(sandboxDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<AgentCommandResult> listFiles(Map<String, dynamic> params) async {
    try {
      await _ensureSandbox();
      final target = _resolveSafePath(params['path'] as String?);
      final entries = await Directory(target)
          .list()
          .map((e) => {'name': p.basename(e.path), 'isDirectory': e is Directory})
          .toList();
      return AgentCommandResult.ok('Đã liệt kê ${entries.length} mục', data: {'entries': entries});
    } catch (e) {
      return AgentCommandResult.fail('Lỗi liệt kê file: $e');
    }
  }

  Future<AgentCommandResult> createFile(Map<String, dynamic> params) async {
    try {
      await _ensureSandbox();
      final target = _resolveSafePath(params['path'] as String?);
      await Directory(p.dirname(target)).create(recursive: true);
      await File(target).writeAsString(params['content'] as String? ?? '');
      return AgentCommandResult.ok('Đã tạo file ${params['path']}');
    } catch (e) {
      return AgentCommandResult.fail('Lỗi tạo file: $e');
    }
  }

  Future<AgentCommandResult> renameFile(Map<String, dynamic> params) async {
    try {
      final from = _resolveSafePath(params['path'] as String?);
      final to = _resolveSafePath(params['newPath'] as String?);
      if (!await File(from).exists() && !await Directory(from).exists()) {
        return AgentCommandResult.fail('Không tìm thấy ${params['path']}');
      }
      await File(from).rename(to);
      return AgentCommandResult.ok('Đã đổi tên/di chuyển thành ${params['newPath']}');
    } catch (e) {
      return AgentCommandResult.fail('Lỗi đổi tên file: $e');
    }
  }

  Future<AgentCommandResult> deleteFile(Map<String, dynamic> params) async {
    if (!allowDeleteFiles) {
      return AgentCommandResult.fail(
        'Chức năng xóa file đang bị TẮT trong cấu hình (allowDeleteFiles=false).',
      );
    }
    if (params['confirm'] != true) {
      return AgentCommandResult.fail('Cần xác nhận (confirm: true) trước khi xóa file.');
    }
    try {
      final target = _resolveSafePath(params['path'] as String?);
      final entity = FileSystemEntity.typeSync(target) == FileSystemEntityType.directory
          ? Directory(target)
          : File(target);
      if (!await entity.exists()) {
        return AgentCommandResult.fail('Không tìm thấy ${params['path']}');
      }
      await entity.delete(recursive: true);
      return AgentCommandResult.ok('Đã xóa ${params['path']}');
    } catch (e) {
      return AgentCommandResult.fail('Lỗi xóa file: $e');
    }
  }
}
