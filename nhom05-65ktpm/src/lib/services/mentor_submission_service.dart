import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum SubmissionStatus { pendingReview, reviewed }

/// Dữ liệu một bài luyện nói/thuyết trình đã nộp cho mentor.
class MentorSubmission {
  final String id;
  final String title;
  final String note;
  final String promptText;
  final String audioPath;
  final int durationSeconds;
  final int fileSizeBytes;
  final DateTime submittedAt;
  final SubmissionStatus status;
  final int? mentorScore;
  final String? mentorName;
  final String? mentorComment;
  final DateTime? reviewedAt;

  const MentorSubmission({
    required this.id,
    required this.title,
    required this.note,
    required this.promptText,
    required this.audioPath,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.submittedAt,
    required this.status,
    this.mentorScore,
    this.mentorName,
    this.mentorComment,
    this.reviewedAt,
  });

  factory MentorSubmission.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'pendingReview';
    final status = SubmissionStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => SubmissionStatus.pendingReview,
    );
    return MentorSubmission(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Bài thu âm',
      note: json['note'] as String? ?? '',
      promptText: json['promptText'] as String? ?? '',
      audioPath: json['audioPath'] as String? ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      submittedAt: DateTime.parse(json['submittedAt'] as String),
      status: status,
      mentorScore: (json['mentorScore'] as num?)?.toInt(),
      mentorName: json['mentorName'] as String?,
      mentorComment: json['mentorComment'] as String?,
      reviewedAt: json['reviewedAt'] != null
          ? DateTime.parse(json['reviewedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'promptText': promptText,
    'audioPath': audioPath,
    'durationSeconds': durationSeconds,
    'fileSizeBytes': fileSizeBytes,
    'submittedAt': submittedAt.toIso8601String(),
    'status': status.name,
    'mentorScore': mentorScore,
    'mentorName': mentorName,
    'mentorComment': mentorComment,
    'reviewedAt': reviewedAt?.toIso8601String(),
  };
}

/// Lưu trữ cục bộ danh sách bài đã nộp và sao chép file .wav sang thư mục lâu dài.
class MentorSubmissionService {
  final Directory? _baseDirectory;

  MentorSubmissionService({Directory? baseDirectory})
    : _baseDirectory = baseDirectory;

  Future<Directory> _resolveBaseDirectory() async =>
      _baseDirectory ?? await getApplicationDocumentsDirectory();

  Future<File> _indexFile() async {
    final dir = await _resolveBaseDirectory();
    return File(p.join(dir.path, 'mentor_submissions.json'));
  }

  Future<Directory> _audioDirectory() async {
    final dir = await _resolveBaseDirectory();
    final audioDir = Directory(p.join(dir.path, 'mentor_submissions'));
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  Future<List<MentorSubmission>> loadSubmissions() async {
    final file = await _indexFile();
    if (!await file.exists()) return const [];
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded
          .cast<Map<String, dynamic>>()
          .map(MentorSubmission.fromJson)
          .toList();
      list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<MentorSubmission> submitRecording({
    required String title,
    required String note,
    required String promptText,
    required String sourceAudioPath,
    required int durationSeconds,
    required int fileSizeBytes,
  }) async {
    final sourceFile = File(sourceAudioPath);
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Không tìm thấy file âm thanh để nộp.');
    }

    final now = DateTime.now();
    final id = 'sub_${now.millisecondsSinceEpoch}';
    final audioDir = await _audioDirectory();
    final ext = p.extension(sourceAudioPath).isEmpty
        ? '.wav'
        : p.extension(sourceAudioPath);
    final savedAudioPath = p.join(audioDir.path, '$id$ext');
    await sourceFile.copy(savedAudioPath);

    final review = _buildSampleMentorReview(
      promptText: promptText,
      durationSeconds: durationSeconds,
      note: note,
    );

    final submission = MentorSubmission(
      id: id,
      title: title.trim(),
      note: note.trim(),
      promptText: promptText,
      audioPath: savedAudioPath,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      submittedAt: now,
      status: SubmissionStatus.reviewed,
      mentorScore: review.score,
      mentorName: 'Mentor Minh Anh',
      mentorComment: review.comment,
      reviewedAt: now,
    );

    final current = await loadSubmissions();
    await _saveAll([submission, ...current]);
    return submission;
  }

  Future<void> deleteSubmission(String id) async {
    final current = await loadSubmissions();
    final target = current.where((s) => s.id == id).toList();
    final remaining = current.where((s) => s.id != id).toList();
    await _saveAll(remaining);

    for (final item in target) {
      if (item.audioPath.isEmpty) continue;
      try {
        final audioFile = File(item.audioPath);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _saveAll(List<MentorSubmission> submissions) async {
    final file = await _indexFile();
    final encoded = jsonEncode([for (final s in submissions) s.toJson()]);
    await file.writeAsString(encoded, flush: true);
  }

  ({int score, String comment}) _buildSampleMentorReview({
    required String promptText,
    required int durationSeconds,
    required String note,
  }) {
    if (durationSeconds < 2) {
      return (
        score: 72,
        comment:
            'Bản thu hơi ngắn nên chưa nghe hết độ ngân và âm cuối của câu '
            '"$promptText". Bạn hãy nói chậm rãi hơn và giữ nhịp đều ở lượt tới nhé.',
      );
    }
    final noteHint = note.trim().isEmpty
        ? ''
        : ' Mentor đã xem ghi chú của bạn và nhận thấy phần trọng âm khá ổn.';
    return (
      score: 86,
      comment:
          'Phát âm rõ ràng và ngữ điệu tự nhiên ở câu "$promptText". '
          'Chú ý bật nhẹ các phụ âm cuối /t/, /s/, /d/ để câu tròn chữ hơn.$noteHint',
    );
  }
}
