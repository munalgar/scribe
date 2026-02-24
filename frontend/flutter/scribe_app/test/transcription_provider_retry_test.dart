import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;

import '../lib/models/batch_item.dart';
import '../lib/proto/scribe.pb.dart' as pb;
import '../lib/providers/transcription_provider.dart';
import '../lib/services/grpc_client.dart';

class _FakeClientCall<R> extends ClientCall<dynamic, R> {
  _FakeClientCall(this._response)
    : super(
        ClientMethod<dynamic, R>(
          '/scribe.Scribe/StreamTranscription',
          (_) => const <int>[],
          (_) => throw UnimplementedError(),
        ),
        const Stream<dynamic>.empty(),
        CallOptions(),
      );

  final Stream<R> _response;

  @override
  Stream<R> get response => _response;

  @override
  Future<Map<String, String>> get headers async => <String, String>{};

  @override
  Future<Map<String, String>> get trailers async => <String, String>{};

  @override
  Future<void> cancel() async {}
}

class _RetryTestClient extends ScribeGrpcClient {
  _RetryTestClient({required this.failFirstAttemptForFiles});

  final Set<String> failFirstAttemptForFiles;
  final Map<String, int> _attemptByFile = <String, int>{};
  int _jobCounter = 0;

  int attemptsForFile(String fileName) => _attemptByFile[fileName] ?? 0;

  String _canonicalFileName(String filePath) {
    final name = p.basename(filePath);
    final split = name.indexOf('_');
    if (split <= 0) return name;
    final prefix = name.substring(0, split);
    final isTimestamp = int.tryParse(prefix) != null;
    return isTimestamp ? name.substring(split + 1) : name;
  }

  @override
  Future<pb.StartTranscriptionResponse> startTranscription({
    required String filePath,
    String model = 'base',
    bool enableGpu = true,
    String? language,
    String? translateToLanguage,
  }) async {
    final canonical = _canonicalFileName(filePath);
    final nextAttempt = (_attemptByFile[canonical] ?? 0) + 1;
    _attemptByFile[canonical] = nextAttempt;

    if (failFirstAttemptForFiles.contains(canonical) && nextAttempt == 1) {
      throw GrpcError.internal('Simulated start failure');
    }

    final response = pb.StartTranscriptionResponse();
    response.jobId = 'job-${_jobCounter++}';
    response.status = pb.JobStatus.QUEUED;
    return response;
  }

  @override
  ResponseStream<pb.TranscriptionEvent> streamTranscription(String jobId) {
    final event = pb.TranscriptionEvent()
      ..jobId = jobId
      ..status = pb.JobStatus.COMPLETED
      ..progress = 1.0;
    return ResponseStream<pb.TranscriptionEvent>(
      _FakeClientCall<pb.TranscriptionEvent>(
        Stream<pb.TranscriptionEvent>.value(event),
      ),
    );
  }

  @override
  Future<pb.ListJobsResponse> listJobs() async => pb.ListJobsResponse();
}

Future<void> _drainAsyncQueue() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<String> _createTempAudioFile(String name) async {
  final path = '${Directory.systemTemp.path}/$name';
  final file = File(path);
  await file.writeAsBytes(<int>[0, 1, 2, 3], flush: true);
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return '/tmp';
          }
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('retries failed solo transcription job', () async {
    const soloName = 'solo-failure.wav';
    final soloPath = await _createTempAudioFile('solo-failure.wav');
    final client = _RetryTestClient(
      failFirstAttemptForFiles: <String>{soloName},
    );
    final provider = TranscriptionProvider();
    provider.updateClient(client);
    provider.selectFile(soloPath);

    await provider.startBatchTranscription();
    await _drainAsyncQueue();

    expect(provider.batchQueue, hasLength(1));
    expect(provider.batchQueue.first.status, BatchItemStatus.failed);
    expect(provider.activeJobStatus, pb.JobStatus.FAILED);
    expect(provider.isTranscribing, isFalse);

    await provider.retryBatchItem(0);
    await _drainAsyncQueue();

    expect(client.attemptsForFile(soloName), 2);
    expect(provider.batchQueue.first.status, BatchItemStatus.completed);
    expect(provider.activeJobStatus, pb.JobStatus.COMPLETED);
    expect(provider.isTranscribing, isFalse);

    await File(soloPath).delete();
  });

  test('retries failed item in batch transcription queue', () async {
    const failedName = 'batch-failure.wav';
    const successName = 'batch-success.wav';
    final failedPath = await _createTempAudioFile('batch-failure.wav');
    final successPath = await _createTempAudioFile('batch-success.wav');

    final client = _RetryTestClient(
      failFirstAttemptForFiles: <String>{failedName},
    );
    final provider = TranscriptionProvider();
    provider.updateClient(client);
    provider.selectFiles(<String>[failedPath, successPath]);

    await provider.startBatchTranscription();
    await _drainAsyncQueue();

    expect(provider.batchQueue, hasLength(2));
    expect(provider.batchQueue[0].status, BatchItemStatus.failed);
    expect(provider.batchQueue[1].status, BatchItemStatus.completed);
    expect(provider.isTranscribing, isFalse);

    await provider.retryBatchItem(0);
    await _drainAsyncQueue();

    expect(client.attemptsForFile(failedName), 2);
    expect(client.attemptsForFile(successName), 1);
    expect(provider.batchQueue[0].status, BatchItemStatus.completed);
    expect(provider.batchQueue[1].status, BatchItemStatus.completed);
    expect(provider.isTranscribing, isFalse);

    await File(failedPath).delete();
    await File(successPath).delete();
  });
}
