import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transcription_provider.dart';
import '../services/app_preferences.dart';
import '../theme.dart';

const _appVersion = '1.0.0';

class _LangOption {
  final String code;
  final String label;
  const _LangOption(this.code, this.label);
}

const List<_LangOption> _languages = [
  _LangOption('en', 'English'),
  _LangOption('es', 'Spanish'),
  _LangOption('fr', 'French'),
  _LangOption('de', 'German'),
  _LangOption('it', 'Italian'),
  _LangOption('pt', 'Portuguese'),
  _LangOption('ja', 'Japanese'),
  _LangOption('zh', 'Chinese'),
  _LangOption('ko', 'Korean'),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _computeType = 'auto';
  bool _dirty = false;

  // Server connection editing state
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _serverDirty = false;

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
  void initState() {
    super.initState();
    final prefs = context.read<AppPreferences>();
    _hostController = TextEditingController(text: prefs.serverHost);
    _portController = TextEditingController(text: prefs.serverPort.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
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
                      Divider(
                        color: theme.colorScheme.outlineVariant,
                        height: 1,
                      ),
                      _buildLanguageSetting(context, theme),
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

                  // Server connection section
                  _buildServerConnectionSection(context, conn, theme),

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

                  const SizedBox(height: 20),

                  // Storage info section
                  _buildStorageSection(context, provider, theme),

                  const SizedBox(height: 20),

                  // About section
                  _buildAboutSection(context, conn, theme),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSetting(BuildContext context, ThemeData theme) {
    final prefs = context.watch<AppPreferences>();
    final currentLang = prefs.defaultLanguage;

    return _SettingRow(
      label: 'Default Language',
      description: 'Pre-selected language for new transcriptions',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: currentLang,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Auto-detect'),
            ),
            ..._languages.map(
              (lang) => DropdownMenuItem<String?>(
                value: lang.code,
                child: Text(lang.label),
              ),
            ),
          ],
          onChanged: (v) => prefs.setDefaultLanguage(v),
        ),
      ),
    );
  }

  Widget _buildServerConnectionSection(
    BuildContext context,
    ConnectionProvider conn,
    ThemeData theme,
  ) {
    final prefs = context.read<AppPreferences>();

    return _SectionCard(
      title: 'Server Connection',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Host',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: ScribeTheme.monoStyle(context, fontSize: 13),
                  onChanged: (_) => setState(() => _serverDirty = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: ScribeTheme.monoStyle(context, fontSize: 13),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _serverDirty = true),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: _serverDirty
                    ? () async {
                        final host = _hostController.text.trim();
                        final port =
                            int.tryParse(_portController.text.trim()) ??
                                AppPreferences.defaultPort;
                        await prefs.setServerConnection(host, port);
                        await conn.connect(host: host, port: port);
                        setState(() => _serverDirty = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reconnecting to server…'),
                            ),
                          );
                        }
                      }
                    : null,
                child: const Text('Reconnect'),
              ),
              if (_serverDirty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    _hostController.text = prefs.serverHost;
                    _portController.text = prefs.serverPort.toString();
                    setState(() => _serverDirty = false);
                  },
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection(
    BuildContext context,
    SettingsProvider settings,
    ThemeData theme,
  ) {
    final transcription = context.watch<TranscriptionProvider>();
    final jobCount = transcription.jobs.length;
    final downloadedModels =
        settings.models.where((m) => m.downloaded).toList();
    final totalModelBytes =
        downloadedModels.fold<int>(0, (sum, m) => sum + m.size.toInt());

    return _SectionCard(
      title: 'Storage',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              _StorageStat(
                icon: Icons.history_rounded,
                label: 'Transcriptions',
                value: '$jobCount',
                theme: theme,
              ),
              const SizedBox(width: 24),
              _StorageStat(
                icon: Icons.model_training_rounded,
                label: 'Models on disk',
                value: downloadedModels.isEmpty
                    ? 'None'
                    : '${downloadedModels.length}  ·  ${_formatBytes(totalModelBytes)}',
                theme: theme,
              ),
            ],
          ),
        ),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: jobCount == 0
                    ? null
                    : () => _confirmClearHistory(context, transcription),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Clear All History'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: jobCount == 0
                        ? theme.colorScheme.outlineVariant
                        : theme.colorScheme.error.withAlpha(120),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    TranscriptionProvider transcription,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all history?'),
        content: Text(
          'This will permanently delete ${transcription.jobs.length} '
          'transcription${transcription.jobs.length == 1 ? '' : 's'} '
          'and their segments. Downloaded models will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ids = transcription.jobs.map((j) => j.jobId).toList();
      final deleted = await transcription.deleteJobs(ids);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $deleted transcription(s)')),
        );
      }
    }
  }

  Widget _buildAboutSection(
    BuildContext context,
    ConnectionProvider conn,
    ThemeData theme,
  ) {
    final isConnected = conn.state == BackendConnectionState.connected;
    final stateLabel = switch (conn.state) {
      BackendConnectionState.connected => 'Connected',
      BackendConnectionState.connecting => 'Connecting…',
      BackendConnectionState.error => 'Disconnected',
      BackendConnectionState.disconnected => 'Disconnected',
    };
    final stateColor = switch (conn.state) {
      BackendConnectionState.connected => Colors.green,
      BackendConnectionState.connecting => Colors.orange,
      _ => theme.colorScheme.error,
    };

    return _SectionCard(
      title: 'About',
      children: [
        _AboutRow(
          label: 'Version',
          value: _appVersion,
          theme: theme,
        ),
        Divider(
          color: theme.colorScheme.outlineVariant,
          height: 1,
          indent: 20,
          endIndent: 20,
        ),
        _AboutRow(
          label: 'Backend',
          theme: theme,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stateLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Divider(
          color: theme.colorScheme.outlineVariant,
          height: 1,
          indent: 20,
          endIndent: 20,
        ),
        _AboutRow(
          label: 'Server address',
          value: '${conn.host}:${conn.port}',
          mono: true,
          theme: theme,
        ),
        if (!isConnected && conn.errorMessage != null) ...[
          Divider(
            color: theme.colorScheme.outlineVariant,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conn.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _StorageStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _StorageStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool mono;
  final Widget? child;
  final ThemeData theme;

  const _AboutRow({
    required this.label,
    this.value,
    this.mono = false,
    this.child,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (child != null)
            child!
          else
            Text(
              value ?? '',
              style: mono
                  ? ScribeTheme.monoStyle(
                      context,
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
        ],
      ),
    );
  }
}
