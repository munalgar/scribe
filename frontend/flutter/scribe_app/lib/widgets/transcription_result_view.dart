import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../models/batch_item.dart';
import '../providers/transcription_provider.dart';
import '../proto/scribe.pbgrpc.dart';
import '../services/export_formatters.dart';
import '../services/export_service.dart';
import '../theme.dart';
import 'export_format_dialog.dart';
import 'audio_player_bar.dart';
import 'batch_queue_panel.dart';
import 'status_badge.dart';
import 'transcript_panel.dart';

class TranscriptionResultView extends StatefulWidget {
  final ScrollController scrollController;
  final int viewingBatchIndex;
  final ValueChanged<int> onViewingIndexChanged;
  final bool isConnected;
  final Player audioPlayer;

  const TranscriptionResultView({
    super.key,
    required this.scrollController,
    required this.viewingBatchIndex,
    required this.onViewingIndexChanged,
    required this.isConnected,
    required this.audioPlayer,
  });

  @override
  State<TranscriptionResultView> createState() =>
      _TranscriptionResultViewState();
}

class _TranscriptionResultViewState extends State<TranscriptionResultView> {
  final GlobalKey<AudioPlayerBarState> _playerBarKey = GlobalKey();
  final GlobalKey<TranscriptPanelState> _transcriptKey = GlobalKey();

  Duration _playbackPosition = Duration.zero;
  bool _isPlaying = false;
  bool _isUtilitySidebarCollapsed = false;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(
      widget.audioPlayer.stream.position.listen((p) {
        if (mounted) setState(() => _playbackPosition = p);
      }),
    );
    _subs.add(
      widget.audioPlayer.stream.playing.listen((p) {
        if (mounted) setState(() => _isPlaying = p);
      }),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _handleSeek(Duration position) {
    _playerBarKey.currentState?.seekTo(position);
  }

  void _handleSpaceKey() {
    _playerBarKey.currentState?.togglePlayPause();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final theme = Theme.of(context);

    final isDone = provider.isBatchMode
        ? provider.isBatchComplete
        : (provider.activeJobStatus == JobStatus.COMPLETED ||
              provider.activeJobStatus == JobStatus.FAILED ||
              provider.activeJobStatus == JobStatus.CANCELED);

    final List<BatchItem> queue = provider.batchQueue;
    final viewIndex = widget.viewingBatchIndex.clamp(
      0,
      queue.isEmpty ? 0 : queue.length - 1,
    );
    final viewingItem = queue.isNotEmpty ? queue[viewIndex] : null;
    final displaySegments = viewingItem?.segments ?? provider.segments;
    final selectedPath = provider.selectedFilePath;
    final displayFileName =
        viewingItem?.fileName ??
        (selectedPath != null ? p.basename(selectedPath) : 'Audio file');

    final audioPath = viewingItem?.filePath ?? provider.selectedFilePath;
    final audioDurationHint = _durationHintFromSegments(displaySegments);
    final hasAudio = audioPath != null && isDone;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _handleSpaceKey,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _playerBarKey.currentState?.seekBackwardByStep(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _playerBarKey.currentState?.seekForwardByStep(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _buildTopBar(
              context,
              theme,
              provider,
              isDone,
              displayFileName,
              displaySegments,
              viewingItem,
            ),

            if (!isDone && provider.isTranscribing)
              _buildProgressBar(theme, provider),

            if (provider.isBatchMode)
              BatchQueuePanel(
                viewingBatchIndex: widget.viewingBatchIndex,
                onViewingIndexChanged: widget.onViewingIndexChanged,
              ),

            if (provider.error != null &&
                provider.activeJobStatus == JobStatus.FAILED)
              _buildErrorBanner(theme, provider),

            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: TranscriptPanel(
                            key: _transcriptKey,
                            segments: displaySegments,
                            playbackPosition: _playbackPosition,
                            isPlaying: _isPlaying,
                            onSeek: _handleSeek,
                            isTranscribing:
                                provider.isTranscribing &&
                                viewingItem?.status == BatchItemStatus.running,
                            scrollController: widget.scrollController,
                            initialEdits: provider.savedEdits,
                          ),
                        ),
                        AudioPlayerBar(
                          key: _playerBarKey,
                          player: widget.audioPlayer,
                          filePath: audioPath,
                          durationHint: audioDurationHint,
                          enabled: hasAudio,
                        ),
                      ],
                    ),
                  ),
                  _buildSidebar(
                    context,
                    theme,
                    provider,
                    isDone,
                    displaySegments,
                    viewingItem,
                    viewIndex,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    ThemeData theme,
    TranscriptionProvider provider,
    bool isDone,
    String displayFileName,
    List<dynamic> displaySegments,
    BatchItem? viewingItem,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.audio_file_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
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
          const SizedBox(width: 10),
          StatusBadge(status: provider.activeJobStatus),
          if (provider.isBatchMode) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${provider.completedBatchFiles + (provider.isTranscribing ? 1 : 0)} / ${provider.totalBatchFiles}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (isDone)
            FilledButton.icon(
              onPressed: () => provider.reset(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          if (provider.isTranscribing)
            OutlinedButton.icon(
              onPressed: () => provider.cancelTranscription(),
              icon: const Icon(Icons.stop_rounded, size: 16),
              label: Text(provider.isBatchMode ? 'Cancel All' : 'Cancel'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ThemeData theme, TranscriptionProvider provider) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: provider.progress > 0 ? provider.progress : null,
          minHeight: 3,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
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
    );
  }

  Widget _buildErrorBanner(ThemeData theme, TranscriptionProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                provider.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    ThemeData theme,
    TranscriptionProvider provider,
    bool isDone,
    List<dynamic> displaySegments,
    BatchItem? viewingItem,
    int viewIndex,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: _isUtilitySidebarCollapsed ? 58 : 260,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isUtilitySidebarCollapsed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Utilities',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Collapse utility sidebar',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _isUtilitySidebarCollapsed = true;
                      });
                    },
                    icon: const Icon(Icons.tune_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Divider(color: theme.colorScheme.outlineVariant, height: 1),
          ],
          if (_isUtilitySidebarCollapsed)
            Expanded(
              child: Center(
                child: IconButton(
                  tooltip: 'Expand utility sidebar',
                  onPressed: () {
                    setState(() {
                      _isUtilitySidebarCollapsed = false;
                    });
                  },
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text(
                      'Export',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: ExportFormat.values.map((format) {
                        return _SidebarExportTile(
                          format: format,
                          enabled: isDone && displaySegments.isNotEmpty,
                          onTap: () => _exportTranscript(
                            context,
                            format,
                            provider,
                            viewingItem,
                          ),
                          theme: theme,
                        );
                      }).toList(),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _SidebarActionButton(
                      icon: Icons.folder_zip_outlined,
                      label: 'Export multiple formats',
                      enabled: isDone && displaySegments.isNotEmpty,
                      theme: theme,
                      onTap: () =>
                          _exportMultiFormat(context, provider, viewingItem),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _SidebarActionButton(
                      icon: Icons.copy_rounded,
                      label: 'Copy to clipboard',
                      enabled: isDone && displaySegments.isNotEmpty,
                      theme: theme,
                      onTap: () {
                        final text = _transcriptKey.currentState != null
                            ? _transcriptKey.currentState!
                                  .getFullEditedTranscript()
                            : (viewingItem != null
                                  ? provider.getTranscriptForItem(viewIndex)
                                  : provider.getFullTranscript());
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _SidebarActionButton(
                      icon: Icons.save_rounded,
                      label: 'Save edits',
                      enabled:
                          isDone &&
                          displaySegments.isNotEmpty &&
                          (viewingItem?.jobId ?? provider.activeJobId) != null,
                      theme: theme,
                      onTap: () => _saveEdits(context, provider, viewingItem),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    color: theme.colorScheme.outlineVariant,
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      'Info',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _buildInfoRow(
                    'Segments',
                    '${displaySegments.length}',
                    theme,
                    wrap: true,
                  ),
                  if (displaySegments.isNotEmpty) ...[
                    _buildInfoRow(
                      'Duration',
                      _formatDurationFromSegments(displaySegments),
                      theme,
                      wrap: true,
                    ),
                  ],
                  if (provider.activeJobId != null)
                    _buildInfoRow(
                      'Job',
                      provider.activeJobId!,
                      theme,
                      wrap: true,
                    ),

                  const SizedBox(height: 24),
                  Divider(
                    color: theme.colorScheme.outlineVariant,
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.keyboard_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Shortcuts',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildShortcutHint('Space', 'Play / Pause', theme),
                        _buildShortcutHint(
                          'Alt + ← →',
                          'Skip by selected step',
                          theme,
                        ),
                        _buildShortcutHint('Ctrl + F', 'Search', theme),
                        _buildShortcutHint('Double-click', 'Edit text', theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    ThemeData theme, {
    bool wrap = false,
  }) {
    final valueStyle = ScribeTheme.monoStyle(
      context,
      fontSize: 11,
      color: theme.colorScheme.onSurface,
    );

    if (wrap) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            SelectableText(value, style: valueStyle),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(String keys, String action, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              keys,
              style: ScribeTheme.monoStyle(context, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            action,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Duration? _durationHintFromSegments(List<dynamic> segments) {
    if (segments.isEmpty) return null;
    double maxEnd = 0;
    for (final seg in segments) {
      final end = seg.end;
      if (end is num && end > maxEnd) {
        maxEnd = end.toDouble();
      }
    }
    if (maxEnd <= 0) return null;
    return Duration(milliseconds: (maxEnd * 1000).round());
  }

  String _formatDurationFromSegments(List<dynamic> segments) {
    final duration = _durationHintFromSegments(segments);
    if (duration == null) return '--:--';
    final totalSeconds = duration.inMilliseconds / 1000;
    final h = (totalSeconds ~/ 3600);
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = ((totalSeconds % 60).truncate()).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  Future<void> _saveEdits(
    BuildContext context,
    TranscriptionProvider provider,
    BatchItem? viewingItem,
  ) async {
    final panelState = _transcriptKey.currentState;
    if (panelState == null || !panelState.hasEdits) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No edits to save')));
      }
      return;
    }

    final jobId = viewingItem?.jobId ?? provider.activeJobId;
    if (jobId == null) return;

    final saved = await provider.saveTranscriptEdits(
      jobId,
      panelState.editedTexts,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? 'Edits saved' : 'Failed to save edits')),
      );
    }
  }

  Future<void> _exportTranscript(
    BuildContext context,
    ExportFormat format,
    TranscriptionProvider provider,
    BatchItem? viewingItem,
  ) async {
    final panelState = _transcriptKey.currentState;
    final segments = panelState != null
        ? panelState.getSegmentsWithEdits()
        : (viewingItem?.segments ?? provider.segments);
    if (segments.isEmpty) return;

    final exportPath = provider.selectedFilePath;
    final audioName =
        viewingItem?.fileName ??
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported to $savedPath')));
    }
  }

  Future<void> _exportMultiFormat(
    BuildContext context,
    TranscriptionProvider provider,
    BatchItem? viewingItem,
  ) async {
    final formats = await ExportFormatDialog.show(
      context,
      title: 'Export Transcript',
    );
    if (formats == null || formats.isEmpty || !context.mounted) return;

    // If only one format chosen, delegate to the single-file export.
    if (formats.length == 1) {
      await _exportTranscript(context, formats.first, provider, viewingItem);
      return;
    }

    final panelState = _transcriptKey.currentState;
    final segments = panelState != null
        ? panelState.getSegmentsWithEdits()
        : (viewingItem?.segments ?? provider.segments);
    if (segments.isEmpty) return;

    final exportPath = provider.selectedFilePath;
    final audioName =
        viewingItem?.fileName ??
        (exportPath != null ? p.basename(exportPath) : 'transcript');
    final baseName = audioName.contains('.')
        ? audioName.substring(0, audioName.lastIndexOf('.'))
        : audioName;

    final savedDir = await ExportService.saveMultipleFormats(
      baseName: baseName,
      formats: formats,
      contentBuilder: (fmt) => ExportFormatters.format(
        fmt,
        segments,
        jobId: viewingItem?.jobId ?? provider.activeJobId,
      ),
    );

    if (savedDir != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${formats.length} formats to $savedDir'),
        ),
      );
    }
  }
}

class _SidebarExportTile extends StatelessWidget {
  final ExportFormat format;
  final bool enabled;
  final VoidCallback onTap;
  final ThemeData theme;

  const _SidebarExportTile({
    required this.format,
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 15,
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  format.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
              Text(
                '.${format.extension}',
                style: ScribeTheme.monoStyle(
                  context,
                  fontSize: 10,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final ThemeData theme;
  final VoidCallback onTap;

  const _SidebarActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
