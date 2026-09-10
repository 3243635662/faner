# 播放页控件方案 — 集成说明

## 文件对应关系（放进你项目的位置）

```
faner/lib/features/media_viewer/
├── video_player_page.dart                      <- 本包 video_player_page.dart
├── controllers/
│   └── video_controls_controller.dart          <- 本包 controllers/video_controls_controller.dart
└── widgets/
    ├── controls_overlay.dart                   <- 本包 widgets/controls_overlay.dart
    └── video_progress_bar.dart                 <- 本包 widgets/video_progress_bar.dart
```

`demo_main.dart` 只是给你单独跑一遍验证交互用的，**不需要放进 faner 项目**。

## 依赖

`pubspec.yaml` 里确认已有（你现有项目应该已经有）：

```yaml
dependencies:
  video_player: ^2.9.2
```

## 核心问题的修复点在哪

你之前反馈的"自动切下一个视频/手动进入播放时控件状态错乱"，根因是控件可见性
状态没有在**所有**进入播放会话的入口都被强制重置。这套代码把这件事收敛成
一个方法：`VideoControlsController.onEnterPlayer()`，并且在
`video_player_page.dart` 的 `_loadIndex()` 里统一调用 —— 无论是：

1. 首次打开播放页（`initState` -> `_loadIndex`）
2. 自动播放完切下一个（`_onAutoAdvance` -> `_loadIndex`）
3. 手动点上一个/下一个按钮（`_onPrevious`/`_onNext` -> `_loadIndex`）

三个入口最终都走同一个 `_loadIndex`，所以不存在"漏掉某个入口"的可能。
以后如果你加新的切换视频方式（比如手势左右滑动切换），**也必须走
`_loadIndex`，不要绕过它直接换 `VideoPlayerController`**，否则这个 bug
会复现。

## 接入你现有的 go_router / Riverpod

### go_router 路由传参

```dart
GoRoute(
  path: 'player',
  builder: (context, state) {
    final args = state.extra as PlayerRouteArgs; // 你自己定义的参数类
    return VideoPlayerPage(
      playlist: args.playlist,
      initialIndex: args.initialIndex,
    );
  },
),
```

跳转时：

```dart
context.push('/player', extra: PlayerRouteArgs(
  playlist: currentFolderVideos.map((e) => VideoItem(
    url: e.isRemote ? e.remoteStreamUrl : e.localPath,
    title: e.displayName,
  )).toList(),
  initialIndex: tappedIndex,
));
```

### 如果播放列表来自 Riverpod Provider

`VideoPlayerPage` 目前是"传进去的 playlist 就是固定的"，如果你想让播放列表
随文件浏览页的排序/筛选实时联动，可以把 `playlist` 参数换成从
`ref.watch(currentFolderVideosProvider)` 取，`VideoPlayerPage` 改成
`ConsumerStatefulWidget` 即可，`_loadIndex` 的逻辑不需要变。

## 局域网视频源的兼容性提醒

`_createController` 里对 `http://` 直接用 `VideoPlayerController.networkUrl`，
对应你项目 Server 端的 `/api/file`（已支持 Range）。如果后续遇到某些安卓
平板拍出来的视频格式（比如某些机型的 HEVC 封装、TS 流）在 `video_player`
默认解码器上播不出来/花屏，参考我之前建议的 `media_kit` 或 `fvp` 包替换
底层引擎，UI 层（`ControlsOverlay`/`VideoControlsController`）完全不用改，
只需要把 `video_player_page.dart` 里 `VideoPlayerController` 相关的几行
换成对应包的 API。

## 平板细节还可以继续打磨的点（当前 demo 未包含）

- 横屏下如果视频宽高比和屏幕差异很大，可以在两侧加播放列表侧栏而不是纯黑边
  （复用你现有的响应式断点 `lib/core/tokens.dart`）。
- 音量/亮度的边缘滑动手势（左边滑亮度、右边滑音量）—— 主流播放器标配，
  如果需要我可以单独再给一版带这个手势的 `GestureDetector` 实现。
- 双击画面快进/快退 15 秒（抖音/B站风格）。

这些都是在现有结构上加手势识别，不需要改动 `VideoControlsController` 的
核心逻辑,需要的话直接说就行。
