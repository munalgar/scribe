import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transcription_provider.dart';
import '../services/app_preferences.dart';
import '../services/backend_process.dart';
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

  // Test-connection state
  bool _isTesting = false;
  String? _testResult; // "OK 12ms" or error string
  bool _testSuccess = false;

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
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _computeType,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            selectedItemBuilder: (context) => const [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('auto'),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('int8'),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('float16'),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('float32'),
                              ),
                            ],
                            items: [
                              DropdownMenuItem(
                                value: 'auto',
                                child: _ComputeTypeItem(
                                  title: 'auto',
                                  subtitle: 'Best for your hardware',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'int8',
                                child: _ComputeTypeItem(
                                  title: 'int8',
                                  subtitle: 'Fastest, lower precision',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'float16',
                                child: _ComputeTypeItem(
                                  title: 'float16',
                                  subtitle: 'Balanced, ideal for GPUs',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'float32',
                                child: _ComputeTypeItem(
                                  title: 'float32',
                                  subtitle: 'Highest precision, slowest',
                                ),
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
    final prefs = context.watch<AppPreferences>();
    final process = context.watch<BackendProcessManager>();
    final isManaged = prefs.backendMode == BackendMode.managed;
    final isConnected = conn.state == BackendConnectionState.connected;
    final isDev = prefs.devMode;

    final (Color statusColor, String statusLabel) = switch (conn.state) {
      BackendConnectionState.connected => (Colors.green, 'Connected'),
      BackendConnectionState.connecting => (Colors.orange, 'Connecting…'),
      BackendConnectionState.error => (theme.colorScheme.error, 'Disconnected'),
      BackendConnectionState.disconnected => (
        theme.colorScheme.onSurfaceVariant,
        'Offline',
      ),
    };

    return _SectionCard(
      title: 'Server',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (isConnected && conn.latencyMs != null) ...[
            const SizedBox(width: 6),
            Text(
              '${conn.latencyMs}ms',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
              ),
            ),
          ],
        ],
      ),
      children: [
        // ── Backend mode toggle (dev mode only) ─────────────────────────
        if (isDev) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Backend Mode', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        isManaged
                            ? 'Built-in server starts automatically'
                            : 'Connect to an external server',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<BackendMode>(
                  segments: const [
                    ButtonSegment(
                      value: BackendMode.managed,
                      label: Text('Built-in'),
                      icon: Icon(Icons.memory_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: BackendMode.external,
                      label: Text('External'),
                      icon: Icon(Icons.dns_rounded, size: 16),
                    ),
                  ],
                  selected: {prefs.backendMode},
                  onSelectionChanged: (selected) async {
                    final mode = selected.first;
                    await prefs.setBackendMode(mode);
                    if (!context.mounted) return;

                    // Tear down the previous connection (cancels any
                    // pending auto-reconnect timer so it can't
                    // interfere with the new mode).
                    await conn.disconnect();
                    if (!context.mounted) return;

                    if (mode == BackendMode.managed) {
                      // Start the managed backend.
                      try {
                        final port = await process.start();
                        if (context.mounted) {
                          conn.connect(host: '127.0.0.1', port: port);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    } else {
                      // Switch to external: stop managed backend, connect
                      // to configured host/port.
                      await process.stop();
                      conn.connect(
                        host: prefs.serverHost,
                        port: prefs.serverPort,
                      );
                    }
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

          Divider(color: theme.colorScheme.outlineVariant, height: 1),
        ],

        // ── Managed mode controls ────────────────────────────────────────
        if (isManaged) ...[_buildManagedSection(context, process, conn, theme)],

        // ── External mode controls (only reachable in dev mode) ──────────
        if (!isManaged) ...[_buildExternalSection(context, conn, prefs, theme)],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Managed mode UI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildManagedSection(
    BuildContext context,
    BackendProcessManager process,
    ConnectionProvider conn,
    ThemeData theme,
  ) {
    final (Color procColor, IconData procIcon) = switch (process.state) {
      BackendProcessState.running => (Colors.green, Icons.check_circle_rounded),
      BackendProcessState.starting => (Colors.orange, Icons.sync_rounded),
      BackendProcessState.crashed => (
        theme.colorScheme.error,
        Icons.error_rounded,
      ),
      BackendProcessState.stopped => (
        theme.colorScheme.onSurfaceVariant,
        Icons.stop_circle_rounded,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Process status
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(procIcon, size: 18, color: procColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      process.stateLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (process.crashCount > 0)
                      Text(
                        'Crashed ${process.crashCount} time${process.crashCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              // Action buttons
              if (process.isRunning) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final port = await process.restart();
                      if (context.mounted) {
                        conn.connect(host: '127.0.0.1', port: port);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Restart'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    await process.stop();
                    await conn.disconnect();
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Stop'),
                ),
              ] else if (process.state == BackendProcessState.stopped ||
                  process.state == BackendProcessState.crashed) ...[
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      final port = await process.start();
                      if (context.mounted) {
                        conn.connect(host: '127.0.0.1', port: port);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else ...[
                // Starting state
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),

        // Log viewer (dev mode only)
        if (process.logs.isNotEmpty &&
            context.read<AppPreferences>().devMode) ...[
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          _BackendLogViewer(logs: process.logs, theme: theme),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // External mode UI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExternalSection(
    BuildContext context,
    ConnectionProvider conn,
    AppPreferences prefs,
    ThemeData theme,
  ) {
    final isConnected = conn.state == BackendConnectionState.connected;

    return Column(
      children: [
        // Current address display when not editing
        if (!_serverDirty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                SelectableText(
                  conn.address,
                  style: ScribeTheme.monoStyle(
                    context,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (prefs.isEnvOverride) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'ENV',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _serverDirty = true);
                    _hostController.text = prefs.serverHost;
                    _portController.text = prefs.serverPort.toString();
                  },
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Change'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

        // Editable host/port fields
        if (_serverDirty) ...[
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
                      hintText: '127.0.0.1',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: ScribeTheme.monoStyle(context, fontSize: 13),
                    onChanged: (_) {
                      _testResult = null;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '50051',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: ScribeTheme.monoStyle(context, fontSize: 13),
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      _testResult = null;
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          // Test result badge
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Icon(
                    _testSuccess
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 16,
                    color: _testSuccess
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _testResult!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _testSuccess
                          ? Colors.green
                          : theme.colorScheme.error,
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
                  onPressed: () async {
                    final host = _hostController.text.trim();
                    final port =
                        int.tryParse(_portController.text.trim()) ??
                        AppPreferences.defaultPort;
                    await prefs.setServerConnection(host, port);
                    await conn.connect(host: host, port: port);
                    setState(() {
                      _serverDirty = false;
                      _testResult = null;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Connecting to server…')),
                      );
                    }
                  },
                  child: const Text('Save & Connect'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isTesting
                      ? null
                      : () async {
                          final host = _hostController.text.trim();
                          final port =
                              int.tryParse(_portController.text.trim()) ??
                              AppPreferences.defaultPort;
                          setState(() {
                            _isTesting = true;
                            _testResult = null;
                          });
                          try {
                            final latency = await conn.testConnection(
                              host,
                              port,
                            );
                            _testResult = 'Reachable  ·  ${latency}ms';
                            _testSuccess = true;
                          } catch (e) {
                            _testResult = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                            _testSuccess = false;
                          }
                          setState(() => _isTesting = false);
                        },
                  child: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _hostController.text = prefs.serverHost;
                    _portController.text = prefs.serverPort.toString();
                    setState(() {
                      _serverDirty = false;
                      _testResult = null;
                    });
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],

        // Error message
        if (conn.state == BackendConnectionState.error &&
            conn.errorMessage != null) ...[
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => conn.retry(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          if (conn.reconnectAttempts > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Auto-reconnect attempt ${conn.reconnectAttempts}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
        ],

        // Reconnect actions when connected
        if (isConnected && !_serverDirty) ...[
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => conn.retry(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reconnect'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await prefs.resetServerConnection();
                    _hostController.text = prefs.serverHost;
                    _portController.text = prefs.serverPort.toString();
                    await conn.connect(
                      host: prefs.serverHost,
                      port: prefs.serverPort,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reset to default address'),
                        ),
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Reset to Default'),
                ),
              ],
            ),
          ),
        ],
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
    final downloadedModels = settings.models
        .where((m) => m.downloaded)
        .toList();
    final totalModelBytes = downloadedModels.fold<int>(
      0,
      (sum, m) => sum + m.size.toInt(),
    );

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
    final prefs = context.watch<AppPreferences>();
    final isDev = prefs.devMode;

    return _SectionCard(
      title: 'About',
      children: [
        _AboutRow(label: 'Version', value: _appVersion, theme: theme),
        Divider(
          color: theme.colorScheme.outlineVariant,
          height: 1,
          indent: 20,
          endIndent: 20,
        ),

        // Developer mode toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Developer Mode', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Show advanced server controls and logs',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isDev,
                onChanged: (value) async {
                  await prefs.setDevMode(value);
                  if (!value && context.mounted) {
                    // Turning off dev mode — revert to managed mode
                    // so the user doesn't get stuck on external.
                    if (prefs.backendMode == BackendMode.external) {
                      final process = context.read<BackendProcessManager>();
                      await prefs.setBackendMode(BackendMode.managed);
                      if (!context.mounted) return;
                      await conn.disconnect();
                      if (!context.mounted) return;
                      try {
                        final port = await process.start();
                        if (context.mounted) {
                          conn.connect(host: '127.0.0.1', port: port);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    }
                  }
                },
              ),
            ],
          ),
        ),

        // Dev-only info
        if (isDev) ...[
          Divider(
            color: theme.colorScheme.outlineVariant,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          _AboutRow(
            label: 'Build mode',
            value: AppPreferences.isDevMode ? 'Debug' : 'Release',
            theme: theme,
          ),
          Divider(
            color: theme.colorScheme.outlineVariant,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dev tips',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Set SCRIBE_BACKEND_HOST / SCRIBE_BACKEND_PORT env vars\n'
                  '• Run bash scripts/dev_backend.sh to start the server\n'
                  '• Enable "External" backend mode above to connect manually',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.5,
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

class _ComputeTypeItem extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ComputeTypeItem({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
  final ThemeData theme;

  const _AboutRow({required this.label, this.value, required this.theme});

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
          Text(
            value ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible log viewer for the managed backend process output.
class _BackendLogViewer extends StatefulWidget {
  final List<String> logs;
  final ThemeData theme;

  const _BackendLogViewer({required this.logs, required this.theme});

  @override
  State<_BackendLogViewer> createState() => _BackendLogViewerState();
}

class _BackendLogViewerState extends State<_BackendLogViewer> {
  bool _expanded = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _BackendLogViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when new logs arrive and expanded.
    if (_expanded && widget.logs.length != oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Logs',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${widget.logs.length} lines)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            height: 180,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: widget.logs.length,
              itemBuilder: (_, i) => Text(
                widget.logs[i],
                style: ScribeTheme.monoStyle(
                  context,
                  fontSize: 11,
                  color: widget.logs[i].contains('[stderr]')
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
