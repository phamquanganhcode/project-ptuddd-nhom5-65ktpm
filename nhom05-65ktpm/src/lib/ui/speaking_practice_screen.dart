import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../data/lessons.dart';
import '../scoring/phonemes.dart';
import '../services/audio_recorder_service.dart';
import '../services/mentor_submission_service.dart';
import 'submitted_assignments_screen.dart';

/// Màn hình luyện tập nói với bộ thu âm WAV tạm vào bộ nhớ máy,
/// xử lý quyền micro và trình phát lại bản ghi âm của người học.
class SpeakingPracticeScreen extends StatefulWidget {
  const SpeakingPracticeScreen({super.key});

  @override
  State<SpeakingPracticeScreen> createState() => _SpeakingPracticeScreenState();
}

class _SpeakingPracticeScreenState extends State<SpeakingPracticeScreen>
    with WidgetsBindingObserver {
  final _recorderService = AudioRecorderService();
  final _submissionService = MentorSubmissionService();
  final _player = AudioPlayer();
  final _tts = FlutterTts();
  final _level = ValueNotifier<double>(0.0);
  late final List<String> _prompts = [
    for (final lesson in lessons) ...lesson.items,
  ];

  int _promptIndex = 0;
  Timer? _durationTimer;
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<Duration?>? _playerDurationSub;
  StreamSubscription<Duration>? _playerPositionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Duration _elapsed = Duration.zero;

  bool _isRecording = false;
  bool _isBusy = false;
  bool _isSubmitting = false;
  bool _disposed = false;

  bool _isPlaying = false;
  bool _isPlayerLoading = false;
  bool _isDraggingSlider = false;
  double? _dragPositionMs;
  Duration _playPosition = Duration.zero;
  Duration _playDuration = Duration.zero;

  MicrophonePermissionState? _permissionState;
  String? _statusMessage;
  String? _recordedPath;
  int? _recordedBytes;
  Duration? _recordedDuration;

  String get _currentPrompt => _prompts[_promptIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.4);
    _bindPlayerStreams();
    unawaited(_syncPermissionState());
  }

  void _bindPlayerStreams() {
    _playerDurationSub = _player.durationStream.listen((duration) {
      if (!mounted || _disposed || duration == null) return;
      setState(() => _playDuration = duration);
    });
    _playerPositionSub = _player.positionStream.listen((position) {
      if (!mounted || _disposed || _isDraggingSlider) return;
      setState(() => _playPosition = position);
    });
    _playerStateSub = _player.playerStateStream.listen((state) {
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
      _playPosition = Duration.zero;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPermissionState());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    unawaited(_amplitudeSub?.cancel());
    unawaited(_playerDurationSub?.cancel());
    unawaited(_playerPositionSub?.cancel());
    unawaited(_playerStateSub?.cancel());
    _level.dispose();
    unawaited(_tts.stop());
    final leftoverPath = _recordedPath;
    unawaited(_disposeResources(leftoverPath));
    super.dispose();
  }

  Future<void> _disposeResources(String? leftoverPath) async {
    try {
      await _player.stop();
    } catch (_) {}
    await _player.dispose();
    await _recorderService.dispose();
    await _recorderService.deleteTempFile(leftoverPath);
  }

  Future<void> _syncPermissionState() async {
    final perm = await _recorderService.checkMicrophonePermission();
    if (!mounted || _disposed) return;
    setState(() {
      _permissionState = perm;
      if (perm == MicrophonePermissionState.granted &&
          _statusMessage != null &&
          !_isRecording) {
        _statusMessage = null;
      }
    });
  }

  Future<void> _toggleRecording() async {
    if (_isBusy) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      final perm = await _recorderService.requestMicrophonePermission();
      if (!mounted || _disposed) return;
      setState(() => _permissionState = perm);

      if (perm == MicrophonePermissionState.permanentlyDenied ||
          perm == MicrophonePermissionState.restricted) {
        setState(
          () => _statusMessage =
              'Quyền micro đang bị chặn. Hãy mở Cài đặt để cấp quyền.',
        );
        await _showPermissionSettingsDialog();
        return;
      }

      if (perm != MicrophonePermissionState.granted) {
        setState(
          () => _statusMessage = 'Cần quyền microphone để thu âm giọng nói.',
        );
        _showSnack('Bạn cần cấp quyền micro để bắt đầu thu âm.');
        return;
      }

      await _tts.stop();
      await _stopPlayback();
      await _recorderService.deleteTempFile(_recordedPath);

      await _recorderService.startRecording();
      if (!mounted || _disposed) {
        await _recorderService.stopRecording();
        return;
      }

      _durationTimer?.cancel();
      await _amplitudeSub?.cancel();
      _level.value = 0.0;

      setState(() {
        _isRecording = true;
        _elapsed = Duration.zero;
        _recordedPath = null;
        _recordedBytes = null;
        _recordedDuration = null;
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _disposed || !_isRecording) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });

      _amplitudeSub = _recorderService.amplitudeStream().listen((value) {
        if (!_disposed) _level.value = value;
      }, onError: (_) {});
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _isRecording = false;
        _statusMessage = 'Không thể khởi động bộ thu âm: $e';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _isBusy = true);
    _durationTimer?.cancel();
    _durationTimer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    try {
      final path = await _recorderService.stopRecording();
      int? bytes;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          bytes = await file.length();
        }
      }
      if (!mounted || _disposed) {
        await _recorderService.deleteTempFile(path);
        return;
      }
      setState(() {
        _isRecording = false;
        _level.value = 0.0;
        _recordedPath = path;
        _recordedBytes = bytes;
        _recordedDuration = _elapsed;
        _playPosition = Duration.zero;
        _playDuration = _elapsed;
        _statusMessage = path == null
            ? 'Không tạo được file âm thanh.'
            : null;
      });
      if (path != null) {
        await _preparePlayback(path);
      }
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _isRecording = false;
        _level.value = 0.0;
        _statusMessage = 'Lỗi khi dừng thu âm: $e';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _preparePlayback(String path) async {
    if (!mounted || _disposed) return;
    setState(() => _isPlayerLoading = true);
    try {
      final duration = await _player.setFilePath(path);
      if (!mounted || _disposed) return;
      setState(() {
        _playPosition = Duration.zero;
        if (duration != null) {
          _playDuration = duration;
        }
      });
    } catch (e) {
      if (!mounted || _disposed) return;
      _showSnack('Không thể nạp file để phát lại: $e');
    } finally {
      if (mounted && !_disposed) {
        setState(() => _isPlayerLoading = false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    final path = _recordedPath;
    if (path == null || _isRecording || _isPlayerLoading) return;
    try {
      await _tts.stop();
      if (_isPlaying) {
        await _player.pause();
        return;
      }
      if (_player.processingState == ProcessingState.idle) {
        final duration = await _player.setFilePath(path);
        if (!mounted || _disposed) return;
        if (duration != null) {
          setState(() => _playDuration = duration);
        }
      } else if (_player.processingState == ProcessingState.completed ||
          (_playDuration > Duration.zero && _playPosition >= _playDuration)) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    } catch (e) {
      if (!mounted || _disposed) return;
      _showSnack('Không thể phát bản ghi âm: $e');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted || _disposed) return;
    setState(() {
      _isPlaying = false;
      _isDraggingSlider = false;
      _dragPositionMs = null;
      _playPosition = Duration.zero;
      _playDuration = Duration.zero;
    });
  }

  Future<void> _deleteRecordedFile() async {
    await _stopPlayback();
    final path = _recordedPath;
    await _recorderService.deleteTempFile(path);
    if (!mounted || _disposed) return;
    setState(() {
      _recordedPath = null;
      _recordedBytes = null;
      _recordedDuration = null;
    });
    _showSnack('Đã xóa file thu âm tạm.');
  }

  Future<void> _playSample() async {
    if (_isRecording) return;
    if (_isPlaying) {
      await _player.pause();
    }
    await _tts.speak(_currentPrompt);
  }

  Future<void> _openSubmittedAssignments() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_isPlaying) {
      await _player.pause();
    }
    if (!mounted || _disposed) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SubmittedAssignmentsScreen()),
    );
  }

  Future<void> _showSubmitDialog() async {
    final path = _recordedPath;
    if (path == null || _isRecording || _isSubmitting) return;
    if (_isPlaying) {
      await _player.pause();
    }
    if (!mounted || _disposed) return;

    final submissionInput = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _SubmitAssignmentDialog(defaultPrompt: _currentPrompt),
    );

    if (submissionInput == null || !mounted || _disposed) return;
    setState(() => _isSubmitting = true);
    try {
      final durationSecs = (_recordedDuration ?? _playDuration).inSeconds;
      await _submissionService.submitRecording(
        title: submissionInput.title,
        note: submissionInput.note,
        promptText: _currentPrompt,
        sourceAudioPath: path,
        durationSeconds: durationSecs,
        fileSizeBytes: _recordedBytes ?? 0,
      );
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Đã nộp bài cho mentor thành công.'),
            action: SnackBarAction(
              label: 'Xem bài đã nộp',
              onPressed: () => unawaited(_openSubmittedAssignments()),
            ),
          ),
        );
    } catch (e) {
      if (!mounted || _disposed) return;
      _showSnack('Không thể nộp bài: $e');
    } finally {
      if (mounted && !_disposed) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showPermissionSettingsDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cần quyền Microphone'),
        content: const Text(
          'Ứng dụng cần quyền truy cập micro để thu âm giọng nói luyện tập. '
          'Vui lòng bật quyền Micro trong phần Cài đặt ứng dụng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(_recorderService.openSettings());
            },
            child: const Text('Mở cài đặt'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _changePrompt(int delta) {
    if (_isRecording || _isBusy) return;
    setState(() {
      _promptIndex = (_promptIndex + delta) % _prompts.length;
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked =
        _permissionState == MicrophonePermissionState.permanentlyDenied ||
        _permissionState == MicrophonePermissionState.restricted;
    final totalDuration = _playDuration > Duration.zero
        ? _playDuration
        : (_recordedDuration ?? Duration.zero);
    final maxMs = totalDuration.inMilliseconds > 0
        ? totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = (_isDraggingSlider && _dragPositionMs != null
            ? _dragPositionMs!
            : _playPosition.inMilliseconds.toDouble())
        .clamp(0.0, maxMs);
    final displayPosition = Duration(milliseconds: currentMs.round());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Luyện nói & Thu âm'),
        actions: [
          IconButton(
            tooltip: 'Bài đã nộp & Nhận xét',
            onPressed: _openSubmittedAssignments,
            icon: const Icon(Icons.assignment_turned_in_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Câu mẫu ${_promptIndex + 1}/${_prompts.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentPrompt,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ipaOfText(_currentPrompt),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Câu trước',
                        onPressed: _isRecording
                            ? null
                            : () => _changePrompt(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      TextButton.icon(
                        onPressed: _isRecording ? null : _playSample,
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Nghe mẫu'),
                      ),
                      IconButton(
                        tooltip: 'Câu tiếp',
                        onPressed: _isRecording
                            ? null
                            : () => _changePrompt(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              _formatDuration(_elapsed),
              style: theme.textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: _isRecording
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<double>(
            valueListenable: _level,
            builder: (_, value, _) => Column(
              children: [
                LinearProgressIndicator(
                  value: _isRecording ? value : 0,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRecording
                      ? 'Đang thu âm (WAV 16 kHz)...'
                      : 'Nhấn nút micro để bắt đầu thu âm',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: FloatingActionButton.large(
              heroTag: 'f3_audio_recorder',
              tooltip: _isRecording ? 'Dừng thu âm' : 'Bắt đầu thu âm',
              backgroundColor: _isRecording ? theme.colorScheme.error : null,
              foregroundColor: _isRecording ? theme.colorScheme.onError : null,
              onPressed: _isBusy ? null : _toggleRecording,
              child: _isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Icon(_isRecording ? Icons.stop : Icons.mic),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    if (blocked) ...[
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _recorderService.openSettings(),
                        icon: const Icon(Icons.settings),
                        label: const Text('Mở cài đặt quyền'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (_recordedPath != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.audio_file, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đã lưu file thu âm tạm',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xóa file tạm',
                          onPressed: _deleteRecordedFile,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Tên file: ${p.basename(_recordedPath!)}'),
                    Text(
                      'Thời lượng: ${_formatDuration(_recordedDuration ?? Duration.zero)} • '
                      'Dung lượng: ${_formatBytes(_recordedBytes)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Đường dẫn: $_recordedPath',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        IconButton.filled(
                          tooltip: _isPlaying ? 'Tạm dừng' : 'Phát lại',
                          onPressed: _isRecording || _isPlayerLoading
                              ? null
                              : _togglePlayback,
                          icon: _isPlayerLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                ),
                        ),
                        Expanded(
                          child: Slider(
                            min: 0.0,
                            max: maxMs,
                            value: currentMs,
                            onChangeStart: totalDuration > Duration.zero
                                ? (_) => setState(() {
                                    _isDraggingSlider = true;
                                  })
                                : null,
                            onChanged: totalDuration > Duration.zero
                                ? (value) => setState(() {
                                    _dragPositionMs = value;
                                  })
                                : null,
                            onChangeEnd: totalDuration > Duration.zero
                                ? (value) async {
                                    final target = Duration(
                                      milliseconds: value.round(),
                                    );
                                    setState(() {
                                      _isDraggingSlider = false;
                                      _dragPositionMs = null;
                                      _playPosition = target;
                                    });
                                    await _player.seek(target);
                                  }
                                : null,
                          ),
                        ),
                        Text(
                          '${_formatDuration(displayPosition)} / ${_formatDuration(totalDuration)}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isRecording || _isSubmitting
                            ? null
                            : _showSubmitDialog,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _isSubmitting
                              ? 'Đang nộp bài...'
                              : 'Nộp bài cho mentor',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubmitAssignmentDialog extends StatefulWidget {
  final String defaultPrompt;

  const _SubmitAssignmentDialog({required this.defaultPrompt});

  @override
  State<_SubmitAssignmentDialog> createState() =>
      _SubmitAssignmentDialogState();
}

class _SubmitAssignmentDialogState extends State<_SubmitAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController = TextEditingController(
    text: 'Luyện nói: ${widget.defaultPrompt}',
  );
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _close([({String title, String note})? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _close((title: _titleController.text, note: _noteController.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nộp bài cho mentor'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề bài nộp',
                border: OutlineInputBorder(),
              ),
              maxLength: 80,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nhập tiêu đề' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Ghi chú cho mentor (tùy chọn)',
                hintText: 'Ví dụ: Em muốn kiểm tra âm cuối và ngữ điệu...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              maxLength: 200,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text('Hủy')),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send),
          label: const Text('Nộp bài'),
        ),
      ],
    );
  }
}
