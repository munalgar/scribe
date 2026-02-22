import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/connection_provider.dart';
import '../providers/transcription_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/idle_transcription_view.dart';
import '../widgets/transcription_result_view.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  String _selectedModel = 'base';
  bool _enableGpu = true;
  String? _language;
  String? _translateToLanguage;
  final ScrollController _scrollController = ScrollController();
  int _viewingBatchIndex = 0;
  int _lastSegmentCount = 0;

  late final Player _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = Player();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickFiles({bool replace = true}) async {
    final provider = context.read<TranscriptionProvider>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'flac', 'ogg', 'mp4', 'webm'],
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      if (paths.isNotEmpty) {
        if (replace) {
          provider.selectFiles(paths);
        } else {
          provider.addFiles(paths);
        }
      }
    }
  }

  Future<void> _startTranscription() async {
    final provider = context.read<TranscriptionProvider>();
    if (provider.selectedFilePaths.isEmpty) return;

    await _audioPlayer.stop();
    setState(() => _viewingBatchIndex = 0);

    await provider.startBatchTranscription(
      model: _selectedModel,
      enableGpu: _enableGpu,
      language: _language,
      translateToLanguage: _translateToLanguage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranscriptionProvider>();
    final conn = context.watch<ConnectionProvider>();
    final settings = context.watch<SettingsProvider>();
    final isConnected = conn.state == BackendConnectionState.connected;

    final downloadedModels = settings.models
        .where((m) => m.downloaded)
        .map((m) => m.name)
        .toList();

    if (downloadedModels.isNotEmpty &&
        !downloadedModels.contains(_selectedModel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedModel = downloadedModels.first);
        }
      });
    }

    if (provider.isTranscribing &&
        provider.currentBatchIndex >= 0 &&
        _viewingBatchIndex != provider.currentBatchIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _viewingBatchIndex = provider.currentBatchIndex);
        }
      });
    }

    final currentSegmentCount = provider.segments.length;
    if (currentSegmentCount == 0) {
      _lastSegmentCount = 0;
    } else if (currentSegmentCount > _lastSegmentCount) {
      _lastSegmentCount = currentSegmentCount;
      _scrollToBottom();
    }

    if (provider.isTranscribing || provider.batchQueue.isNotEmpty) {
      return TranscriptionResultView(
        scrollController: _scrollController,
        viewingBatchIndex: _viewingBatchIndex,
        onViewingIndexChanged: (i) => setState(() => _viewingBatchIndex = i),
        isConnected: isConnected,
        audioPlayer: _audioPlayer,
      );
    }

    _audioPlayer.stop();

    return IdleTranscriptionView(
      selectedModel: _selectedModel,
      onModelChanged: (v) => setState(() => _selectedModel = v),
      language: _language,
      onLanguageChanged: (v) => setState(() => _language = v),
      enableGpu: _enableGpu,
      onGpuChanged: (v) => setState(() => _enableGpu = v),
      translateToLanguage: _translateToLanguage,
      onTranslateLanguageChanged: (v) =>
          setState(() => _translateToLanguage = v),
      downloadedModels: downloadedModels,
      isConnected: isConnected,
      onPickFiles: () => _pickFiles(replace: true),
      onAddMoreFiles: () => _pickFiles(replace: false),
      onStartTranscription: _startTranscription,
    );
  }
}
