import 'package:permission_handler/permission_handler.dart';

/// 存储权限封装。
///
/// 本 app 是「文件共享服务器」，核心需求是读取 `/storage/emulated/0`
/// 下的任意文件，因此**必须**获得 `MANAGE_EXTERNAL_STORAGE`（所有文件访问）。
/// Android 13+ 的 `READ_MEDIA_*` 只覆盖 MediaStore 索引的媒体文件，作为降级。
class StoragePermission {
  StoragePermission._();

  /// 是否拥有完整外部存储访问（MANAGE_EXTERNAL_STORAGE）。
  /// 这是读取任意路径文件（含第三方 app 产生的文件）的前提。
  static Future<bool> hasFullAccess() async {
    final manage = await Permission.manageExternalStorage.status;
    return manage.isGranted;
  }

  /// 是否至少能浏览本机媒体：完整访问，或 Android 13+ 细分媒体权限。
  static Future<bool> isGranted() async {
    if (await hasFullAccess()) return true;
    final photos = await Permission.photos.status;
    final videos = await Permission.videos.status;
    return photos.isGranted || videos.isGranted;
  }

  /// 请求权限。优先引导开启「所有文件访问」（共享必需），
  /// 同时申请 Android 13+ 细分媒体权限作为降级。
  static Future<bool> ensure() async {
    if (await Permission.manageExternalStorage.status.isGranted) {
      return true;
    }

    // Android 13+ 细分媒体权限（降级：至少能读相机照片/视频）
    await Permission.photos.request();
    await Permission.videos.request();

    // 完整外部存储访问：跳转系统设置页「所有文件访问」。
    // 注意：request() 返回时通常仍为 denied（需用户手动开启），
    // 因此最终用 isGranted() 重新查询，并配合 App 生命周期在返回时复查。
    await Permission.manageExternalStorage.request();

    return isGranted();
  }
}
