import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/batch_item.dart';
import '../providers/transcription_provider.dart';

/// Panel showing batch transcription progress with a file list.
class BatchQueuePanel extends StatelessWidget {
  final int viewingBatchIndex;
  final ValueChanged<int> onViewingIndexChanged;

  const BatchQueuePanel({
    super.key,
    required this.viewingBatchIndex,
    required this.onViewingIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final theme = Theme.of(context);
    final viewIndex = viewingBatchIndex.clamp(
      0,
      provider.batchQueue.isEmpty ? 0 : provider.batchQueue.length - 1,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        color: theme.colorScheme.surfaceContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Batch Progress', style: theme.textTheme.labelMedium),
              const Spacer(),
              Text(
                '${provider.completedBatchFiles}/${provider.totalBatchFiles} complete',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: provider.totalBatchFiles > 0
                  ? provider.completedBatchFiles / provider.totalBatchFiles
                  : 0,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: provider.batchQueue.length,
              itemBuilder: (context, index) {
                final item = provider.batchQueue[index];
                final isViewing = index == viewIndex;
                return KeyedSubtree(
                  key: ValueKey(item.filePath),
                  child: _buildBatchItemRow(
                    item,
                    index,
                    isViewing,
                    provider,
                    theme,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchItemRow(
    BatchItem item,
    int index,
    bool isViewing,
    TranscriptionProvider provider,
    ThemeData theme,
  ) {
    IconData icon;
    Color color;
    switch (item.status) {
      case BatchItemStatus.pending:
        icon = Icons.hourglass_empty_rounded;
        color = theme.colorScheme.onSurfaceVariant;
      case BatchItemStatus.running:
        icon = Icons.play_circle_rounded;
        color = theme.colorScheme.primary;
      case BatchItemStatus.completed:
        icon = Icons.check_circle_rounded;
        color = theme.colorScheme.onTertiaryContainer;
      case BatchItemStatus.failed:
        icon = Icons.error_rounded;
        color = theme.colorScheme.error;
      case BatchItemStatus.canceled:
        icon = Icons.cancel_rounded;
        color = theme.colorScheme.secondary;
    }

    return Material(
      color: isViewing
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.38)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: item.isTerminal || item.status == BatchItemStatus.running
            ? () => onViewingIndexChanged(index)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.fileName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: item.status == BatchItemStatus.running
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.status == BatchItemStatus.running)
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(item.progress * 100).toInt()}%',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              if (item.status == BatchItemStatus.pending)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => provider.removePendingItem(index),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
