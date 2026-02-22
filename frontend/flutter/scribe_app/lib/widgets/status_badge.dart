import 'package:flutter/material.dart';

import '../proto/scribe.pbgrpc.dart';

/// Badge displaying the current job status with icon and color.
class StatusBadge extends StatelessWidget {
  final JobStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color bgColor;
    Color textColor;
    String label;
    IconData? icon;

    switch (status) {
      case JobStatus.QUEUED:
        bgColor = theme.colorScheme.secondaryContainer;
        textColor = theme.colorScheme.onSecondaryContainer;
        label = 'Queued';
        icon = Icons.hourglass_empty_rounded;
      case JobStatus.RUNNING:
        bgColor = theme.colorScheme.primaryContainer;
        textColor = theme.colorScheme.primary;
        label = 'Transcribing';
        icon = null;
      case JobStatus.COMPLETED:
        bgColor = theme.colorScheme.tertiaryContainer;
        textColor = theme.colorScheme.onTertiaryContainer;
        label = 'Completed';
        icon = Icons.check_rounded;
      case JobStatus.FAILED:
        bgColor = theme.colorScheme.errorContainer;
        textColor = theme.colorScheme.error;
        label = 'Failed';
        icon = Icons.close_rounded;
      case JobStatus.CANCELED:
        bgColor = theme.colorScheme.secondaryContainer;
        textColor = theme.colorScheme.secondary;
        label = 'Canceled';
        icon = Icons.stop_rounded;
      default:
        bgColor = theme.colorScheme.surfaceContainerHigh;
        textColor = theme.colorScheme.onSurfaceVariant;
        label = '';
        icon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == JobStatus.RUNNING)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              ),
            ),
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: 13, color: textColor),
            ),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
