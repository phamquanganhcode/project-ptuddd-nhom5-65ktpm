import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

enum MicrophonePermissionState { granted, denied, permanentlyDenied, restricted }

/// Quản lý xin quyền microphone và thu âm WAV (16 kHz mono) vào thư mục tạm.
class AudioRecorderService {
  final AudioRecorder _recorder;

  AudioRecorderService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  Future<MicrophonePermissionState> checkMicrophonePermission() async {
    return _mapStatus(await Permission.microphone.status);
  }

  Future<MicrophonePermissionState> requestMicrophonePermission() async {
    final current = await Permission.microphone.status;
    if (current.isGranted) return MicrophonePermissionState.granted;
    return _mapStatus(await Permission.microphone.request());
  }

  Future<bool> openSettings() => openAppSettings();

  Stream<double> amplitudeStream({
    Duration interval = const Duration(milliseconds: 120),
  }) {
    return _recorder.onAmplitudeChanged(interval).map((amp) {
      // dBFS thường nằm trong [-60, 0]; chuẩn hóa về [0.0, 1.0] để vẽ thanh mức âm.
      return ((amp.current + 60.0) / 60.0).clamp(0.0, 1.0);
    });
  }

  Future<String> startRecording() async {
    final tempDir = await getTemporaryDirectory();
    final filePath = p.join(
      tempDir.path,
      'speaking_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: filePath,
    );
    return filePath;
  }

  Future<String?> stopRecording() => _recorder.stop();

  Future<void> deleteTempFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Bỏ qua lỗi xóa file tạm khi dọn dẹp tài nguyên.
    }
  }

  Future<void> dispose() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } catch (_) {}
    await _recorder.dispose();
  }

  MicrophonePermissionState _mapStatus(PermissionStatus status) {
    if (status.isGranted) return MicrophonePermissionState.granted;
    if (status.isPermanentlyDenied) {
      return MicrophonePermissionState.permanentlyDenied;
    }
    if (status.isRestricted) return MicrophonePermissionState.restricted;
    return MicrophonePermissionState.denied;
  }
}

