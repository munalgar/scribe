import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _computeType = 'auto';
  bool _dirty = false;

  static String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  static String _formatEta(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  String _downloadStatusLabel(SettingsProvider provider) {
    final downloaded = provider.downloadedBytes;
    final total = provider.totalBytes;
    if (total <= 0) return 'Starting...';
    final pct = (provider.downloadProgress * 100).toStringAsFixed(0);
    final label =
        '${_formatBytes(downloaded)} / ${_formatBytes(total)}  ($pct%)';
    final eta = provider.downloadEtaSeconds;
    if (eta != null) return '$label  ~${_formatEta(eta)} remaining';
    return label;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsProvider>().settings;
    if (settings != null && !_dirty) {
      _computeType = settings.computeType.isNotEmpty
          ? settings.computeType
          : 'auto';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final conn = context.watch<ConnectionProvider>();
    final isConnected = conn.state == BackendConnectionState.connected;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settings', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Configure transcription defaults and manage models',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Transcription defaults section
                  _SectionCard(
                    title: 'Transcription Defaults',
                    children: [
                      _SettingRow(
                        label: 'Compute Type',
                        description: 'Precision level for model inference',
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _computeType,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'auto',
                                child: Text('auto'),
                              ),
                              DropdownMenuItem(
                                value: 'int8',
                                child: Text('int8'),
                              ),
                              DropdownMenuItem(
                                value: 'float16',
                                child: Text('float16'),
                              ),
                              DropdownMenuItem(
                                value: 'float32',
                                child: Text('float32'),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _computeType = v ?? 'auto';
                                _dirty = true;
                              });
                            },
                          ),
                        ),
                      ),
                      if (provider.settings?.modelsDir.isNotEmpty == true) ...[
                        Divider(
                          color: theme.colorScheme.outlineVariant,
                          height: 1,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  provider.settings!.modelsDir,
                                  style: ScribeTheme.monoStyle(
                                    context,
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: FilledButton(
                          onPressed: isConnected && _dirty
                              ? () async {
                                  await provider.updateSettings(
                                    computeType: _computeType,
                                  );
                                  setState(() => _dirty = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Settings saved'),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          child: const Text('Save Settings'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Model management section
                  _SectionCard(
                    title: 'Models',
                    children: [
                      if (provider.modelsError != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    provider.modelsError!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (provider.models.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Center(
                            child: Text(
                              'No models available',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        ...provider.models.indexed.map((entry) {
                          final (i, model) = entry;
                          final isLast = i == provider.models.length - 1;
                          final isDownloading =
                              provider.downloadingModel == model.name;
                          final sizeMb = model.size.toInt() / (1024 * 1024);
                          final sizeLabel = sizeMb >= 1024
                              ? '${(sizeMb / 1024).toStringAsFixed(1)} GB'
                              : '${sizeMb.toStringAsFixed(0)} MB';

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            model.name,
                                            style: theme.textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 2),
                                          if (isDownloading) ...[
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value:
                                                    provider.downloadProgress >
                                                        0
                                                    ? provider.downloadProgress
                                                    : null,
                                                minHeight: 6,
                                                color:
                                                    theme.colorScheme.primary,
                                                backgroundColor: theme
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _downloadStatusLabel(provider),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ] else
                                            Text(
                                              sizeLabel,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (isDownloading)
                                      IconButton(
                                        icon: Icon(
                                          Icons.close_rounded,
                                          size: 20,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                        tooltip: 'Cancel download',
                                        onPressed: () =>
                                            provider.cancelDownload(),
                                      )
                                    else if (model.downloaded)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme
                                                  .tertiaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Downloaded',
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                    color: theme
                                                        .colorScheme
                                                        .onTertiaryContainer,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                            tooltip: 'Delete model',
                                            onPressed: () => provider
                                                .deleteModel(model.name),
                                          ),
                                        ],
                                      )
                                    else
                                      OutlinedButton(
                                        onPressed: isConnected
                                            ? () => provider.downloadModel(
                                                model.name,
                                              )
                                            : null,
                                        child: const Text('Download'),
                                      ),
                                  ],
                                ),
                              ),
                              if (!isLast)
                                Divider(
                                  color: theme.colorScheme.outlineVariant,
                                  height: 1,
                                  indent: 20,
                                  endIndent: 20,
                                ),
                            ],
                          );
                        }),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
            child: Row(
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
          ),
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String description;
  final Widget child;

  const _SettingRow({
    required this.label,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }
}
