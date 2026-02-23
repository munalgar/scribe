import 'package:flutter/material.dart';

import '../services/export_formatters.dart';

/// A dialog that lets the user pick one or more export formats.
/// Returns the selected list of [ExportFormat]s, or null if cancelled.
class ExportFormatDialog extends StatefulWidget {
  /// Optional title override (e.g. for batch export).
  final String title;

  const ExportFormatDialog({super.key, this.title = 'Export Transcript'});

  @override
  State<ExportFormatDialog> createState() => _ExportFormatDialogState();

  /// Convenience method to show the dialog and return selected formats.
  static Future<List<ExportFormat>?> show(
    BuildContext context, {
    String title = 'Export Transcript',
  }) {
    return showDialog<List<ExportFormat>>(
      context: context,
      builder: (_) => ExportFormatDialog(title: title),
    );
  }
}

class _ExportFormatDialogState extends State<ExportFormatDialog> {
  final Set<ExportFormat> _selected = {ExportFormat.txt};

  bool get _allSelected => _selected.length == ExportFormat.values.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(ExportFormat.values);
      }
    });
  }

  void _toggle(ExportFormat fmt) {
    setState(() {
      if (_selected.contains(fmt)) {
        _selected.remove(fmt);
      } else {
        _selected.add(fmt);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose the formats to export:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Select All toggle
            CheckboxListTile(
              dense: true,
              value: _allSelected,
              tristate: true,
              title: Text(
                'Select All',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (_) => _toggleAll(),
            ),
            const Divider(height: 1),
            // Individual format checkboxes
            ...ExportFormat.values.map(
              (fmt) => CheckboxListTile(
                dense: true,
                value: _selected.contains(fmt),
                title: Text('${fmt.label} (.${fmt.extension})'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (_) => _toggle(fmt),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isNotEmpty
              ? () => Navigator.pop(context, _selected.toList())
              : null,
          child: Text(
            _selected.length == 1
                ? 'Export'
                : 'Export ${_selected.length} formats',
          ),
        ),
      ],
    );
  }
}
