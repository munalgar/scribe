import 'dart:io';

import 'package:file_picker/file_picker.dart';

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
}
