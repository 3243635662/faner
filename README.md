# Faner

轻量化自用的文件管理与局域网媒体互看 App（Flutter / Android）。

> 完整开发文档见 `局域网媒体管理器_完整开发文档.md`。本 README 记录实现现状，便于后续会话快速接续。

## 功能

- **本地文件浏览与管理**：浏览本机文件（图片/视频/音频/其他），分类筛选、递归搜索，以及新建文件夹、重命名、删除等增删改查操作。
- **局域网媒体播放**：基于 mDNS（`_lanmedia._tcp`）自动发现局域网内同款设备，支持手动 `IP:端口` 连接兜底；浏览并流式播放对方设备上的图片、视频、音频。
- **HTTP 媒体服务器**：本机同时是 Server（对外发布媒体），完整支持 HTTP Range 请求，视频可拖动进度条秒级响应。
- **设置**：设备名称、局域网共享开关、存储权限、版本信息。
- **响应式布局**：手机/平板统一代码，宽度断点自适应（导航栏/侧边栏切换、主从双栏、网格列数自适应）。

## 技术栈

- 状态管理：`flutter_riverpod`（3.x，Notifier / FutureProvider / StreamProvider）
- 路由：`go_router`（Navigator 2.0，声明式路由 + 系统返回键适配）
- HTTP 客户端：`dio`
- 服务发现：`nsd`（mDNS）
- 播放器：`video_player`（视频）、`just_audio`（音频）
- 其他：`path_provider`、`permission_handler`、`shared_preferences`、`device_info_plus`、`flutter_foreground_task`（后台保活）、`fc_native_video_thumbnail`（视频缩略图）、`cached_network_image`（远程图片磁盘缓存）
- 服务端：`dart:io` 的 `HttpServer`
- 主题：Material 3 原生 + 设计 Token（`lib/core/tokens.dart`）

## 目录结构

```
lib/
├── main.dart
├── app/                 # MaterialApp、路由表（go_router）
├── core/                # 常量、文件类型、断点、Result、设计 Token、路径工具
├── data/
│   ├── models/          # FileEntry、DeviceInfo
│   ├── local/           # LocalFileService（本机文件系统抽象）
│   └── remote/          # RemoteFileClient、DiscoveryService
├── server/              # MediaHttpServer + router + handlers（含 Range）
├── providers/           # Riverpod Providers
├── features/            # local_browser / remote_browser / devices / media_viewer / settings / shared
├── permissions/         # 存储权限封装
└── home/                # 底部导航 / 侧边栏壳
```

## 里程碑进度

- [x] 里程碑 1：本地文件浏览器（含权限、缩略图、分类、搜索、增删改查）
- [x] 里程碑 2：最小 Server + 手动互联（`/api/info`、`/api/list`、`/api/file`、`/api/search`）
- [x] 里程碑 3：Range 支持 + 视频/音频播放打通（流式读取）
- [x] 里程碑 4：mDNS 自动发现（注册 + 扫描 + 手动兜底）
- [x] 里程碑 5：平板响应式布局（主从双栏、导航切换、网格自适应）
- [x] 里程碑 6：后台保活（`flutter_foreground_task` 前台服务 + 常驻通知）
- [ ] 里程碑 7：体验打磨（图片缓存/缩略图生成缓存等，阶段 B/C 依赖）

## 运行

```bash
flutter pub get
flutter run          # 需 Android 真机 / 模拟器（Android 8.0+）
```

构建 APK：

```bash
flutter build apk --release
```

## 关键实现点

- **端口**：固定 `8848`，被占用自动 +1 重试（最多 5 次）。
- **明文流量**：`AndroidManifest.xml` 已配置 `android:usesCleartextTraffic="true"`（局域网 HTTP 必需）。
- **路径穿越防护**：`list_handler` 与 `file_handler` 均做 `..` 校验，非法返回 `403`。
- **Range**：`GET /api/file` 支持 `bytes=start-end`，`openRead` 流式读取，禁止整文件读入内存。
- **最小 SDK**：`minSdk = 26`（Android 8.0）。
- **存储权限**：优先 Android 13+ 细分媒体权限，完整访问走 `MANAGE_EXTERNAL_STORAGE`。

## 与开发文档的差异说明

- 文档仅含图片/视频，本次按需求补充了**音频**（`just_audio`）与 `EntryType.audio`。
- 文档核心为浏览/互看，本次按需求补充了本地**增删改查**与**搜索**（`/api/search`）。
- 为满足"默认取机型名"，额外引入 `device_info_plus`。
- 以上均为对核心需求的合理扩展，未偏离文档的架构与安全边界。
