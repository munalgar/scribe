import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import '../models/batch_item.dart';
import '../proto/scribe.pb.dart' as pb;
import '../proto/scribe.pbgrpc.dart';
import '../services/grpc_client.dart';

class TranscriptionProvider extends ChangeNotifier {
  ScribeGrpcClient? _client;

  List<pb.JobSummary> _jobs = [];
  String? _activeJobId;
  JobStatus _activeJobStatus = JobStatus.JOB_STATUS_UNSPECIFIED;
  List<pb.Segment> _segments = [];
  double _progress = 0.0;
  bool _isTranscribing = false;
  String? _error;
  StreamSubscription? _streamSubscription;

  // Batch state
  List<String> _selectedFilePaths = [];
  List<BatchItem> _batchQueue = [];
  int _currentBatchIndex = -1;

  // Stored batch options (set once at start)
  String _batchModel = 'base';
  bool _batchEnableGpu = true;
  String? _batchLanguage;
  String? _batchTranslateToLanguage;

  // Getters - existing
  List<pb.JobSummary> get jobs => _jobs;
  String? get activeJobId => _activeJobId;
  JobStatus get activeJobStatus => _activeJobStatus;
  List<pb.Segment> get segments => _segments;
  double get progress => _progress;
  bool get isTranscribing => _isTranscribing;
  String? get error => _error;

  // Getters - batch
  List<String> get selectedFilePaths => _selectedFilePaths;
  List<BatchItem> get batchQueue => _batchQueue;
  int get currentBatchIndex => _currentBatchIndex;
  bool get isBatchMode => _batchQueue.length > 1;
  int get totalBatchFiles => _batchQueue.length;
  int get completedBatchFiles =>
      _batchQueue.where((item) => item.isTerminal).length;
  bool get isBatchComplete =>
      _batchQueue.isNotEmpty && _batchQueue.every((item) => item.isTerminal);

  // Backward-compatible getter
  String? get selectedFilePath =>
      _currentBatchIndex >= 0 && _currentBatchIndex < _batchQueue.length
      ? _batchQueue[_currentBatchIndex].filePath
      : (_selectedFilePaths.isNotEmpty ? _selectedFilePaths.first : null);

  void updateClient(ScribeGrpcClient? client) {
    _client = client;
  }

  // --- File selection ---

  void selectFile(String path) {
    _selectedFilePaths = [path];
    notifyListeners();
  }

  void selectFiles(List<String> paths) {
    _selectedFilePaths = List.from(paths);
    notifyListeners();
  }

  void addFiles(List<String> paths) {
    for (final path in paths) {
      if (!_selectedFilePaths.contains(path)) {
        _selectedFilePaths.add(path);
      }
    }
    notifyListeners();
  }

  void removeSelectedFile(int index) {
    if (index >= 0 && index < _selectedFilePaths.length) {
      _selectedFilePaths.removeAt(index);
      notifyListeners();
    }
  }

  // --- Transcription ---

  Future<void> startTranscription({
    required String filePath,
    String model = 'base',
    bool enableGpu = true,
    String? language,
    String? translateToLanguage,
  }) async {
    _selectedFilePaths = [filePath];
    await startBatchTranscription(
      model: model,
      enableGpu: enableGpu,
      language: language,
      translateToLanguage: translateToLanguage,
    );
  }

  Future<void> startBatchTranscription({
    String model = 'base',
    bool enableGpu = true,
    String? language,
    String? translateToLanguage,
  }) async {
    if (_client == null || _selectedFilePaths.isEmpty) return;

    // Store batch options
    _batchModel = model;
    _batchEnableGpu = enableGpu;
    _batchLanguage = language;
    _batchTranslateToLanguage = translateToLanguage;

    // Build queue
    _batchQueue = _selectedFilePaths
        .map((path) => BatchItem(filePath: path))
        .toList();
    _currentBatchIndex = -1;
    _error = null;
    _isTranscribing = true;
    notifyListeners();

    await _processNextInQueue();
  }

  Future<void> _processNextInQueue() async {
    // Safety: if cancelled externally, stop processing
    if (!_isTranscribing) return;

    final nextIndex = _batchQueue.indexWhere(
      (item) => item.status == BatchItemStatus.pending,
    );

    if (nextIndex == -1) {
      // Batch complete
      _isTranscribing = false;
      _currentBatchIndex = -1;
      loadJobs();
      notifyListeners();
      return;
    }

    _currentBatchIndex = nextIndex;
    final item = _batchQueue[nextIndex];
    item.status = BatchItemStatus.running;

    // Reset per-file tracking
    _activeJobId = null;
    _activeJobStatus = JobStatus.JOB_STATUS_UNSPECIFIED;
    _segments = [];
    _progress = 0.0;
    _error = null;
    notifyListeners();

    try {
      final response = await _client!.startTranscription(
        filePath: item.filePath,
        model: _batchModel,
        enableGpu: _batchEnableGpu,
        language: _batchLanguage,
        translateToLanguage: _batchTranslateToLanguage,
      );

      item.jobId = response.jobId;
      _activeJobId = response.jobId;
      _activeJobStatus = response.status;
      notifyListeners();

      _listenToStream(response.jobId, item);
    } on GrpcError catch (e) {
      item.status = BatchItemStatus.failed;
      item.error = e.message ?? 'Failed to start transcription';
      _error = item.error;
      notifyListeners();

      // Continue to next file despite failure
      await _processNextInQueue();
    }
  }

  void _listenToStream(String jobId, BatchItem item) {
    _streamSubscription?.cancel();
    final stream = _client!.streamTranscription(jobId);
    bool advancingQueue = false;

    _streamSubscription = stream.listen(
      (event) {
        _activeJobStatus = event.status;
        _progress = event.progress;
        item.progress = event.progress;

        if (event.hasSegment()) {
          final seg = event.segment;
          if (item.segments.every((s) => s.index != seg.index)) {
            item.segments = [...item.segments, seg];
            _segments = item.segments;
          }
        }

        if (event.hasError() && event.error.isNotEmpty) {
          item.error = event.error;
          _error = event.error;
        }

        // Terminal states - advance to next file
        if (event.status == JobStatus.COMPLETED ||
            event.status == JobStatus.FAILED ||
            event.status == JobStatus.CANCELED) {
          item.status = _mapJobStatusToBatchStatus(event.status);
          notifyListeners();
          if (!advancingQueue) {
            advancingQueue = true;
            unawaited(_processNextInQueue());
          }
          return;
        }

        notifyListeners();
      },
      onError: (e) {
        item.status = BatchItemStatus.failed;
        item.error = e is GrpcError
            ? (e.message ?? 'Stream error')
            : e.toString();
        _error = item.error;
        notifyListeners();
        if (!advancingQueue) {
          advancingQueue = true;
          unawaited(_processNextInQueue());
        }
      },
      onDone: () {
        if (!item.isTerminal) {
          item.status = BatchItemStatus.failed;
          item.error = 'Stream closed unexpectedly';
          notifyListeners();
          if (!advancingQueue) {
            advancingQueue = true;
            unawaited(_processNextInQueue());
          }
        }
      },
    );
  }

  BatchItemStatus _mapJobStatusToBatchStatus(JobStatus status) {
    switch (status) {
      case JobStatus.COMPLETED:
        return BatchItemStatus.completed;
      case JobStatus.FAILED:
        return BatchItemStatus.failed;
      case JobStatus.CANCELED:
        return BatchItemStatus.canceled;
      default:
        return BatchItemStatus.running;
    }
  }

  // --- Cancellation ---

  Future<void> cancelTranscription() async {
    if (isBatchMode) {
      await cancelBatch();
      return;
    }
    if (_client == null || _activeJobId == null) return;
    try {
      await _client!.cancelJob(_activeJobId!);
      _isTranscribing = false;
      _activeJobStatus = JobStatus.CANCELED;
      if (_batchQueue.isNotEmpty && _currentBatchIndex >= 0) {
        _batchQueue[_currentBatchIndex].status = BatchItemStatus.canceled;
      }
      notifyListeners();
    } on GrpcError catch (e) {
      _error = e.message ?? 'Failed to cancel';
      notifyListeners();
    }
  }

  Future<void> cancelBatch() async {
    if (_activeJobId != null && _client != null) {
      try {
        await _client!.cancelJob(_activeJobId!);
      } on GrpcError catch (_) {
        // Best effort
      }
    }

    for (final item in _batchQueue) {
      if (!item.isTerminal) {
        item.status = BatchItemStatus.canceled;
      }
    }

    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isTranscribing = false;
    _activeJobStatus = JobStatus.CANCELED;
    loadJobs();
    notifyListeners();
  }

  void removePendingItem(int index) {
    if (index >= 0 &&
        index < _batchQueue.length &&
        _batchQueue[index].status == BatchItemStatus.pending) {
      _batchQueue[index].status = BatchItemStatus.canceled;
      notifyListeners();
    }
  }

  // --- Jobs ---

  Future<void> loadJobs() async {
    if (_client == null) return;
    try {
      final response = await _client!.listJobs();
      _jobs = response.jobs.toList();
      notifyListeners();
    } on GrpcError catch (e) {
      _error = e.message ?? 'Failed to load jobs';
      notifyListeners();
    }
  }

  Future<void> deleteJob(String jobId) async {
    if (_client == null) return;
    try {
      await _client!.deleteJob(jobId);
      _jobs = _jobs.where((j) => j.jobId != jobId).toList();
      notifyListeners();
    } on GrpcError catch (e) {
      _error = e.message ?? 'Failed to delete job';
      notifyListeners();
    }
  }

  Future<int> deleteJobs(List<String> jobIds) async {
    if (_client == null) return 0;
    int deleted = 0;
    for (final jobId in jobIds) {
      try {
        await _client!.deleteJob(jobId);
        _jobs = _jobs.where((j) => j.jobId != jobId).toList();
        deleted++;
      } on GrpcError {
        // continue deleting remaining jobs
      }
    }
    if (deleted < jobIds.length) {
      _error =
          'Failed to delete ${jobIds.length - deleted} of ${jobIds.length} jobs';
    }
    notifyListeners();
    return deleted;
  }

  // --- Transcript access ---

  String getFullTranscript() {
    final sorted = [..._segments]..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((s) => s.text).join(' ');
  }

  String getTranscriptForItem(int index) {
    if (index < 0 || index >= _batchQueue.length) return '';
    final sorted = [..._batchQueue[index].segments]
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((s) => s.text).join(' ');
  }

  Future<pb.GetTranscriptResponse?> fetchFullTranscript(String jobId) async {
    if (_client == null) return null;
    try {
      return await _client!.getTranscript(jobId);
    } on GrpcError catch (e) {
      _error = e.message ?? 'Failed to fetch transcript';
      notifyListeners();
      return null;
    }
  }

  // --- Load saved job ---

  Future<bool> loadSavedJob(String jobId) async {
    if (_client == null) return false;

    final response = await fetchFullTranscript(jobId);
    if (response == null || response.segments.isEmpty) return false;

    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isTranscribing = false;
    _error = null;
    _progress = 1.0;
    _currentBatchIndex = 0;

    _activeJobId = jobId;
    _activeJobStatus = JobStatus.COMPLETED;
    _segments = response.segments.toList();

    final audioPath = response.audioPath.isNotEmpty
        ? response.audioPath
        : 'unknown';
    _selectedFilePaths = [audioPath];

    _batchQueue = [
      BatchItem(
        filePath: audioPath,
        jobId: jobId,
        status: BatchItemStatus.completed,
        segments: _segments,
        progress: 1.0,
      ),
    ];

    notifyListeners();
    return true;
  }

  // --- Reset ---

  void reset() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _activeJobId = null;
    _activeJobStatus = JobStatus.JOB_STATUS_UNSPECIFIED;
    _segments = [];
    _progress = 0.0;
    _isTranscribing = false;
    _error = null;
    _selectedFilePaths = [];
    _batchQueue = [];
    _currentBatchIndex = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }
}
