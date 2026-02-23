import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'export_formatters.dart';

class ExportService {
  static Future<String?> saveToFile({
    required String content,
    required String defaultFileName,
    required String extension,
  }) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Transcript',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: [extension],
    );

    if (result == null) return null;

    final file = File(result);
    await file.writeAsString(content);
    return result;
  }

  /// Exports the transcript in multiple formats to a user-chosen directory.
  /// Returns the directory path on success, or null if cancelled.
  static Future<String?> saveMultipleFormats({
    required String baseName,
    required List<ExportFormat> formats,
    required String Function(ExportFormat fmt) contentBuilder,
  }) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose export folder',
    );

    if (dir == null) return null;

    for (final fmt in formats) {
      final filePath = p.join(dir, '$baseName.${fmt.extension}');
      final file = File(filePath);
      await file.writeAsString(contentBuilder(fmt));
    }

    return dir;
  }
}
