import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../providers/transcription_provider.dart';
import 'option_chip.dart';

/// The idle state view with file picker, options, and start button.
class IdleTranscriptionView extends StatelessWidget {
  final String selectedModel;
  final ValueChanged<String> onModelChanged;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;
  final bool enableGpu;
  final ValueChanged<bool> onGpuChanged;
  final bool translateToEnglish;
  final ValueChanged<bool> onTranslateChanged;
  final List<String> downloadedModels;
  final bool isConnected;
  final VoidCallback onPickFiles;
  final VoidCallback onAddMoreFiles;
  final VoidCallback onStartTranscription;

  const IdleTranscriptionView({
    super.key,
    required this.selectedModel,
    required this.onModelChanged,
    required this.language,
    required this.onLanguageChanged,
    required this.enableGpu,
    required this.onGpuChanged,
    required this.translateToEnglish,
    required this.onTranslateChanged,
    required this.downloadedModels,
    required this.isConnected,
    required this.onPickFiles,
    required this.onAddMoreFiles,
    required this.onStartTranscription,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final theme = Theme.of(context);
    final hasFiles = provider.selectedFilePaths.isNotEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
              // Hero area
              Text(
                'Transcribe Audio',
                style: theme.textTheme.displayMedium,
              ),
              const SizedBox(height: 40),

              // File picker card
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPickFiles,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 36),
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasFiles
                            ? theme.colorScheme.primary.withValues(alpha: 0.4)
                            : theme.colorScheme.outlineVariant,
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
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.upload_file_rounded,
                                  size: 28,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Drop audio files or click to browse',
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
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

              const SizedBox(height: 28),

              // Options row
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OptionChip(
                    icon: Icons.model_training_rounded,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: downloadedModels.contains(selectedModel)
                            ? selectedModel
                            : (downloadedModels.isNotEmpty
                                ? downloadedModels.first
                                : 'base'),
                        isDense: true,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                        items: (downloadedModels.isEmpty
                                ? ['base']
                                : downloadedModels)
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) onModelChanged(v);
                        },
                      ),
                    ),
                  ),
                  OptionChip(
                    icon: Icons.language_rounded,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: language,
                        isDense: true,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: null, child: Text('Auto-detect')),
                          DropdownMenuItem(
                              value: 'en', child: Text('English')),
                          DropdownMenuItem(
                              value: 'es', child: Text('Spanish')),
                          DropdownMenuItem(
                              value: 'fr', child: Text('French')),
                          DropdownMenuItem(
                              value: 'de', child: Text('German')),
                          DropdownMenuItem(
                              value: 'it', child: Text('Italian')),
                          DropdownMenuItem(
                              value: 'pt', child: Text('Portuguese')),
                          DropdownMenuItem(
                              value: 'ja', child: Text('Japanese')),
                          DropdownMenuItem(
                              value: 'zh', child: Text('Chinese')),
                          DropdownMenuItem(
                              value: 'ko', child: Text('Korean')),
                        ],
                        onChanged: onLanguageChanged,
                      ),
                    ),
                  ),
                  ToggleChip(
                    label: 'GPU',
                    icon: Icons.memory_rounded,
                    value: enableGpu,
                    onChanged: onGpuChanged,
                  ),
                  ToggleChip(
                    label: 'Translate',
                    icon: Icons.translate_rounded,
                    value: translateToEnglish,
                    onChanged: onTranslateChanged,
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
                      Icon(Icons.error_outline_rounded,
                          color: theme.colorScheme.error, size: 20),
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

              const SizedBox(height: 28),

              // Start button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: isConnected && hasFiles
                      ? onStartTranscription
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
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
      TranscriptionProvider provider, ThemeData theme) {
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
                    Icon(Icons.audio_file_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
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
                        icon: Icon(Icons.close_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
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
          onPressed: onAddMoreFiles,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add more files'),
        ),
      ],
    );
  }
}
