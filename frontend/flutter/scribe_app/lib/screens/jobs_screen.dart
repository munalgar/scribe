import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../providers/connection_provider.dart';
import '../providers/transcription_provider.dart';
import '../proto/scribe.pb.dart' as pb;
import '../proto/scribe.pbgrpc.dart';
import '../services/export_formatters.dart';
import '../services/export_service.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();

  static Future<void> exportJob(
    BuildContext context,
    TranscriptionProvider provider,
    pb.JobSummary job,
    ExportFormat format,
  ) async {
    final dialogRoute = DialogRoute(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    Navigator.of(context).push(dialogRoute);

    final response = await provider.fetchFullTranscript(job.jobId);

    if (dialogRoute.isActive && context.mounted) {
      Navigator.of(context).removeRoute(dialogRoute);
    }

    if (response == null || response.segments.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transcript data available')),
        );
      }
      return;
    }

    final audioName = response.audioPath.isNotEmpty
        ? p.basename(response.audioPath)
        : job.jobId;
    final baseName = audioName.contains('.')
        ? audioName.substring(0, audioName.lastIndexOf('.'))
        : audioName;
    final defaultFileName = '$baseName.${format.extension}';

    final content = ExportFormatters.format(
      format,
      response.segments.toList(),
      jobId: job.jobId,
      audioPath: response.audioPath,
      model: response.model,
      language: response.language,
      createdAt: job.createdAt,
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

  static void confirmDelete(
      BuildContext context, TranscriptionProvider provider, String jobId) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transcription'),
        content: const Text(
            'This will permanently remove this transcription and its data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.deleteJob(jobId);
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _JobsScreenState extends State<JobsScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _toggleSelect(String jobId) {
    setState(() {
      if (_selected.contains(jobId)) {
        _selected.remove(jobId);
      } else {
        _selected.add(jobId);
      }
    });
  }

  void _selectAll(List<pb.JobSummary> jobs) {
    setState(() {
      if (_selected.length == jobs.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(jobs.map((j) => j.jobId));
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _confirmBatchDelete(TranscriptionProvider provider) {
    final count = _selected.length;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected'),
        content: Text(
            'This will permanently remove $count transcription${count == 1 ? '' : 's'} and their data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final ids = _selected.toList();
              _exitSelectMode();
              provider.deleteJobs(ids);
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: Text('Delete $count'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final conn = context.watch<ConnectionProvider>();
    final isConnected = conn.state == BackendConnectionState.connected;
    final theme = Theme.of(context);

    // Clean up stale selections
    if (_selectMode) {
      final validIds = provider.jobs.map((j) => j.jobId).toSet();
      _selected.retainAll(validIds);
      if (_selected.isEmpty && provider.jobs.isEmpty) {
        _selectMode = false;
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider, isConnected, theme),
              const SizedBox(height: 8),
              Text(
                'Your transcription history',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
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
              Expanded(
                child: provider.jobs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.history_rounded,
                                size: 32,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No transcriptions yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your completed transcriptions will appear here',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: provider.jobs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final job = provider.jobs[index];
                          return _JobCard(
                            key: ValueKey(job.jobId),
                            job: job,
                            provider: provider,
                            isConnected: isConnected,
                            selectMode: _selectMode,
                            isSelected: _selected.contains(job.jobId),
                            onToggleSelect: () => _toggleSelect(job.jobId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      TranscriptionProvider provider, bool isConnected, ThemeData theme) {
    if (_selectMode) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel selection',
            onPressed: _exitSelectMode,
          ),
          const SizedBox(width: 4),
          Text(
            '${_selected.length} selected',
            style: theme.textTheme.titleMedium,
          ),
          const Spacer(),
          TextButton(
            onPressed: provider.jobs.isNotEmpty
                ? () => _selectAll(provider.jobs)
                : null,
            child: Text(
              _selected.length == provider.jobs.length
                  ? 'Deselect All'
                  : 'Select All',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed:
                _selected.isNotEmpty && isConnected
                    ? () => _confirmBatchDelete(provider)
                    : null,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Text('History', style: theme.textTheme.headlineLarge),
        const Spacer(),
        if (provider.jobs.isNotEmpty)
          IconButton(
            icon: Icon(Icons.checklist_rounded,
                color: theme.colorScheme.onSurfaceVariant),
            tooltip: 'Select',
            onPressed: isConnected
                ? () => setState(() => _selectMode = true)
                : null,
          ),
        IconButton(
          icon: Icon(Icons.refresh_rounded,
              color: theme.colorScheme.onSurfaceVariant),
          tooltip: 'Refresh',
          onPressed: isConnected ? () => provider.loadJobs() : null,
        ),
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  final pb.JobSummary job;
  final TranscriptionProvider provider;
  final bool isConnected;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onToggleSelect;

  const _JobCard({
    super.key,
    required this.job,
    required this.provider,
    required this.isConnected,
    required this.selectMode,
    required this.isSelected,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: selectMode ? onToggleSelect : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            if (selectMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelect(),
              ),
              const SizedBox(width: 6),
            ],
            _statusIcon(theme, job.status),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.jobId.length > 8
                        ? '${job.jobId.substring(0, 8)}...'
                        : job.jobId,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.createdAt.isNotEmpty ? job.createdAt : 'Unknown date',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!selectMode) ...[
              if (job.status == JobStatus.COMPLETED)
                PopupMenuButton<ExportFormat>(
                  icon: Icon(Icons.download_rounded,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                  tooltip: 'Export',
                  onSelected: (format) =>
                      JobsScreen.exportJob(context, provider, job, format),
                  itemBuilder: (context) => ExportFormat.values
                      .map((f) => PopupMenuItem(
                            value: f,
                            child: Text('${f.label} (.${f.extension})'),
                          ))
                      .toList(),
                ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                tooltip: 'Delete',
                onPressed: isConnected
                    ? () =>
                        JobsScreen.confirmDelete(context, provider, job.jobId)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(ThemeData theme, JobStatus status) {
    IconData icon;
    Color color;
    Color bgColor;

    switch (status) {
      case JobStatus.COMPLETED:
        icon = Icons.check_rounded;
        color = theme.brightness == Brightness.light
            ? const Color(0xFF2D6A3F) : const Color(0xFF8BC99B);
        bgColor = theme.brightness == Brightness.light
            ? const Color(0xFFD4EDDA) : const Color(0xFF1E3A28);
      case JobStatus.FAILED:
        icon = Icons.close_rounded;
        color = theme.colorScheme.error;
        bgColor = theme.colorScheme.errorContainer;
      case JobStatus.CANCELED:
        icon = Icons.stop_rounded;
        color = theme.colorScheme.secondary;
        bgColor = theme.colorScheme.secondaryContainer;
      case JobStatus.RUNNING:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      case JobStatus.QUEUED:
        icon = Icons.hourglass_empty_rounded;
        color = theme.colorScheme.primary;
        bgColor = theme.colorScheme.primaryContainer;
      default:
        icon = Icons.help_outline_rounded;
        color = theme.colorScheme.onSurfaceVariant;
        bgColor = theme.colorScheme.surfaceContainerHigh;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
