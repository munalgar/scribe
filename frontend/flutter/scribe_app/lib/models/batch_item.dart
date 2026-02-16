import 'package:path/path.dart' as p;
import '../proto/scribe.pb.dart' as pb;

enum BatchItemStatus {
  pending,
  running,
  completed,
  failed,
  canceled,
}

class BatchItem {
  final String filePath;
  String? jobId;
  BatchItemStatus status;
  List<pb.Segment> segments;
  double progress;
  String? error;

  BatchItem({
    required this.filePath,
    this.jobId,
    this.status = BatchItemStatus.pending,
    List<pb.Segment>? segments,
    this.progress = 0.0,
    this.error,
  }) : segments = segments ?? [];

  String get fileName => p.basename(filePath);

  bool get isTerminal =>
      status == BatchItemStatus.completed ||
      status == BatchItemStatus.failed ||
      status == BatchItemStatus.canceled;
}
