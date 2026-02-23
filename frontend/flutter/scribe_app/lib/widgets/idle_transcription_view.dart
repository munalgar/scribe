import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';

import '../providers/transcription_provider.dart';
import 'option_chip.dart';

class _LanguageOption {
  final String code;
  final String label;

  const _LanguageOption(this.code, this.label);
}

const List<_LanguageOption> _supportedLanguages = <_LanguageOption>[
  _LanguageOption('en', 'English'),
  _LanguageOption('es', 'Spanish'),
  _LanguageOption('fr', 'French'),
  _LanguageOption('de', 'German'),
  _LanguageOption('it', 'Italian'),
  _LanguageOption('pt', 'Portuguese'),
  _LanguageOption('ja', 'Japanese'),
  _LanguageOption('zh', 'Chinese'),
  _LanguageOption('ko', 'Korean'),
];
const String _bundledModel = 'base';

/// Allowed audio file extensions for drag-and-drop filtering.
const Set<String> _allowedExtensions = {
  '.wav',
  '.mp3',
  '.m4a',
  '.flac',
  '.ogg',
  '.mp4',
  '.webm',
};

/// The idle state view with file picker, options, and start button.
class IdleTranscriptionView extends StatefulWidget {
  final String selectedModel;
  final ValueChanged<String> onModelChanged;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;
  final bool enableGpu;
  final ValueChanged<bool> onGpuChanged;
  final String? translateToLanguage;
  final ValueChanged<String?> onTranslateLanguageChanged;
  final List<String> downloadedModels;
  final bool isConnected;
  final VoidCallback onPickFiles;
  final VoidCallback onAddMoreFiles;
  final VoidCallback onStartTranscription;
  final ValueChanged<List<String>> onFilesDropped;

  const IdleTranscriptionView({
    super.key,
    required this.selectedModel,
    required this.onModelChanged,
    required this.language,
    required this.onLanguageChanged,
    required this.enableGpu,
    required this.onGpuChanged,
    required this.translateToLanguage,
    required this.onTranslateLanguageChanged,
    required this.downloadedModels,
    required this.isConnected,
    required this.onPickFiles,
    required this.onAddMoreFiles,
    required this.onStartTranscription,
    required this.onFilesDropped,
  });

  @override
  State<IdleTranscriptionView> createState() => _IdleTranscriptionViewState();
}

class _IdleTranscriptionViewState extends State<IdleTranscriptionView> {
  bool _isDragging = false;

  void _handleDrop(DropDoneDetails details) {
    setState(() => _isDragging = false);
    final paths = details.files
        .map((f) => f.path)
        .where(
          (path) =>
              _allowedExtensions.contains(p.extension(path).toLowerCase()),
        )
        .toList();
    if (paths.isNotEmpty) {
      widget.onFilesDropped(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final theme = Theme.of(context);
    final hasFiles = provider.selectedFilePaths.isNotEmpty;
    final visibleSelectedModel =
        widget.downloadedModels.contains(widget.selectedModel)
        ? widget.selectedModel
        : (widget.downloadedModels.isNotEmpty
              ? widget.downloadedModels.first
              : _bundledModel);
    final isUsingNonBundledModel = visibleSelectedModel != _bundledModel;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hero area
                      Text(
                        'Transcribe Audio',
                        style: theme.textTheme.displayMedium,
                      ),
                      const SizedBox(height: 34),

                      // File picker card with drag-and-drop
                      DropTarget(
                        onDragEntered: (_) =>
                            setState(() => _isDragging = true),
                        onDragExited: (_) =>
                            setState(() => _isDragging = false),
                        onDragDone: _handleDrop,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onPickFiles,
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 36,
                              ),
                              decoration: BoxDecoration(
                                color: _isDragging
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.08,
                                      )
                                    : theme.cardTheme.color,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _isDragging
                                      ? theme.colorScheme.primary
                                      : hasFiles
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.4,
                                        )
                                      : theme.colorScheme.outlineVariant,
                                  width: _isDragging ? 2 : 1,
                                ),
                              ),
                              child: hasFiles
                                  ? _buildSelectedFilesList(provider, theme)
                                  : Column(
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Icon(
                                            _isDragging
                                                ? Icons.file_download_rounded
                                                : Icons.upload_file_rounded,
                                            size: 28,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextButton(
                                          onPressed: widget.onPickFiles,
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: Text(
                                            _isDragging
                                                ? 'Release to add files'
                                                : 'Drop audio files or click to browse',
                                            style: theme.textTheme.titleMedium,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'WAV, MP3, M4A, FLAC, OGG, MP4, WebM',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Options row
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          OptionChip(
                            icon: Icons.model_training_rounded,
                            active: isUsingNonBundledModel,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: visibleSelectedModel,
                                isDense: true,
                                dropdownColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(10),
                                iconEnabledColor: isUsingNonBundledModel
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: isUsingNonBundledModel
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                items:
                                    (widget.downloadedModels.isEmpty
                                            ? [_bundledModel]
                                            : widget.downloadedModels)
                                        .map(
                                          (m) => DropdownMenuItem(
                                            value: m,
                                            child: Text(
                                              m,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface,
                                                  ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  if (v != null) widget.onModelChanged(v);
                                },
                              ),
                            ),
                          ),
                          OptionChip(
                            icon: Icons.language_rounded,
                            active: widget.language != null,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: widget.language,
                                isDense: true,
                                dropdownColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(10),
                                iconEnabledColor: widget.language != null
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: widget.language != null
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text(
                                      'Auto-detect',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                                  ),
                                  ..._supportedLanguages.map(
                                    (option) => DropdownMenuItem<String?>(
                                      value: option.code,
                                      child: Text(
                                        option.label,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: widget.onLanguageChanged,
                              ),
                            ),
                          ),
                          ToggleChip(
                            label: 'GPU',
                            icon: Icons.memory_rounded,
                            value: widget.enableGpu,
                            onChanged: widget.onGpuChanged,
                          ),
                          OptionChip(
                            icon: Icons.translate_rounded,
                            active: widget.translateToLanguage != null,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: widget.translateToLanguage,
                                isDense: true,
                                dropdownColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(10),
                                iconEnabledColor:
                                    widget.translateToLanguage != null
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: widget.translateToLanguage != null
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(
                                      'Off',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                                  ),
                                  ..._supportedLanguages.map(
                                    (option) => DropdownMenuItem<String?>(
                                      value: option.code,
                                      child: Text(
                                        option.label,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: widget.onTranslateLanguageChanged,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (provider.error != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  provider.error!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Start button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (_) => theme.colorScheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (_) => theme.colorScheme.onSurface.withValues(
                                alpha: 0.38,
                              ),
                            ),
                          ),
                          onPressed: widget.isConnected && hasFiles
                              ? widget.onStartTranscription
                              : null,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                provider.selectedFilePaths.length > 1
                                    ? 'Start Batch (${provider.selectedFilePaths.length} files)'
                                    : 'Start Transcription',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedFilesList(
    TranscriptionProvider provider,
    ThemeData theme,
  ) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.audio_file_rounded,
            size: 28,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${provider.selectedFilePaths.length} file${provider.selectedFilePaths.length == 1 ? '' : 's'} selected',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: provider.selectedFilePaths.length,
            itemBuilder: (context, index) {
              final fileName = p.basename(provider.selectedFilePaths[index]);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      Icons.audio_file_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => provider.removeSelectedFile(index),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: widget.onAddMoreFiles,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add more files'),
        ),
      ],
    );
  }
}
