import 'dart:io';

import 'package:english_pronunciation_app/services/mentor_submission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late MentorSubmissionService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('f11_submission_test_');
    service = MentorSubmissionService(baseDirectory: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('nộp bài sao chép file sang lưu trữ lâu dài và lưu nhận xét mẫu', () async {
    final tempWav = File(p.join(tempRoot.path, 'temp_clip.wav'));
    await tempWav.writeAsBytes([1, 2, 3, 4, 5]);

    final saved = await service.submitRecording(
      title: 'Bài thuyết trình 1',
      note: 'Nhờ mentor xem giúp âm cuối',
      promptText: 'She sells sea shells',
      sourceAudioPath: tempWav.path,
      durationSeconds: 4,
      fileSizeBytes: 5,
    );

    // Xóa file tạm gốc nhưng file đã nộp phải còn nguyên vẹn.
    await tempWav.delete();
    expect(await File(saved.audioPath).exists(), isTrue);
    expect(saved.status, SubmissionStatus.reviewed);
    expect(saved.mentorScore, isNotNull);
    expect(saved.mentorComment, isNotEmpty);

    final loaded = await service.loadSubmissions();
    expect(loaded, hasLength(1));
    expect(loaded.single.title, 'Bài thuyết trình 1');
    expect(loaded.single.note, 'Nhờ mentor xem giúp âm cuối');
  });

  test('xóa bài nộp sẽ xóa luôn file âm thanh đã lưu', () async {
    final tempWav = File(p.join(tempRoot.path, 'temp_clip2.wav'));
    await tempWav.writeAsBytes([9, 8, 7]);

    final saved = await service.submitRecording(
      title: 'Bài test xóa',
      note: '',
      promptText: 'think',
      sourceAudioPath: tempWav.path,
      durationSeconds: 2,
      fileSizeBytes: 3,
    );

    expect(await File(saved.audioPath).exists(), isTrue);
    await service.deleteSubmission(saved.id);
    expect(await File(saved.audioPath).exists(), isFalse);
    expect(await service.loadSubmissions(), isEmpty);
  });
}

