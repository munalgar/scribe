import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../proto/scribe.pb.dart' as pb;
import '../theme.dart';

class _SearchMatch {
  final int segmentIndex;
  final int charIndex;

  const _SearchMatch({required this.segmentIndex, required this.charIndex});
}

class TranscriptPanel extends StatefulWidget {
  final List<pb.Segment> segments;
  final Duration playbackPosition;
  final bool isPlaying;
  final ValueChanged<Duration>? onSeek;
  final bool isTranscribing;
  final ScrollController scrollController;
  final Map<int, String> initialEdits;

  const TranscriptPanel({
    super.key,
    required this.segments,
    required this.playbackPosition,
    required this.isPlaying,
    this.onSeek,
    this.isTranscribing = false,
    required this.scrollController,
    this.initialEdits = const {},
  });

  @override
  State<TranscriptPanel> createState() => TranscriptPanelState();
}

class TranscriptPanelState extends State<TranscriptPanel> {
  int? _editingIndex;
  int? _manualSelectedIndex;
  late TextEditingController _editController;
  late FocusNode _editFocusNode;
  final FocusNode _panelFocusNode = FocusNode();
  final Map<int, GlobalKey> _segmentKeys = {};

  String _searchQuery = '';
  bool _searchVisible = false;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  int _searchMatchIndex = 0;
  List<_SearchMatch> _searchMatchEntries = [];
  Set<int> _searchMatchedSegmentIndices = {};

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
    final activeSegmentIds = widget.segments.map((s) => s.index).toSet();
    _segmentKeys.removeWhere(
      (segmentId, _) => !activeSegmentIds.contains(segmentId),
    );
    // Restore edits when loading a new job with saved edits
    if (widget.initialEdits != oldWidget.initialEdits &&
        widget.initialEdits.isNotEmpty) {
      _editedTexts = Map.from(widget.initialEdits);
    }
    if (_manualSelectedIndex != null &&
        (_manualSelectedIndex! < 0 ||
            _manualSelectedIndex! >= widget.segments.length)) {
      _manualSelectedIndex = null;
    }
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _manualSelectedIndex = null;
    }
    if (widget.isPlaying && widget.segments.isNotEmpty) {
      _autoScrollToCurrentSegment();
    }
  }

  int get _currentSegmentIndex {
    final posSeconds =
        widget.playbackPosition.inMicroseconds / Duration.microsecondsPerSecond;
    if (widget.segments.isEmpty) return -1;

    for (var i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i];
      final nextStart = i < widget.segments.length - 1
          ? widget.segments[i + 1].start
          : double.infinity;
      final end = seg.end > seg.start ? seg.end : nextStart;
      if (posSeconds >= seg.start && posSeconds < end) return i;
    }

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
    if (_segmentIsComfortablyVisible(idx)) return;
    _scrollToSegmentIndex(idx);
  }

  void _startEditing(int index) {
    final seg = widget.segments[index];
    final text = _editedTexts[seg.index] ?? seg.text;
    setState(() {
      _editingIndex = index;
      _manualSelectedIndex = index;
      _editController.text = text;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
  }

  void _seekToSegment(int index) {
    if (index < 0 || index >= widget.segments.length) return;
    final seg = widget.segments[index];
    final targetMicros = (seg.start * Duration.microsecondsPerSecond)
        .round()
        .clamp(0, 1 << 62);
    setState(() => _manualSelectedIndex = index);
    widget.onSeek?.call(Duration(microseconds: targetMicros));
    _focusPanel();
  }

  void _focusSegment(int index) {
    if (index < 0 || index >= widget.segments.length) return;
    if (_manualSelectedIndex == index) {
      _focusPanel();
      return;
    }
    setState(() => _manualSelectedIndex = index);
    _focusPanel();
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

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _focusPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _panelFocusNode.requestFocus();
    });
  }

  void openSearch() {
    if (_searchVisible) {
      _focusSearchField();
      return;
    }
    setState(() {
      _searchVisible = true;
    });
    _focusSearchField();
  }

  void _closeSearch() {
    if (!_searchVisible) return;
    _searchFocusNode.unfocus();
    setState(() {
      _searchVisible = false;
      _searchQuery = '';
      _searchController.clear();
      _searchMatchEntries = [];
      _searchMatchedSegmentIndices = {};
      _searchMatchIndex = 0;
    });
    _focusPanel();
  }

  void _toggleSearch() {
    if (_searchVisible) {
      _closeSearch();
      return;
    }
    openSearch();
  }

  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _searchMatchEntries = [];
      _searchMatchedSegmentIndices = {};
      _searchMatchIndex = 0;
      if (_searchQuery.isNotEmpty) {
        for (var i = 0; i < widget.segments.length; i++) {
          final lowerText = _getSegmentText(i).toLowerCase();
          var from = 0;
          while (true) {
            final idx = lowerText.indexOf(_searchQuery, from);
            if (idx == -1) break;
            _searchMatchEntries.add(
              _SearchMatch(segmentIndex: i, charIndex: idx),
            );
            _searchMatchedSegmentIndices.add(i);
            from = idx + _searchQuery.length;
          }
        }
      }
    });
    if (_searchMatchEntries.isNotEmpty) {
      _scrollToSearchMatch(0);
    }
  }

  void _nextSearchMatch() {
    if (_searchMatchEntries.isEmpty) return;
    setState(() {
      _searchMatchIndex = (_searchMatchIndex + 1) % _searchMatchEntries.length;
    });
    _scrollToSearchMatch(_searchMatchIndex);
  }

  void _prevSearchMatch() {
    if (_searchMatchEntries.isEmpty) return;
    setState(() {
      _searchMatchIndex =
          (_searchMatchIndex - 1 + _searchMatchEntries.length) %
          _searchMatchEntries.length;
    });
    _scrollToSearchMatch(_searchMatchIndex);
  }

  void _scrollToSearchMatch(int matchIdx) {
    if (matchIdx >= _searchMatchEntries.length) return;
    final match = _searchMatchEntries[matchIdx];
    _scrollToSegmentIndex(match.segmentIndex, matchCharIndex: match.charIndex);
  }

  void _scrollToSegmentIndex(int segmentIndex, {int? matchCharIndex}) {
    if (segmentIndex < 0 || segmentIndex >= widget.segments.length) return;
    if (!widget.scrollController.hasClients) return;
    final rowKey = _segmentKeyForListIndex(segmentIndex);
    if (_animateSegmentKeyToViewportTarget(
      rowKey,
      segmentIndex: segmentIndex,
      matchCharIndex: matchCharIndex,
    )) {
      return;
    }

    // Fallback if the row hasn't been built yet; then refine when it appears.
    final estimatedOffset = segmentIndex * 52.0;
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    final viewportHeight = widget.scrollController.position.viewportDimension;
    final centeredOffset = (estimatedOffset - viewportHeight / 2).clamp(
      0.0,
      maxScroll,
    );
    widget.scrollController
        .animateTo(
          centeredOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (!mounted || !widget.scrollController.hasClients) return;
          _animateSegmentKeyToViewportTarget(
            rowKey,
            segmentIndex: segmentIndex,
            matchCharIndex: matchCharIndex,
            duration: const Duration(milliseconds: 130),
          );
        });
  }

  GlobalKey _segmentKeyForListIndex(int listIndex) {
    final segmentId = widget.segments[listIndex].index;
    return _segmentKeys.putIfAbsent(segmentId, () => GlobalKey());
  }

  bool _animateSegmentKeyToViewportTarget(
    GlobalKey rowKey, {
    required int segmentIndex,
    int? matchCharIndex,
    Duration duration = const Duration(milliseconds: 220),
  }) {
    final rowContext = rowKey.currentContext;
    if (rowContext == null) return false;
    if (matchCharIndex != null) {
      final position = widget.scrollController.position;
      final rowRenderObject = rowContext.findRenderObject();
      final viewportContext = position.context.notificationContext;
      final viewportRenderObject = viewportContext?.findRenderObject();

      if (rowRenderObject is RenderBox &&
          viewportRenderObject is RenderBox &&
          rowRenderObject.attached &&
          viewportRenderObject.attached) {
        final rowTopLeft = rowRenderObject.localToGlobal(
          Offset.zero,
          ancestor: viewportRenderObject,
        );
        final rowTop = rowTopLeft.dy;
        final rowHeight = rowRenderObject.size.height;
        final viewportHeight = viewportRenderObject.size.height;
        final rowTextLength = _getSegmentText(segmentIndex).length;
        final boundedLength = rowTextLength <= 0 ? 1 : rowTextLength;
        final targetRatio =
            ((matchCharIndex + (_searchQuery.length / 2)) / boundedLength)
                .clamp(0.0, 1.0);
        final targetY = rowTop + rowHeight * targetRatio;

        const topInset = 56.0;
        const bottomInset = 40.0;
        final preferredCenter = viewportHeight * 0.58;
        final minCenter = topInset;
        final maxCenter = viewportHeight - bottomInset;
        final desiredCenter = preferredCenter.clamp(
          minCenter,
          maxCenter > minCenter ? maxCenter : minCenter,
        );
        final delta = targetY - desiredCenter;
        final targetOffset = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        widget.scrollController.animateTo(
          targetOffset.toDouble(),
          duration: duration,
          curve: Curves.easeOut,
        );
        return true;
      }
    }

    Scrollable.ensureVisible(
      rowContext,
      alignment: 0.5,
      duration: duration,
      curve: Curves.easeOut,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    return true;
  }

  bool _segmentIsComfortablyVisible(int segmentIndex) {
    final rowContext = _segmentKeyForListIndex(segmentIndex).currentContext;
    if (rowContext == null) return false;

    final rowRenderObject = rowContext.findRenderObject();
    final viewportContext =
        widget.scrollController.position.context.notificationContext;
    final viewportRenderObject = viewportContext?.findRenderObject();

    if (rowRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !rowRenderObject.attached ||
        !viewportRenderObject.attached) {
      return false;
    }

    final rowTopLeft = rowRenderObject.localToGlobal(
      Offset.zero,
      ancestor: viewportRenderObject,
    );
    final rowTop = rowTopLeft.dy;
    final rowBottom = rowTop + rowRenderObject.size.height;
    final viewportHeight = viewportRenderObject.size.height;
    const margin = 40.0;
    return rowTop >= margin && rowBottom <= viewportHeight - margin;
  }

  void _moveToSegment(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= widget.segments.length) return;

    final wasEditing = _editingIndex != null;
    final editingIndex = _editingIndex;
    if (wasEditing && editingIndex != null) {
      _commitEdit(editingIndex);
    }

    _seekToSegment(targetIndex);
    _scrollToSegmentIndex(targetIndex);

    if (wasEditing) {
      _startEditing(targetIndex);
    }
  }

  void goToNextLine() {
    if (widget.segments.isEmpty) return;
    final fromIndex =
        _editingIndex ??
        (!widget.isPlaying ? _manualSelectedIndex : null) ??
        (_currentSegmentIndex >= 0 ? _currentSegmentIndex : -1);
    final targetIndex = (fromIndex + 1).clamp(0, widget.segments.length - 1);
    _moveToSegment(targetIndex);
  }

  void goToPreviousLine() {
    if (widget.segments.isEmpty) return;
    final fromIndex =
        _editingIndex ??
        (!widget.isPlaying ? _manualSelectedIndex : null) ??
        _currentSegmentIndex;
    final safeFrom = fromIndex >= 0 ? fromIndex : 0;
    final targetIndex = (safeFrom - 1).clamp(0, widget.segments.length - 1);
    _moveToSegment(targetIndex);
  }

  String _getSegmentText(int listIndex) {
    final seg = widget.segments[listIndex];
    return _editedTexts[seg.index] ?? seg.text;
  }

  String getFullEditedTranscript() {
    final sorted = [...widget.segments]
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((s) => _editedTexts[s.index] ?? s.text).join(' ');
  }

  Map<int, String> get editedTexts => Map.unmodifiable(_editedTexts);

  bool get hasEdits => _editedTexts.isNotEmpty;

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
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final playbackIdx = _currentSegmentIndex;
    final currentIdx = widget.isPlaying
        ? playbackIdx
        : (_manualSelectedIndex ?? playbackIdx);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: isMacOS,
          control: !isMacOS,
        ): openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchVisible) _closeSearch();
          if (_editingIndex != null) _cancelEdit();
        },
      },
      child: Focus(
        focusNode: _panelFocusNode,
        autofocus: true,
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
          if (_searchMatchEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_searchMatchIndex + 1}/${_searchMatchEntries.length}',
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
    final isSearchMatch = _searchMatchedSegmentIndices.contains(index);
    final isActiveMatch =
        _searchMatchEntries.isNotEmpty &&
        _searchMatchIndex < _searchMatchEntries.length &&
        _searchMatchEntries[_searchMatchIndex].segmentIndex == index;
    final activeMatchCharIndex = isActiveMatch
        ? _searchMatchEntries[_searchMatchIndex].charIndex
        : null;
    final isEditing = _editingIndex == index;
    final displayText = _getSegmentText(index);
    final hasEdit = _editedTexts.containsKey(seg.index);

    return MouseRegion(
      cursor: isEditing ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: isEditing ? null : () => _focusSegment(index),
        onDoubleTap: isEditing
            ? null
            : () {
                _seekToSegment(index);
                _startEditing(index);
              },
        child: Container(
          key: _segmentKeyForListIndex(index),
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
                  _seekToSegment(index);
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
                    : _buildSegmentText(
                        displayText,
                        isCurrent,
                        hasEdit,
                        theme,
                        activeMatchCharIndex: activeMatchCharIndex,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentText(
    String text,
    bool isCurrent,
    bool hasEdit,
    ThemeData theme, {
    int? activeMatchCharIndex,
  }) {
    if (_searchQuery.isNotEmpty) {
      return _buildHighlightedText(
        text,
        isCurrent,
        hasEdit,
        theme,
        activeMatchCharIndex: activeMatchCharIndex,
      );
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
    ThemeData theme, {
    int? activeMatchCharIndex,
  }) {
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
            backgroundColor: idx == activeMatchCharIndex
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : theme.colorScheme.primary.withValues(alpha: 0.3),
            fontWeight: idx == activeMatchCharIndex
                ? FontWeight.w700
                : FontWeight.w600,
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
