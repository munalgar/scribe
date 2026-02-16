import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        bgColor = theme.brightness == Brightness.light
            ? const Color(0xFFD4EDDA)
            : const Color(0xFF1E3A28);
        textColor = theme.brightness == Brightness.light
            ? const Color(0xFF2D6A3F)
            : const Color(0xFF8BC99B);
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == JobStatus.RUNNING)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 12,
                height: 12,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: textColor),
              ),
            ),
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: 14, color: textColor),
            ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
