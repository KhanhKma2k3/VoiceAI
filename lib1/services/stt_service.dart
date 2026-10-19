import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class SttService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentPath;

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      _currentPath = '${dir.path}/audio_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentPath!,
      );
    } else {
      throw Exception("Chưa cấp quyền truy cập Micro");
    }
  }

  Future<File?> stopRecording() async {
    final path = await _audioRecorder.stop();
    if (path == null) return null;
    return File(path);
  }

  // Gọi trực tiếp hàm transcribeAudio vừa thêm trong ApiService
  Future<String?> transcribe(File file) async {
    return await ApiService.transcribeAudio(file);
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}