import 'dart:convert';

import 'package:path/path.dart' as p;

import '../proto/scribe.pb.dart' as pb;

enum ExportFormat {
  txt('Text', 'txt'),
  srt('SubRip Subtitle', 'srt'),
  vtt('WebVTT Subtitle', 'vtt'),
  json('JSON', 'json'),
  csv('CSV', 'csv');

  const ExportFormat(this.label, this.extension);
  final String label;
  final String extension;
}

class ExportFormatters {
  static List<pb.Segment> _sorted(List<pb.Segment> segments) =>
      [...segments]..sort((a, b) => a.index.compareTo(b.index));

  static String format(
    ExportFormat fmt,
    List<pb.Segment> segments, {
    String? jobId,
    String? audioPath,
    String? model,
    String? language,
    String? createdAt,
  }) {
    switch (fmt) {
      case ExportFormat.txt:
        return toTxt(segments);
      case ExportFormat.srt:
        return toSrt(segments);
      case ExportFormat.vtt:
        return toVtt(segments);
      case ExportFormat.json:
        return toJson(
          segments,
          jobId: jobId,
          audioPath: audioPath,
          model: model,
          language: language,
          createdAt: createdAt,
        );
      case ExportFormat.csv:
        return toCsv(segments);
    }
  }

  static String toTxt(List<pb.Segment> segments) {
    return _sorted(segments).map((s) => s.text.trim()).join('\n');
  }

  static String toSrt(List<pb.Segment> segments) {
    final sorted = _sorted(segments);
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      buf.writeln('${i + 1}');
      buf.writeln(
        '${_formatTime(s.start, ',')} --> ${_formatTime(s.end, ',')}',
      );
      buf.writeln(s.text.trim());
      if (i < sorted.length - 1) buf.writeln();
    }
    return buf.toString();
  }

  static String toVtt(List<pb.Segment> segments) {
    final sorted = _sorted(segments);
    final buf = StringBuffer();
    buf.writeln('WEBVTT');
    buf.writeln();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      buf.writeln(
        '${_formatTime(s.start, '.')} --> ${_formatTime(s.end, '.')}',
      );
      buf.writeln(s.text.trim());
      if (i < sorted.length - 1) buf.writeln();
    }
    return buf.toString();
  }

  static String toJson(
    List<pb.Segment> segments, {
    String? jobId,
    String? audioPath,
    String? model,
    String? language,
    String? createdAt,
  }) {
    final sorted = _sorted(segments);
    final filename = (audioPath?.isNotEmpty ?? false)
        ? p.basename(audioPath!)
        : null;
    final data = <String, dynamic>{
      if (jobId?.isNotEmpty ?? false) 'job_id': jobId,
      if (filename != null) 'filename': filename,
      if (audioPath?.isNotEmpty ?? false) 'audio_path': audioPath,
      if (model?.isNotEmpty ?? false) 'model': model,
      if (language?.isNotEmpty ?? false) 'language': language,
      if (createdAt?.isNotEmpty ?? false) 'created_at': createdAt,
      'segments': sorted
          .map(
            (s) => {
              'index': s.index,
              'start': s.start,
              'end': s.end,
              'text': s.text.trim(),
            },
          )
          .toList(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  static String toCsv(List<pb.Segment> segments) {
    final sorted = _sorted(segments);
    final buf = StringBuffer();
    buf.writeln('index,start,end,text');
    for (final s in sorted) {
      final escapedText = s.text.trim().replaceAll('"', '""');
      buf.writeln('${s.index},${s.start},${s.end},"$escapedText"');
    }
    return buf.toString();
  }

  static String _formatTime(double seconds, String msSeparator) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = ((seconds % 60).truncate()).toString().padLeft(2, '0');
    final ms = ((seconds * 1000).truncate() % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s$msSeparator$ms';
  }
}
