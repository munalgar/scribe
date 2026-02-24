import 'package:grpc/grpc.dart';
import '../proto/scribe.pbgrpc.dart';
import '../proto/scribe.pb.dart' as pb;

class ScribeGrpcClient {
  ClientChannel? _channel;
  ScribeClient? _stub;

  /// Whether a channel has been created. Does not guarantee the backend is reachable.
  bool get hasChannel => _channel != null;

  static const _defaultTimeout = Duration(seconds: 10);
  static const _downloadTimeout = Duration(minutes: 60);

  CallOptions get _defaultOptions => CallOptions(timeout: _defaultTimeout);

  CallOptions get _downloadOptions => CallOptions(timeout: _downloadTimeout);

  Future<void> connect({String host = '127.0.0.1', int port = 50051}) async {
    await disconnect();
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        keepAlive: ClientKeepAliveOptions(
          pingInterval: Duration(seconds: 30),
          timeout: Duration(seconds: 10),
          permitWithoutCalls: true,
        ),
      ),
    );
    _stub = ScribeClient(_channel!);
  }

  Future<void> disconnect() async {
    await _channel?.shutdown();
    _channel = null;
    _stub = null;
  }

  ScribeClient get stub {
    if (_stub == null) throw StateError('Not connected');
    return _stub!;
  }

  Future<pb.HealthCheckResponse> healthCheck() =>
      stub.healthCheck(pb.HealthCheckRequest(), options: _defaultOptions);

  Future<pb.StartTranscriptionResponse> startTranscription({
    required String filePath,
    String model = 'base',
    bool enableGpu = true,
    String? language,
    String? translateToLanguage,
  }) {
    final request = pb.StartTranscriptionRequest()
      ..audio = (pb.AudioSource()..filePath = filePath)
      ..options = (pb.TranscriptionOptions()
        ..model = model
        ..enableGpu = enableGpu);
    if (language != null && language.isNotEmpty) {
      request.options.language = language;
    }
    if (translateToLanguage != null && translateToLanguage.isNotEmpty) {
      request.options.translateToLanguage = translateToLanguage;
      // Keep the legacy flag set for older backends and native Whisper EN translation.
      request.options.translateToEnglish = translateToLanguage == 'en';
    }
    return stub.startTranscription(request, options: _defaultOptions);
  }

  ResponseStream<pb.TranscriptionEvent> streamTranscription(String jobId) =>
      stub.streamTranscription(pb.StreamTranscriptionRequest()..jobId = jobId);

  Future<pb.GetJobResponse> getJob(String jobId) =>
      stub.getJob(pb.GetJobRequest()..jobId = jobId, options: _defaultOptions);

  Future<pb.ListJobsResponse> listJobs() =>
      stub.listJobs(pb.ListJobsRequest(), options: _defaultOptions);

  Future<pb.CancelJobResponse> cancelJob(String jobId) => stub.cancelJob(
    pb.CancelJobRequest()..jobId = jobId,
    options: _defaultOptions,
  );

  Future<pb.DeleteJobResponse> deleteJob(String jobId) => stub.deleteJob(
    pb.DeleteJobRequest()..jobId = jobId,
    options: _defaultOptions,
  );

  Future<pb.GetTranscriptResponse> getTranscript(String jobId) =>
      stub.getTranscript(
        pb.GetTranscriptRequest()..jobId = jobId,
        options: _defaultOptions,
      );

  Future<pb.SaveTranscriptEditsResponse> saveTranscriptEdits(
    String jobId,
    List<pb.SegmentEdit> edits,
  ) => stub.saveTranscriptEdits(
    pb.SaveTranscriptEditsRequest()
      ..jobId = jobId
      ..edits.addAll(edits),
    options: _defaultOptions,
  );

  Future<pb.TranslateTranscriptResponse> translateTranscript({
    required String jobId,
    required String targetLanguage,
    Map<int, String> sourceEdits = const {},
    List<int> segmentIndices = const [],
  }) {
    final request = pb.TranslateTranscriptRequest()
      ..jobId = jobId
      ..targetLanguage = targetLanguage;
    if (sourceEdits.isNotEmpty) {
      request.sourceEdits.addAll(
        sourceEdits.entries.map(
          (entry) =>
              pb.SegmentEdit(segmentIndex: entry.key, editedText: entry.value),
        ),
      );
    }
    if (segmentIndices.isNotEmpty) {
      request.segmentIndices.addAll(segmentIndices);
    }
    return stub.translateTranscript(request, options: _defaultOptions);
  }

  Future<pb.GetSettingsResponse> getSettings() =>
      stub.getSettings(pb.GetSettingsRequest(), options: _defaultOptions);

  Future<pb.UpdateSettingsResponse> updateSettings(pb.Settings settings) =>
      stub.updateSettings(
        pb.UpdateSettingsRequest()..settings = settings,
        options: _defaultOptions,
      );

  Future<pb.ListModelsResponse> listModels() =>
      stub.listModels(pb.ListModelsRequest(), options: _defaultOptions);

  ResponseStream<pb.DownloadModelProgress> downloadModel(String name) =>
      stub.downloadModel(
        pb.DownloadModelRequest()..name = name,
        options: _downloadOptions,
      );

  Future<pb.CancelDownloadResponse> cancelDownload(String name) =>
      stub.cancelDownload(
        pb.CancelDownloadRequest()..name = name,
        options: _defaultOptions,
      );

  Future<pb.DeleteModelResponse> deleteModel(String name) => stub.deleteModel(
    pb.DeleteModelRequest()..name = name,
    options: _defaultOptions,
  );
}
