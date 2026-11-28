import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/mentor_submission_service.dart';

/// Màn hình F11: Danh sách các bài đã nộp cho mentor kèm điểm số và nhận xét.
class SubmittedAssignmentsScreen extends StatefulWidget {
  const SubmittedAssignmentsScreen({super.key});

  @override
  State<SubmittedAssignmentsScreen> createState() =>
      _SubmittedAssignmentsScreenState();
}

class _SubmittedAssignmentsScreenState
    extends State<SubmittedAssignmentsScreen> {
  final _service = MentorSubmissionService();
  late Future<List<MentorSubmission>> _future = _service.loadSubmissions();

  void _reload() {
    setState(() {
      _future = _service.loadSubmissions();
    });
  }

  Future<void> _openDetail(MentorSubmission submission) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _SubmissionDetailScreen(
          submission: submission,
          service: _service,
        ),
      ),
    );
    if (deleted == true && mounted) {
      _reload();
    }
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bài đã nộp & Nhận xét')),
      body: FutureBuilder<List<MentorSubmission>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <MentorSubmission>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Chưa có bài nộp nào',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hãy thu âm ở màn hình Luyện nói & Thu âm rồi bấm "Nộp bài cho mentor" để lưu và xem nhận xét.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final reviewed = item.status == SubmissionStatus.reviewed;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openDetail(item),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  reviewed ? 'Đã có nhận xét' : 'Chờ mentor chấm',
                                ),
                                avatar: Icon(
                                  reviewed
                                      ? Icons.verified
                                      : Icons.hourglass_bottom,
                                  size: 16,
                                  color: reviewed ? Colors.green : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nộp lúc ${_formatDateTime(item.submittedAt)} • '
                            'Thời lượng ${_formatDuration(item.durationSeconds)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (item.note.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Ghi chú: ${item.note}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          if (reviewed && item.mentorScore != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Điểm: ${item.mentorScore}/100',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.mentorComment ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _openDetail(item),
                              icon: const Icon(Icons.play_circle_outline),
                              label: const Text('Nghe lại & Xem chi tiết'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SubmissionDetailScreen extends StatefulWidget {
  final MentorSubmission submission;
  final MentorSubmissionService service;

  const _SubmissionDetailScreen({
    required this.submission,
    required this.service,
  });

  @override
  State<_SubmissionDetailScreen> createState() =>
      _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState extends State<_SubmissionDetailScreen> {
  final _player = AudioPlayer();
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _disposed = false;
  bool _audioReady = false;
  bool _audioMissing = false;
  bool _isPlaying = false;
  bool _isDragging = false;
  double? _dragMs;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bindPlayerStreams();
    unawaited(_loadAudio());
  }

  void _bindPlayerStreams() {
    _durationSub = _player.durationStream.listen((d) {
      if (!mounted || _disposed || d == null) return;
      setState(() => _duration = d);
    });
    _positionSub = _player.positionStream.listen((pos) {
      if (!mounted || _disposed || _isDragging) return;
      setState(() => _position = pos);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted || _disposed) return;
      if (state.processingState == ProcessingState.completed) {
        unawaited(_onPlaybackCompleted());
        return;
      }
      if (_isPlaying != state.playing) {
        setState(() => _isPlaying = state.playing);
      }
    });
  }

  Future<void> _onPlaybackCompleted() async {
    if (_disposed) return;
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {}
    if (!mounted || _disposed) return;
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
  }

  Future<void> _loadAudio() async {
    final path = widget.submission.audioPath;
    if (path.isEmpty || !await File(path).exists()) {
      if (!mounted || _disposed) return;
      setState(() => _audioMissing = true);
      return;
    }
    try {
      final loaded = await _player.setFilePath(path);
      if (!mounted || _disposed) return;
      setState(() {
        _audioReady = true;
        _duration =
            loaded ?? Duration(seconds: widget.submission.durationSeconds);
      });
    } catch (_) {
      if (!mounted || _disposed) return;
      setState(() => _audioMissing = true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_durationSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_disposePlayer());
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    try {
      await _player.stop();
    } catch (_) {}
    await _player.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_audioReady) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_duration > Duration.zero && _position >= _duration) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa bài đã nộp?'),
        content: const Text(
          'Bản ghi âm đã lưu và nhận xét cho bài này sẽ bị xóa khỏi máy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _player.stop();
    } catch (_) {}
    await widget.service.deleteSubmission(widget.submission.id);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.submission;
    final reviewed = s.status == SubmissionStatus.reviewed;
    final totalDuration = _duration > Duration.zero
        ? _duration
        : Duration(seconds: s.durationSeconds);
    final maxMs = totalDuration.inMilliseconds > 0
        ? totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = (_isDragging && _dragMs != null
            ? _dragMs!
            : _position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs);
    final displayPos = Duration(milliseconds: currentMs.round());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết bài nộp'),
        actions: [
          IconButton(
            tooltip: 'Xóa bài nộp',
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(reviewed ? 'Đã có nhận xét' : 'Chờ mentor chấm'),
                avatar: Icon(
                  reviewed ? Icons.verified : Icons.hourglass_bottom,
                  size: 18,
                  color: reviewed ? Colors.green : null,
                ),
              ),
              Text(
                'Nộp lúc ${_formatDateTime(s.submittedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (s.promptText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.record_voice_over),
                title: const Text('Câu / nội dung luyện tập'),
                subtitle: Text(s.promptText),
              ),
            ),
          ],
          if (s.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('Ghi chú của bạn'),
                subtitle: Text(s.note),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bản ghi âm đã nộp', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  if (_audioMissing)
                    Text(
                      'Không tìm thấy file âm thanh trên máy.',
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  else
                    Row(
                      children: [
                        IconButton.filled(
                          tooltip: _isPlaying ? 'Tạm dừng' : 'Phát lại',
                          onPressed: _audioReady ? _togglePlay : null,
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            min: 0.0,
                            max: maxMs,
                            value: currentMs,
                            onChangeStart: _audioReady && totalDuration > Duration.zero
                                ? (_) => setState(() => _isDragging = true)
                                : null,
                            onChanged: _audioReady && totalDuration > Duration.zero
                                ? (value) => setState(() => _dragMs = value)
                                : null,
                            onChangeEnd: _audioReady && totalDuration > Duration.zero
                                ? (value) async {
                                    final target = Duration(
                                      milliseconds: value.round(),
                                    );
                                    setState(() {
                                      _isDragging = false;
                                      _dragMs = null;
                                      _position = target;
                                    });
                                    await _player.seek(target);
                                  }
                                : null,
                          ),
                        ),
                        Text(
                          '${_formatDuration(displayPos)} / ${_formatDuration(totalDuration)}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.school),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.mentorName ?? 'Nhận xét từ Mentor',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (s.mentorScore != null)
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          child: Text('${s.mentorScore}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.mentorComment ??
                        'Bài nộp đang chờ mentor nghe lại và phản hồi.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (s.reviewedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Đánh giá lúc ${_formatDateTime(s.reviewedAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

