import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../proto/scribe.pb.dart' as pb;
import '../theme.dart';

// Single-space marker keeps deletions distinguishable from "no edit" in storage.
const String _deletedTextMarker = ' ';

class TranscriptPanel extends StatefulWidget {
  final List<pb.Segment> segments;
  final Duration playbackPosition;
  final bool isPlaying;
  final ValueChanged<Duration>? onSeek;
  final bool isTranscribing;
  final ScrollController scrollController;
  final Map<int, String> initialEdits;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final String? selectionScopeId;

  const TranscriptPanel({
    super.key,
    required this.segments,
    required this.playbackPosition,
    required this.isPlaying,
    this.onSeek,
    this.isTranscribing = false,
    required this.scrollController,
    this.initialEdits = const {},
    this.onSelectionChanged,
    this.selectionScopeId,
  });

  @override
  State<TranscriptPanel> createState() => TranscriptPanelState();
}

class TranscriptPanelState extends State<TranscriptPanel> {
  int? _editingIndex;
  Set<int> _selectedSegmentIndices = <int>{};
  int? _selectionAnchorListIndex;
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
    if (widget.initialEdits.isNotEmpty) {
      _editedTexts = Map.from(widget.initialEdits);
    }
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
    // Restore edits when loading a new job with saved edits
    if (widget.initialEdits != oldWidget.initialEdits &&
        widget.initialEdits.isNotEmpty) {
      _editedTexts = Map.from(widget.initialEdits);
    }
    var selectionChanged = false;
    if (widget.selectionScopeId != oldWidget.selectionScopeId &&
        _selectedSegmentIndices.isNotEmpty) {
      _selectedSegmentIndices = <int>{};
      _selectionAnchorListIndex = null;
      selectionChanged = true;
    }

    if (_selectedSegmentIndices.isNotEmpty) {
      final visibleSegmentIndices = widget.segments.map((s) => s.index).toSet();
      final pruned = _selectedSegmentIndices
          .where((idx) => visibleSegmentIndices.contains(idx))
          .toSet();
      if (pruned.length != _selectedSegmentIndices.length) {
        _selectedSegmentIndices = pruned;
        if (_selectedSegmentIndices.isEmpty) {
          _selectionAnchorListIndex = null;
        }
        selectionChanged = true;
      }
    }

    if (selectionChanged) {
      _emitSelectionChanged();
    }
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

    if (targetOffset < currentOffset ||
        targetOffset > currentOffset + viewportHeight - 80) {
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
      _selectedSegmentIndices = {seg.index};
      _selectionAnchorListIndex = index;
      _editingIndex = index;
      _editController.text = text;
    });
    _emitSelectionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
  }

  bool get _isRangeSelectionPressed {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
  }

  bool get _isToggleSelectionPressed {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
  }

  void _emitSelectionChanged() {
    widget.onSelectionChanged?.call(Set<int>.from(_selectedSegmentIndices));
  }

  void _selectSegment(int index) {
    final seg = widget.segments[index];
    final clickedSegmentIndex = seg.index;
    final toggleSelection = _isToggleSelectionPressed;
    final rangeSelection = _isRangeSelectionPressed;
    Set<int> nextSelection;

    if (rangeSelection && _selectionAnchorListIndex != null) {
      final start = math.min(_selectionAnchorListIndex!, index);
      final end = math.max(_selectionAnchorListIndex!, index);
      final range = {
        for (var i = start; i <= end; i++) widget.segments[i].index,
      };
      if (toggleSelection) {
        nextSelection = {..._selectedSegmentIndices, ...range};
      } else {
        nextSelection = range;
      }
    } else if (toggleSelection) {
      nextSelection = {..._selectedSegmentIndices};
      if (!nextSelection.add(clickedSegmentIndex)) {
        nextSelection.remove(clickedSegmentIndex);
      }
      _selectionAnchorListIndex = index;
    } else {
      nextSelection = {clickedSegmentIndex};
      _selectionAnchorListIndex = index;
    }

    if (setEquals(nextSelection, _selectedSegmentIndices)) return;
    setState(() {
      _selectedSegmentIndices = nextSelection;
      if (_selectedSegmentIndices.isEmpty) {
        _selectionAnchorListIndex = null;
      }
    });
    _emitSelectionChanged();
  }

  void _commitEdit(int index) {
    final seg = widget.segments[index];
    final newText = _editController.text.trim();
    setState(() {
      if (newText == seg.text) {
        _editedTexts.remove(seg.index);
      } else {
        _editedTexts[seg.index] = newText.isEmpty
            ? _deletedTextMarker
            : newText;
      }
      _editingIndex = null;
    });
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
          (_searchMatchIndex - 1 + _searchMatches.length) %
          _searchMatches.length;
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
    if (_editedTexts.containsKey(seg.index)) {
      return _editedTexts[seg.index] ?? '';
    }
    return seg.text;
  }

  bool _isDeletedText(String text) => text.trim().isEmpty;

  void deleteSegments(Iterable<int> segmentIndices) {
    final uniqueIndices = segmentIndices.toSet();
    if (uniqueIndices.isEmpty) return;
    setState(() {
      for (final segmentIndex in uniqueIndices) {
        _editedTexts[segmentIndex] = _deletedTextMarker;
      }
    });
  }

  void deleteSelectedSegments() {
    deleteSegments(_selectedSegmentIndices);
  }

  String getFullEditedTranscript() {
    final sorted = [...widget.segments]
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted
        .map(
          (s) => _editedTexts.containsKey(s.index)
              ? _editedTexts[s.index]!
              : s.text,
        )
        .where((text) => !_isDeletedText(text))
        .join(' ');
  }

  Map<int, String> get editedTexts => Map.unmodifiable(_editedTexts);
  Set<int> get selectedSegmentIndices =>
      Set.unmodifiable(_selectedSegmentIndices);

  bool get hasEdits => _editedTexts.isNotEmpty;

  List<pb.Segment> getSegmentsWithEdits() {
    final withEdits = <pb.Segment>[];
    for (final s in widget.segments) {
      if (!_editedTexts.containsKey(s.index)) {
        withEdits.add(s);
        continue;
      }
      final editedText = _editedTexts[s.index] ?? '';
      if (_isDeletedText(editedText)) {
        continue;
      }
      if (editedText != s.text) {
        final edited = pb.Segment()
          ..index = s.index
          ..start = s.start
          ..end = s.end
          ..text = editedText;
        withEdits.add(edited);
      } else {
        withEdits.add(s);
      }
    }
    return withEdits;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIdx = _currentSegmentIndex;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _toggleSearch,
        const SingleActivator(LogicalKeyboardKey.delete):
            deleteSelectedSegments,
        const SingleActivator(LogicalKeyboardKey.backspace):
            deleteSelectedSegments,
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
                  : Scrollbar(
                      thumbVisibility: true,
                      controller: widget.scrollController,
                      child: ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
                        itemCount: widget.segments.length,
                        itemBuilder: (context, index) =>
                            _buildSegmentRow(context, index, currentIdx, theme),
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
              icon: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: _prevSearchMatch,
              padding: EdgeInsets.zero,
              tooltip: 'Previous match',
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    final isActiveMatch =
        _searchMatches.isNotEmpty &&
        _searchMatchIndex < _searchMatches.length &&
        _searchMatches[_searchMatchIndex] == index;
    final isEditing = _editingIndex == index;
    final isSelected = _selectedSegmentIndices.contains(seg.index);
    final displayText = _getSegmentText(index);
    final isDeleted = _isDeletedText(displayText);
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
            : isSelected
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.2)
            : isSearchMatch
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: (isCurrent || isSelected)
            ? Border(
                left: BorderSide(
                  color: isCurrent
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
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
              _selectSegment(index);
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
                    onTap: () => _selectSegment(index),
                    onDoubleTap: () => _startEditing(index),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: _buildSegmentText(
                        displayText,
                        isCurrent,
                        hasEdit,
                        isDeleted,
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
    bool isDeleted,
    ThemeData theme,
  ) {
    if (isDeleted) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '[Deleted]',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(
            Icons.delete_outline_rounded,
            size: 14,
            color: theme.colorScheme.error.withValues(alpha: 0.7),
          ),
        ],
      );
    }

    if (_searchQuery.isNotEmpty) {
      return _buildHighlightedText(text, isCurrent, hasEdit, isDeleted, theme);
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
    bool isDeleted,
    ThemeData theme,
  ) {
    if (isDeleted) {
      return _buildSegmentText(text, isCurrent, hasEdit, isDeleted, theme);
    }

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
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + _searchQuery.length),
          style: TextStyle(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
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
              icon: Icon(
                Icons.check_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              onPressed: () => _commitEdit(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Save',
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
