import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../proto/scribe.pb.dart' as pb;
import '../theme.dart';

class TranscriptPanel extends StatefulWidget {
  final List<pb.Segment> segments;
  final Duration playbackPosition;
  final bool isPlaying;
  final ValueChanged<Duration>? onSeek;
  final bool isTranscribing;
  final ScrollController scrollController;

  const TranscriptPanel({
    super.key,
    required this.segments,
    required this.playbackPosition,
    required this.isPlaying,
    this.onSeek,
    this.isTranscribing = false,
    required this.scrollController,
  });

  @override
  State<TranscriptPanel> createState() => TranscriptPanelState();
}

class TranscriptPanelState extends State<TranscriptPanel> {
  int? _editingIndex;
  late TextEditingController _editController;
  late FocusNode _editFocusNode;
  final FocusNode _panelFocusNode = FocusNode();

  String _searchQuery = '';
  bool _searchVisible = false;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  int _searchMatchIndex = 0;
  List<int> _searchMatches = [];

  late Map<int, String> _editedTexts;

  int _lastAutoScrollSegment = -1;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editFocusNode = FocusNode();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _editedTexts = {};
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    _panelFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && widget.segments.isNotEmpty) {
      _autoScrollToCurrentSegment();
    }
  }

  int get _currentSegmentIndex {
    final posSeconds = widget.playbackPosition.inMilliseconds / 1000.0;
    for (var i = widget.segments.length - 1; i >= 0; i--) {
      if (posSeconds >= widget.segments[i].start) return i;
    }
    return -1;
  }

  void _autoScrollToCurrentSegment() {
    final idx = _currentSegmentIndex;
    if (idx < 0 || idx == _lastAutoScrollSegment) return;
    if (!widget.scrollController.hasClients) return;

    _lastAutoScrollSegment = idx;
    final estimatedOffset = idx * 52.0;
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    final targetOffset = estimatedOffset.clamp(0.0, maxScroll);

    final currentOffset = widget.scrollController.offset;
    final viewportHeight = widget.scrollController.position.viewportDimension;

    if (targetOffset < currentOffset || targetOffset > currentOffset + viewportHeight - 80) {
      widget.scrollController.animateTo(
        (targetOffset - viewportHeight / 3).clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _startEditing(int index) {
    final seg = widget.segments[index];
    final text = _editedTexts[seg.index] ?? seg.text;
    setState(() {
      _editingIndex = index;
      _editController.text = text;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
  }

  void _commitEdit(int index) {
    final seg = widget.segments[index];
    final newText = _editController.text.trim();
    if (newText.isNotEmpty && newText != seg.text) {
      setState(() {
        _editedTexts[seg.index] = newText;
      });
    }
    setState(() => _editingIndex = null);
  }

  void _cancelEdit() {
    setState(() => _editingIndex = null);
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (_searchVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      } else {
        _searchQuery = '';
        _searchController.clear();
        _searchMatches = [];
        _searchMatchIndex = 0;
      }
    });
  }

  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _searchMatches = [];
      _searchMatchIndex = 0;
      if (_searchQuery.isNotEmpty) {
        for (var i = 0; i < widget.segments.length; i++) {
          final text = _getSegmentText(i).toLowerCase();
          if (text.contains(_searchQuery)) {
            _searchMatches.add(i);
          }
        }
      }
    });
    if (_searchMatches.isNotEmpty) {
      _scrollToSearchMatch(0);
    }
  }

  void _nextSearchMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchMatchIndex = (_searchMatchIndex + 1) % _searchMatches.length;
    });
    _scrollToSearchMatch(_searchMatchIndex);
  }

  void _prevSearchMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchMatchIndex =
          (_searchMatchIndex - 1 + _searchMatches.length) % _searchMatches.length;
    });
    _scrollToSearchMatch(_searchMatchIndex);
  }

  void _scrollToSearchMatch(int matchIdx) {
    if (matchIdx >= _searchMatches.length) return;
    final segIdx = _searchMatches[matchIdx];
    final estimatedOffset = segIdx * 52.0;
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    widget.scrollController.animateTo(
      estimatedOffset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  String _getSegmentText(int listIndex) {
    final seg = widget.segments[listIndex];
    return _editedTexts[seg.index] ?? seg.text;
  }

  String getFullEditedTranscript() {
    final sorted = [...widget.segments]..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((s) => _editedTexts[s.index] ?? s.text).join(' ');
  }

  Map<int, String> get editedTexts => Map.unmodifiable(_editedTexts);

  List<pb.Segment> getSegmentsWithEdits() {
    return widget.segments.map((s) {
      if (_editedTexts.containsKey(s.index)) {
        final edited = pb.Segment()
          ..index = s.index
          ..start = s.start
          ..end = s.end
          ..text = _editedTexts[s.index]!;
        return edited;
      }
      return s;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIdx = _currentSegmentIndex;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _toggleSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchVisible) _toggleSearch();
          if (_editingIndex != null) _cancelEdit();
        },
      },
      child: Focus(
        focusNode: _panelFocusNode,
        child: Column(
          children: [
            if (_searchVisible) _buildSearchBar(theme),
            Expanded(
              child: widget.segments.isEmpty
                  ? _buildEmptyState(theme)
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
                      itemCount: widget.segments.length,
                      itemBuilder: (context, index) => _buildSegmentRow(
                        context,
                        index,
                        currentIdx,
                        theme,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _updateSearch,
              onSubmitted: (_) => _nextSearchMatch(),
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search transcript...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: false,
              ),
            ),
          ),
          if (_searchMatches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_searchMatchIndex + 1}/${_searchMatches.length}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              icon: Icon(Icons.keyboard_arrow_up_rounded, size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
              onPressed: _prevSearchMatch,
              padding: EdgeInsets.zero,
              tooltip: 'Previous match',
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
              onPressed: _nextSearchMatch,
              padding: EdgeInsets.zero,
              tooltip: 'Next match',
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              icon: Icon(Icons.close_rounded, size: 16,
                  color: theme.colorScheme.onSurfaceVariant),
              onPressed: _toggleSearch,
              padding: EdgeInsets.zero,
              tooltip: 'Close search',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    if (widget.isTranscribing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Processing audio...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Text(
        'No segments',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSegmentRow(
    BuildContext context,
    int index,
    int currentPlayingIdx,
    ThemeData theme,
  ) {
    final seg = widget.segments[index];
    final isCurrent = index == currentPlayingIdx;
    final isSearchMatch = _searchMatches.contains(index);
    final isActiveMatch = _searchMatches.isNotEmpty &&
        _searchMatchIndex < _searchMatches.length &&
        _searchMatches[_searchMatchIndex] == index;
    final isEditing = _editingIndex == index;
    final displayText = _getSegmentText(index);
    final hasEdit = _editedTexts.containsKey(seg.index);

    return Container(
      key: ValueKey(seg.index),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActiveMatch
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : isCurrent
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
                : isSearchMatch
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1)
                    : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border(
                left: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              widget.onSeek?.call(
                Duration(milliseconds: (seg.start * 1000).round()),
              );
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 80,
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _formatTime(seg.start),
                  style: ScribeTheme.monoStyle(
                    context,
                    fontSize: 11,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: isEditing
                ? _buildEditor(index, theme)
                : GestureDetector(
                    onDoubleTap: () => _startEditing(index),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: _buildSegmentText(
                        displayText,
                        isCurrent,
                        hasEdit,
                        theme,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentText(
    String text,
    bool isCurrent,
    bool hasEdit,
    ThemeData theme,
  ) {
    if (_searchQuery.isNotEmpty) {
      return _buildHighlightedText(text, isCurrent, hasEdit, theme);
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
              color: isCurrent
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
        if (hasEdit)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.edit_rounded,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }

  Widget _buildHighlightedText(
    String text,
    bool isCurrent,
    bool hasEdit,
    ThemeData theme,
  ) {
    final lowerText = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lowerText.indexOf(_searchQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + _searchQuery.length),
        style: TextStyle(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + _searchQuery.length;
    }

    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
          color: isCurrent
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurface.withValues(alpha: 0.85),
        ),
        children: spans,
      ),
    );
  }

  Widget _buildEditor(int index, ThemeData theme) {
    return TextField(
      controller: _editController,
      focusNode: _editFocusNode,
      maxLines: null,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.check_rounded, size: 16,
                  color: theme.colorScheme.primary),
              onPressed: () => _commitEdit(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Save',
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 16,
                  color: theme.colorScheme.onSurfaceVariant),
              onPressed: _cancelEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Cancel',
            ),
          ],
        ),
      ),
      onSubmitted: (_) => _commitEdit(index),
    );
  }

  String _formatTime(double seconds) {
    final h = (seconds ~/ 3600);
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = ((seconds % 60).truncate()).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}
