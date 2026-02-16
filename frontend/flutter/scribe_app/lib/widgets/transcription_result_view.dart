import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../models/batch_item.dart';
import '../providers/transcription_provider.dart';
import '../proto/scribe.pbgrpc.dart';
import '../services/export_formatters.dart';
import '../services/export_service.dart';
import 'batch_queue_panel.dart';
import 'status_badge.dart';

/// The active transcription view showing progress, segments, and controls.
class TranscriptionResultView extends StatelessWidget {
  final ScrollController scrollController;
  final int viewingBatchIndex;
  final ValueChanged<int> onViewingIndexChanged;
  final bool isConnected;

  const TranscriptionResultView({
    super.key,
    required this.scrollController,
    required this.viewingBatchIndex,
    required this.onViewingIndexChanged,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final theme = Theme.of(context);

    final isDone = provider.isBatchMode
        ? provider.isBatchComplete
        : (provider.activeJobStatus == JobStatus.COMPLETED ||
            provider.activeJobStatus == JobStatus.FAILED ||
            provider.activeJobStatus == JobStatus.CANCELED);

    // Determine which segments to display
    final List<BatchItem> queue = provider.batchQueue;
    final viewIndex =
        viewingBatchIndex.clamp(0, queue.isEmpty ? 0 : queue.length - 1);
    final viewingItem = queue.isNotEmpty ? queue[viewIndex] : null;
    final displaySegments = viewingItem?.segments ?? provider.segments;
    final selectedPath = provider.selectedFilePath;
    final displayFileName = viewingItem?.fileName ??
        (selectedPath != null ? p.basename(selectedPath) : 'Audio file');

    return Column(
      children: [
        // Top bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.audio_file_rounded,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          displayFileName,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(status: provider.activeJobStatus),
              if (provider.isBatchMode) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'File ${provider.completedBatchFiles + (provider.isTranscribing ? 1 : 0)} of ${provider.totalBatchFiles}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              if (isDone) ...[
                if (displaySegments.isNotEmpty) ...[
                  PopupMenuButton<ExportFormat>(
                    icon: Icon(Icons.download_rounded,
                        color: theme.colorScheme.onSurfaceVariant),
                    tooltip: 'Export transcript',
                    onSelected: (format) =>
                        _exportTranscript(context, format, provider, viewingItem),
                    itemBuilder: (context) => ExportFormat.values
                        .map((f) => PopupMenuItem(
                              value: f,
                              child: Text('${f.label} (.${f.extension})'),
                            ))
                        .toList(),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded,
                        color: theme.colorScheme.onSurfaceVariant),
                    tooltip: 'Copy transcript',
                    onPressed: () {
                      final text = viewingItem != null
                          ? provider.getTranscriptForItem(viewIndex)
                          : provider.getFullTranscript();
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Transcript copied')),
                      );
                    },
                  ),
                ],
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => provider.reset(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                ),
              ],
              if (provider.isTranscribing)
                OutlinedButton.icon(
                  onPressed: () => provider.cancelTranscription(),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(provider.isBatchMode ? 'Cancel All' : 'Cancel'),
                ),
            ],
          ),
        ),

        // Per-file progress bar (only while transcribing)
        if (!isDone && provider.isTranscribing)
          Column(
            children: [
              LinearProgressIndicator(
                value: provider.progress > 0 ? provider.progress : null,
                minHeight: 3,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${(provider.progress * 100).toInt()}%',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),

        // Batch queue panel
        if (provider.isBatchMode)
          BatchQueuePanel(
            viewingBatchIndex: viewingBatchIndex,
            onViewingIndexChanged: onViewingIndexChanged,
          ),

        // Error
        if (provider.error != null &&
            provider.activeJobStatus == JobStatus.FAILED)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: theme.colorScheme.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(provider.error!)),
                ],
              ),
            ),
          ),

        // Segments
        Expanded(
          child: displaySegments.isEmpty
              ? Center(
                  child: provider.isTranscribing &&
                          viewingItem?.status == BatchItemStatus.running
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Processing audio...',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'No segments',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
                      itemCount: displaySegments.length,
                      itemBuilder: (context, index) {
                        final seg = displaySegments[index];
                        return Padding(
                          key: ValueKey(seg.index),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 90,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '${_formatTime(seg.start)} - ${_formatTime(seg.end)}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  seg.text,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _exportTranscript(BuildContext context, ExportFormat format,
      TranscriptionProvider provider, BatchItem? viewingItem) async {
    final segments = viewingItem?.segments ?? provider.segments;
    if (segments.isEmpty) return;

    final exportPath = provider.selectedFilePath;
    final audioName = viewingItem?.fileName ??
        (exportPath != null ? p.basename(exportPath) : 'transcript');
    final baseName = audioName.contains('.')
        ? audioName.substring(0, audioName.lastIndexOf('.'))
        : audioName;
    final defaultFileName = '$baseName.${format.extension}';

    final content = ExportFormatters.format(
      format,
      segments,
      jobId: viewingItem?.jobId ?? provider.activeJobId,
    );

    final savedPath = await ExportService.saveToFile(
      content: content,
      defaultFileName: defaultFileName,
      extension: format.extension,
    );

    if (savedPath != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to $savedPath')),
      );
    }
  }

  String _formatTime(double seconds) {
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).toInt();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
