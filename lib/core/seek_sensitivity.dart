/// 左右滑动快进 / 后退的灵敏度档位。
///
/// [msPerPx] 表示**每滑动 1 个逻辑像素**对应的跳转时长（毫秒）。
/// 1 厘米 ≈ 63 逻辑像素，所以 200ms/px ≈ 轻扫 1 厘米跳 12.6 秒。
///
/// 用"像素速率"而非"整屏比例"，保证手感与屏幕尺寸、横竖屏无关；
/// 短视频会自动退化为全片比例映射（见 `MediaPlayerView`）。
enum SeekSensitivity {
  /// 迟缓：同样距离跳得更少，适合精细定位。
  slow(120, '迟缓'),

  /// 标准：默认手感。
  standard(200, '标准'),

  /// 灵敏：轻扫即可大幅跳转。
  fast(320, '灵敏');

  const SeekSensitivity(this.msPerPx, this.label);

  /// 每逻辑像素对应的跳转毫秒数。
  final double msPerPx;

  /// 设置页展示用名称。
  final String label;

  /// 轻扫 1 厘米大致跳转的秒数（设置页用它给用户直观预期）。
  int get secondsPerCentimeter => (msPerPx * 63 / 1000).round();
}
