// 独立可运行的 demo：用来单独验证播放页交互，不依赖 faner 项目其余代码。
//
// 运行方式：
// 1. 新建一个空的 Flutter 项目（或临时复用现有项目）
// 2. 把 media_viewer/ 整个文件夹拷贝到 lib/ 下
// 3. pubspec.yaml 里加依赖：video_player: ^2.9.2
// 4. 把这个文件内容替换掉 lib/main.dart（或者临时改 flutter run -t 指向这个文件）
// 5. flutter run

import 'package:flutter/material.dart';

import 'media_viewer/video_player_page.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Player Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const DemoHomePage(),
    );
  }
}

// 公开的测试视频（Google 官方示例素材，用来验证交互，不涉及版权问题）。
final _demoPlaylist = <VideoItem>[
  const VideoItem(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    title: 'Big Buck Bunny',
  ),
  const VideoItem(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    title: 'Elephants Dream',
  ),
  const VideoItem(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    title: 'For Bigger Blazes',
  ),
];

class DemoHomePage extends StatelessWidget {
  const DemoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放列表（点击验证控件隐藏/显示）')),
      body: ListView.builder(
        itemCount: _demoPlaylist.length,
        itemBuilder: (context, index) {
          final item = _demoPlaylist[index];
          return ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(item.title),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerPage(
                    playlist: _demoPlaylist,
                    initialIndex: index,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/*
验证清单（对照你反馈的问题逐条测手）：
1. 点列表任意一项进入播放页 -> 控件应该是隐藏的（没有顶部返回栏/底部进度条）。
2. 点一下视频画面 -> 控件淡入显示，3 秒不操作自动隐藏。
3. 显示状态下再点一下 -> 立即隐藏。
4. 拖动进度条 -> 拖动过程中控件不会被自动隐藏计时器打断。
5. 播放到结尾自动切下一个视频 -> 控件必须是隐藏的，不能沿用上一个视频结束时的状态。
6. 手动点底部的"下一个"按钮切视频 -> 同样必须回到隐藏状态。
7. 把窗口拉宽模拟平板 / 横屏 -> 中间三个按钮应等比放大、间距变宽。
*/
