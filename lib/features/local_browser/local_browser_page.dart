import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/file_type.dart';
import '../../core/file_view_mode.dart';
import '../../core/prompts.dart';
import '../../core/result.dart';
import '../../core/responsive.dart';
import '../../core/tokens.dart';
import '../../data/models/file_entry.dart';
import '../../permissions/storage_permission.dart';
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

class LocalBrowserPage extends ConsumerStatefulWidget {
  const LocalBrowserPage({super.key});

  @override
  ConsumerState<LocalBrowserPage> createState() => _LocalBrowserPageState();
}

class _LocalBrowserPageState extends ConsumerState<LocalBrowserPage>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  bool _searchLoading = false;
  List<FileEntry>? _searchResults;
  EntryType? _filter;
  SortField _sortField = SortField.time;
  bool _ascending = false;
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统「所有文件访问」设置页返回后复查权限
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final granted = await StoragePermission.isGranted();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _requestPermission() async {
    final granted = await StoragePermission.ensure();
    if (mounted) setState(() => _granted = granted);
  }

  // ---- 浏览与选中 ----

  void _onTapEntry(FileEntry entry, bool isWide, List<FileEntry> allEntries) {
    if (entry.isFolder) {
      ref.read(localPathProvider.notifier).set(entry.path);
      ref.read(selectedEntryProvider.notifier).select(null);
      _exitSearch();
      return;
    }
    if (isWide) {
      ref.read(selectedEntryProvider.notifier).select(entry);
      return;
    }
    _openMedia(entry, allEntries);
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
        .map((e) => LocalMediaSource(_absolute(e.path), title: e.name))
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
        context.push('/audio', extra: sources[index]);
      case EntryType.folder:
      case EntryType.other:
        _showSnack('暂不支持预览该文件');
    }
  }

  /// 双栏详情面板触发全屏：用当前目录完整列表构造媒体源并 push 全屏路由，
  /// 让全屏页能左右切换同类型媒体（fromSplit=true，全屏按钮=返回双栏）。
  void _openFullscreen(FileEntry entry) {
    final path = ref.read(localPathProvider);
    final async = ref.read(localBrowserProvider(path));
    final entries = async.maybeWhen(
      data: (list) => list,
      orElse: () => [entry],
    );
    _openMedia(entry, entries, fromSplit: true);
  }

  String _absolute(String relPath) {
    final service = ref.read(localFileServiceProvider);
    return service.absolutePath(relPath);
  }

  void _goUp() {
    final path = ref.read(localPathProvider);
    if (path.isEmpty) return;
    final idx = path.lastIndexOf('/');
    final parent = idx == -1 ? '' : path.substring(0, idx);
    ref.read(localPathProvider.notifier).set(parent);
    ref.read(selectedEntryProvider.notifier).select(null);
  }

  // ---- 搜索 ----

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
    final service = ref.read(localFileServiceProvider);
    final result = await service.search(query);
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

  // ---- 文件增删改 ----

  Future<void> _createFolder() async {
    final name = await _promptText(title: '新建文件夹', hint: '文件夹名称');
    if (name == null || name.trim().isEmpty) return;
    final service = ref.read(localFileServiceProvider);
    final path = ref.read(localPathProvider);
    final result = await service.createFolder(path, name);
    if (!mounted) return;
    _handleOpResult(result, '创建成功');
  }

  Future<void> _rename(FileEntry entry) async {
    final name = await _promptText(title: '重命名', hint: '新名称', initial: entry.name);
    if (name == null || name.trim().isEmpty) return;
    final service = ref.read(localFileServiceProvider);
    final result = await service.rename(entry.path, name);
    if (!mounted) return;
    _handleOpResult(result, '重命名成功');
  }

  Future<void> _delete(FileEntry entry) async {
    final ok = await _confirm('删除「${entry.name}」', '此操作不可撤销');
    if (ok != true) return;
    final service = ref.read(localFileServiceProvider);
    final result = await service.delete(entry.path);
    if (!mounted) return;
    _handleOpResult(result, '已删除');
  }

  void _handleOpResult(Result<void> result, String successMsg) {
    result.fold(
      (_) {
        _showSnack(successMsg);
        ref.invalidate(localBrowserProvider);
      },
      (err) => _showSnack(err),
    );
  }

  void _showEntryActions(FileEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(entry.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.formattedSize),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(LucideIcons.file_pen),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _rename(entry);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.trash, color: palette.red),
                title: Text('删除', style: TextStyle(color: palette.red)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _delete(entry);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    if (_granted == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_granted == false) {
      return _PermissionGate(onRequest: _requestPermission);
    }
    final path = ref.watch(localPathProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = Responsive.useSplitLayout(context, constraints.maxWidth);
        final selected = ref.watch(selectedEntryProvider);
        // 返回键/手势优先级：关闭搜索 → 取消选中 → 回上级目录；仅根目录才退出应用。
        // PopScope 拦截路径回退，go_router onExit 作为兜底（兼容不同 go_router 版本）。
        final canPop = !_searching && selected == null && path.isEmpty;
        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_searching) {
              _toggleSearch();
            } else if (selected != null) {
              ref.read(selectedEntryProvider.notifier).select(null);
            } else {
              _goUp();
            }
          },
          child: Scaffold(
            body: SafeArea(
            child: Column(
              children: [
                _header(path),
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
                    list: _buildList(isWide),
                    detail: DetailPanel(
                      entry: selected,
                      resolver: (e) => _absolute(e.path),
                      isRemote: false,
                      onOpenFullscreen: _openFullscreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: _searching
              ? null
              : FloatingActionButton(
                  onPressed: _createFolder,
                  child: const Icon(LucideIcons.folder_plus),
                ),
          ),
        );
      },
    );
  }

  Widget _header(String path) {
    final palette = AppPalette.of(context);
    final mode = ref.watch(settingsProvider.select((s) => s.viewMode));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.md, 0),
      child: Row(
        children: [
          if (path.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.arrow_left),
              onPressed: _goUp,
            )
          else
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Icon(LucideIcons.folder, color: palette.brand),
            ),
          Expanded(
            child: Text(
              _title(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title.copyWith(color: palette.text),
            ),
          ),
          IconButton(
            icon: Icon(
                mode == FileViewMode.grid ? LucideIcons.list : LucideIcons.layout_grid),
            tooltip: mode == FileViewMode.grid ? '列表视图' : '网格视图',
            onPressed: () => ref.read(settingsProvider.notifier).toggleViewMode(),
          ),
          IconButton(
            icon: Icon(_searching ? LucideIcons.x : LucideIcons.search),
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: const Icon(LucideIcons.refresh_cw),
            onPressed: () => ref.invalidate(localBrowserProvider),
          ),
        ],
      ),
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
          final selected = _filter == type;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => setState(() => _filter = type),
          );
        },
      ),
    );
  }

  Widget _breadcrumb(String path) {
    final palette = AppPalette.of(context);
    final all = <(String, String)>[(AppConstants.sharedRootLabel, '')];
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
              ref.read(localPathProvider.notifier).set(full);
              ref.read(selectedEntryProvider.notifier).select(null);
            },
            child: Center(child: text),
          );
        },
      ),
    );
  }

  Widget _buildList(bool isWide) {
    final mode = ref.watch(settingsProvider.select((s) => s.viewMode));
    final selectedPath =
        ref.watch(selectedEntryProvider.select((e) => e?.path));
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
    final path = ref.watch(localPathProvider);
    final asyncEntries = ref.watch(localBrowserProvider(path));
    return asyncEntries.when(
      data: (entries) {
        final filtered = _applyFilterAndSort(entries);
        if (filtered.isEmpty) return _empty('此目录为空');
        return RefreshIndicator(
          onRefresh: () =>
              ref.refresh(localBrowserProvider(path).future).then((_) {}),
          child: _fileView(filtered, isWide,
              selectedPath: selectedPath, onLongPress: _showEntryActions),
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
    ValueChanged<FileEntry>? onLongPress,
  }) {
    final mode = ref.watch(settingsProvider.select((s) => s.viewMode));
    if (mode == FileViewMode.list) {
      return FileListView(
        entries: entries,
        fileResolver: _absoluteOf,
        isRemote: false,
        selectedPath: selectedPath,
        onTap: (e) => _onTapEntry(e, isWide, entries),
        onLongPress: onLongPress,
      );
    }
    return FileGridView(
      entries: entries,
      fileResolver: _absoluteOf,
      isRemote: false,
      selectedPath: selectedPath,
      onTap: (e) => _onTapEntry(e, isWide, entries),
      onLongPress: onLongPress,
    );
  }

  String _absoluteOf(FileEntry e) => _absolute(e.path);

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
      // 文件夹始终排在文件前面
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
      EmptyState(icon: LucideIcons.inbox, title: message);

  Widget _errorView(String message) {
    return ErrorView(
      message: message,
      onRetry: () => ref.invalidate(localBrowserProvider),
    );
  }

  String _title(String path) {
    if (path.isEmpty) return AppConstants.sharedRootLabel;
    final idx = path.lastIndexOf('/');
    return idx == -1 ? path : path.substring(idx + 1);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- 对话框 ----

  Future<String?> _promptText({
    required String title,
    required String hint,
    String? initial,
  }) {
    return showTextPrompt(
      context,
      title: title,
      hint: hint,
      initial: initial,
    );
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.folder_x,
      title: '需要存储权限才能浏览本地文件',
      subtitle: 'Faner 需要「所有文件访问」权限，才能读取和共享本机任意文件。\n'
          '点击下方按钮后，请在系统设置中开启“所有文件访问”，再返回本页。',
      action: FilledButton.icon(
        onPressed: onRequest,
        icon: const Icon(LucideIcons.lock_open),
        label: const Text('去授权'),
      ),
    );
  }
}
