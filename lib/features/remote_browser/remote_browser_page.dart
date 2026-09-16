import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/file_type.dart';
import '../../core/file_view_mode.dart';
import '../../core/responsive.dart';
import '../../core/tokens.dart';
import '../../data/models/device_info.dart';
import '../../data/models/file_entry.dart';
import '../../providers/browser_provider.dart';
import '../../providers/services_provider.dart';
import '../../providers/settings_provider.dart';
import '../media_viewer/media_source.dart';
import '../shared/browser_scaffold.dart';
import '../shared/detail_panel.dart';
import '../shared/empty_state.dart';
import '../shared/error_view.dart';
import '../shared/file_grid_view.dart';
import '../shared/file_list_view.dart';
import '../shared/skeleton.dart';

/// 远程设备只读浏览页（复用 FileGridView，不提供增删改）。
class RemoteBrowserPage extends ConsumerStatefulWidget {
  const RemoteBrowserPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  ConsumerState<RemoteBrowserPage> createState() => _RemoteBrowserPageState();
}

class _RemoteBrowserPageState extends ConsumerState<RemoteBrowserPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  FileEntry? _selected;
  EntryType? _filter;
  bool _searching = false;
  bool _searchLoading = false;
  List<FileEntry>? _searchResults;
  SortField _sortField = SortField.time;
  bool _ascending = false;

  @override
  void initState() {
    super.initState();
    // 关键：remotePathProvider 是全局共享的，进入新设备时必须重置到根目录，
    // 否则会沿用上一台设备的残留路径（导致目录不存在 / 一直加载）。
    ref.read(remotePathProvider.notifier).set('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _url(FileEntry e) =>
      ref.read(remoteFileClientProvider).fileUrl(widget.device, e.path);

  String _thumbUrl(FileEntry e) =>
      ref.read(remoteFileClientProvider).thumbnailUrl(widget.device, e.path);

  void _onTap(FileEntry entry, bool isWide, List<FileEntry> allEntries) {
    if (entry.isFolder) {
      ref.read(remotePathProvider.notifier).set(entry.path);
      setState(() {
        _selected = null;
        _exitSearch();
      });
      return;
    }
    if (isWide) {
      setState(() => _selected = entry);
      return;
    }
    _openMedia(entry, allEntries);
  }

  /// 双击列表项：媒体跳过右侧预览、直接全屏沉浸式观看；文件夹退回单击行为。
  void _onDoubleTapEntry(
    FileEntry entry,
    bool isWide,
    List<FileEntry> allEntries,
  ) {
    if (entry.isFolder) {
      _onTap(entry, isWide, allEntries);
      return;
    }
    // 双击直接全屏前，先取消当前选中（停掉右侧内嵌播放器），避免双音源
    if (isWide) {
      setState(() => _selected = null);
    }
    _openMedia(entry, allEntries, fromSplit: isWide);
  }

  void _openMedia(
    FileEntry entry,
    List<FileEntry> allEntries, {
    bool fromSplit = false,
  }) {
    // 同类型媒体列表 + 当前索引，供左右滑动/切换
    final sameType = allEntries.where((e) => e.type == entry.type).toList();
    var index = sameType.indexWhere((e) => e.path == entry.path);
    if (index < 0) index = 0;
    final List<MediaSource> sources = sameType
        .map((e) => RemoteMediaSource(_url(e), title: e.name))
        .toList();
    switch (entry.type) {
      case EntryType.image:
        context.push(
          '/image',
          extra: (items: sources, index: index, fromSplit: fromSplit),
        );
      case EntryType.video:
        context.push(
          '/video',
          extra: (items: sources, index: index, fromSplit: fromSplit),
        );
      case EntryType.audio:
        _showSnack('暂不支持播放音频文件');
      case EntryType.folder:
      case EntryType.other:
        _showSnack('暂不支持预览该文件');
    }
  }

  /// 双栏详情面板触发全屏：用当前目录完整列表构造媒体源并 push 全屏路由，
  /// 让全屏页能左右切换同类型媒体（fromSplit=true，全屏按钮=返回双栏）。
  void _openFullscreen(FileEntry entry) {
    final path = ref.read(remotePathProvider);
    final key = RemoteBrowseKey(widget.device, path);
    final async = ref.read(remoteBrowserProvider(key));
    final entries = async.maybeWhen(
      data: (list) => list,
      orElse: () => [entry],
    );
    _openMedia(entry, entries, fromSplit: true);
  }

  /// 返回上一级目录。
  void _goUp() {
    final path = ref.read(remotePathProvider);
    final idx = path.lastIndexOf('/');
    final parent = idx == -1 ? '' : path.substring(0, idx);
    ref.read(remotePathProvider.notifier).set(parent);
    setState(() => _selected = null);
  }

  /// 统一返回处理：关闭搜索 → 取消选中 → 回上级目录 → 退出页面。
  void _handleBack() {
    if (_searching) {
      _toggleSearch();
    } else if (_selected != null) {
      setState(() => _selected = null);
    } else if (ref.read(remotePathProvider).isNotEmpty) {
      _goUp();
    } else {
      context.pop();
    }
  }

  // 搜索
  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _exitSearch();
    });
  }

  void _exitSearch() {
    _searchResults = null;
    _searchLoading = false;
    _searchController.clear();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _searchLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searchLoading = true);
    final client = ref.read(remoteFileClientProvider);
    final result = await client.search(widget.device, query);
    if (!mounted) return;
    result.fold(
      (list) => setState(() {
        _searchResults = list;
        _searchLoading = false;
      }),
      (err) => setState(() {
        _searchResults = const [];
        _searchLoading = false;
        _showSnack(err);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(remotePathProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = Responsive.useSplitLayout(context, constraints.maxWidth);
        final mode = ref.watch(settingsProvider.select((s) => s.viewMode));
        // 返回键/手势优先级：关闭搜索 → 取消选中 → 回上级目录；仅根目录才退出应用。
        // PopScope 拦截路径回退，go_router onExit 作为兜底（兼容不同 go_router 版本）。
        final canPop = !_searching && _selected == null && path.isEmpty;
        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBack();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.device.deviceName),
              leading: IconButton(
                icon: const Icon(LucideIcons.arrow_left),
                onPressed: _handleBack,
              ),
              actions: [
                IconButton(
                  icon: Icon(mode == FileViewMode.grid
                      ? LucideIcons.list
                      : LucideIcons.layout_grid),
                  tooltip: mode == FileViewMode.grid ? '列表视图' : '网格视图',
                  onPressed: () =>
                      ref.read(settingsProvider.notifier).toggleViewMode(),
                ),
                IconButton(
                  icon: Icon(_searching ? LucideIcons.x : LucideIcons.search),
                  onPressed: _toggleSearch,
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refresh_cw),
                  onPressed: () =>
                      ref.invalidate(remoteBrowserProvider),
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (_searching) _searchField(),
                  Row(
                    children: [
                      Expanded(child: _filterChips()),
                      _sortButton(),
                    ],
                  ),
                  _breadcrumb(path),
                  Expanded(
                    child: BrowserScaffold(
                      list: _buildList(isWide, path),
                      detail: DetailPanel(
                        entry: _selected,
                        resolver: _url,
                        isRemote: true,
                        onOpenFullscreen: _openFullscreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '搜索文件（名称）',
          prefixIcon: Icon(LucideIcons.search),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _filterChips() {
    final filters = <(EntryType?, String)>[
      (null, '全部'),
      (EntryType.image, '图片'),
      (EntryType.video, '视频'),
      (EntryType.audio, '音频'),
      (EntryType.folder, '文件夹'),
      (EntryType.other, '其他'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final (type, label) = filters[index];
          return ChoiceChip(
            label: Text(label),
            selected: _filter == type,
            onSelected: (_) => setState(() => _filter = type),
          );
        },
      ),
    );
  }

  Widget _breadcrumb(String path) {
    final palette = AppPalette.of(context);
    final all = <(String, String)>[(widget.device.deviceName, '')];
    var acc = '';
    for (final seg in path.split('/')) {
      if (seg.isEmpty) continue;
      acc = acc.isEmpty ? seg : '$acc/$seg';
      all.add((seg, acc));
    }
    // 深目录折叠：根 / … / 上一级 / 当前
    final items = all.length > 4
        ? [all.first, ('…', ''), all[all.length - 2], all.last]
        : all;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Icon(LucideIcons.chevron_right, size: 16, color: palette.muted),
        itemBuilder: (context, index) {
          final (label, full) = items[index];
          final isLast = index == items.length - 1;
          final isEllipsis = label == '…';
          final text = Text(
            label,
            style: TextStyle(
              color: isLast ? palette.text : palette.muted,
              fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          );
          if (isEllipsis) return Center(child: text);
          return InkWell(
            onTap: () {
              ref.read(remotePathProvider.notifier).set(full);
              setState(() => _selected = null);
            },
            child: Center(child: text),
          );
        },
      ),
    );
  }

  Widget _buildList(bool isWide, String path) {
    final mode = ref.watch(settingsProvider.select((s) => s.viewMode));
    final selectedPath = _selected?.path;
    if (_searching) {
      if (_searchLoading) {
        return mode == FileViewMode.list
            ? const SkeletonList()
            : const SkeletonGrid();
      }
      final results = _searchResults ?? const [];
      if (results.isEmpty) return _empty('未找到匹配文件');
      return _fileView(_sortEntries(results), isWide,
          selectedPath: selectedPath);
    }
    final key = RemoteBrowseKey(widget.device, path);
    final asyncEntries = ref.watch(remoteBrowserProvider(key));
    return asyncEntries.when(
      data: (entries) {
        final filtered = _applyFilterAndSort(entries);
        if (filtered.isEmpty) return _empty('此目录为空');
        return RefreshIndicator(
          onRefresh: () =>
              ref.refresh(remoteBrowserProvider(key).future).then((_) {}),
          child: _fileView(filtered, isWide,
              selectedPath: selectedPath, storageKey: 'remote:$path'),
        );
      },
      loading: () => mode == FileViewMode.list
          ? const SkeletonList()
          : const SkeletonGrid(),
      error: (e, _) => _errorView(e.toString()),
    );
  }

  Widget _fileView(
    List<FileEntry> entries,
    bool isWide, {
    String? selectedPath,
    String? storageKey,
  }) {
    final mode = ref.watch(settingsProvider.select((s) => s.viewMode));
    if (mode == FileViewMode.list) {
      return FileListView(
        entries: entries,
        fileResolver: _url,
        thumbnailResolver: _thumbUrl,
        isRemote: true,
        selectedPath: selectedPath,
        storageKey: storageKey,
        onTap: (e) => _onTap(e, isWide, entries),
        onDoubleTap: (e) => _onDoubleTapEntry(e, isWide, entries),
      );
    }
    return FileGridView(
      entries: entries,
      fileResolver: _url,
      thumbnailResolver: _thumbUrl,
      isRemote: true,
      selectedPath: selectedPath,
      storageKey: storageKey,
      onTap: (e) => _onTap(e, isWide, entries),
      onDoubleTap: (e) => _onDoubleTapEntry(e, isWide, entries),
    );
  }

  List<FileEntry> _applyFilter(List<FileEntry> entries) {
    final f = _filter;
    if (f == null) return entries;
    return entries.where((e) => e.type == f).toList();
  }

  List<FileEntry> _applyFilterAndSort(List<FileEntry> entries) =>
      _sortEntries(_applyFilter(entries));

  List<FileEntry> _sortEntries(List<FileEntry> entries) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      final cmp = switch (_sortField) {
        SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortField.size => a.sizeBytes.compareTo(b.sizeBytes),
        SortField.time => a.modifiedAt.compareTo(b.modifiedAt),
      };
      return _ascending ? cmp : -cmp;
    });
    return sorted;
  }

  Widget _sortButton() {
    final palette = AppPalette.of(context);
    final label = switch (_sortField) {
      SortField.name => '名称',
      SortField.size => '大小',
      SortField.time => '时间',
    };
    return PopupMenuButton<(SortField, bool)>(
      tooltip: '排序',
      onSelected: (opt) => setState(() {
        _sortField = opt.$1;
        _ascending = opt.$2;
      }),
      itemBuilder: (context) {
        const options = <(SortField, bool, String)>[
          (SortField.name, true, '名称（升序）'),
          (SortField.name, false, '名称（降序）'),
          (SortField.size, false, '大小（从大到小）'),
          (SortField.size, true, '大小（从小到大）'),
          (SortField.time, false, '修改时间（最新）'),
          (SortField.time, true, '修改时间（最早）'),
        ];
        return [
          for (final (field, asc, text) in options)
            PopupMenuItem(
              value: (field, asc),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.check,
                    size: 18,
                    color: _sortField == field && _ascending == asc
                        ? palette.brand
                        : Colors.transparent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(text),
                ],
              ),
            ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrow_up_down, size: 20, color: palette.text),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: TextStyle(color: palette.text, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _empty(String message) =>
      EmptyState(icon: LucideIcons.cloud_off, title: message);

  Widget _errorView(String message) {
    return ErrorView(
      message: message,
      onRetry: () => ref.invalidate(remoteBrowserProvider),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
