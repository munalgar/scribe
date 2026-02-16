import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import '../proto/scribe.pb.dart' as pb;
import '../services/grpc_client.dart';

class SettingsProvider extends ChangeNotifier {
  ScribeGrpcClient? _client;

  pb.Settings? _settings;
  List<pb.ModelInfo> _models = [];
  String? _settingsError;
  String? _modelsError;

  // Download progress state
  String? _downloadingModel;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  DateTime? _downloadStartTime;
  StreamSubscription? _downloadSubscription;

  pb.Settings? get settings => _settings;
  List<pb.ModelInfo> get models => _models;
  String? get downloadingModel => _downloadingModel;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get settingsError => _settingsError;
  String? get modelsError => _modelsError;
  String? get error => _settingsError ?? _modelsError;

  double get downloadProgress =>
      _totalBytes > 0 ? _downloadedBytes / _totalBytes : 0.0;

  /// Estimated seconds remaining, or null if not enough data.
  int? get downloadEtaSeconds {
    if (_downloadStartTime == null || _downloadedBytes <= 0 || _totalBytes <= 0) {
      return null;
    }
    final elapsed = DateTime.now().difference(_downloadStartTime!).inMilliseconds;
    if (elapsed < 500) return null; // need at least 0.5s of data
    final bytesPerMs = _downloadedBytes / elapsed;
    final remaining = _totalBytes - _downloadedBytes;
    return (remaining / bytesPerMs / 1000).ceil();
  }

  void updateClient(ScribeGrpcClient? client) {
    _client = client;
  }

  Future<void> loadSettings() async {
    if (_client == null) return;
    try {
      final response = await _client!.getSettings();
      _settings = response.settings;
      _settingsError = null;
      notifyListeners();
    } on GrpcError catch (e) {
      _settingsError = e.message ?? 'Failed to load settings';
      notifyListeners();
    }
  }

  Future<void> updateSettings({
    String? computeType,
  }) async {
    if (_client == null) return;
    try {
      final s = pb.Settings();
      if (computeType != null) s.computeType = computeType;
      if (_settings?.modelsDir.isNotEmpty == true) {
        s.modelsDir = _settings!.modelsDir;
      }
      final response = await _client!.updateSettings(s);
      _settings = response.settings;
      _settingsError = null;
      notifyListeners();
    } on GrpcError catch (e) {
      _settingsError = e.message ?? 'Failed to save settings';
      notifyListeners();
    }
  }

  Future<void> loadModels() async {
    if (_client == null) return;
    try {
      final response = await _client!.listModels();
      _models = response.models.toList();
      _modelsError = null;
      notifyListeners();
    } on GrpcError catch (e) {
      _modelsError = e.message ?? 'Failed to load models';
      notifyListeners();
    }
  }

  Future<void> downloadModel(String name) async {
    if (_client == null) return;
    _downloadingModel = name;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _downloadStartTime = null;
    _modelsError = null;
    notifyListeners();

    try {
      final stream = _client!.downloadModel(name);
      final completer = Completer<void>();

      _downloadSubscription = stream.listen(
        (progress) {
          if (progress.status == pb.DownloadStatus.DOWNLOAD_STARTING) {
            _downloadStartTime = DateTime.now();
            _totalBytes = progress.totalBytes.toInt();
            notifyListeners();
          } else if (progress.status == pb.DownloadStatus.DOWNLOAD_DOWNLOADING) {
            _downloadedBytes = progress.downloadedBytes.toInt();
            _totalBytes = progress.totalBytes.toInt();
            _downloadStartTime ??= DateTime.now();
            notifyListeners();
          } else if (progress.status == pb.DownloadStatus.DOWNLOAD_COMPLETE) {
            _downloadingModel = null;
            _downloadedBytes = 0;
            _totalBytes = 0;
            _downloadStartTime = null;
            loadModels();
          } else if (progress.status == pb.DownloadStatus.DOWNLOAD_FAILED) {
            _downloadingModel = null;
            _modelsError = progress.error.isNotEmpty
                ? progress.error
                : 'Download failed';
            notifyListeners();
          } else if (progress.status == pb.DownloadStatus.DOWNLOAD_CANCELED) {
            _downloadingModel = null;
            _downloadedBytes = 0;
            _totalBytes = 0;
            _downloadStartTime = null;
            notifyListeners();
          }
        },
        onError: (error) {
          _downloadingModel = null;
          _modelsError = error is GrpcError
              ? (error.message ?? 'Download failed')
              : error.toString();
          notifyListeners();
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          _downloadSubscription = null;
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future;
    } on GrpcError catch (e) {
      _downloadingModel = null;
      _modelsError = e.message ?? 'Failed to download model';
      notifyListeners();
    }
  }

  Future<void> cancelDownload() async {
    if (_client == null || _downloadingModel == null) return;
    try {
      await _client!.cancelDownload(_downloadingModel!);
    } on GrpcError catch (_) {
      // Best-effort cancel
    }
  }

  Future<void> deleteModel(String name) async {
    if (_client == null) return;
    try {
      await _client!.deleteModel(name);
      await loadModels();
    } on GrpcError catch (e) {
      _modelsError = e.message ?? 'Failed to delete model';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }
}
