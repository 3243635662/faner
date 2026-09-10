/// 文件类型枚举 + 后缀 → MIME 判断。
enum EntryType { folder, image, video, audio, other }

extension EntryTypeX on EntryType {
  bool get isFolder => this == EntryType.folder;
  bool get isImage => this == EntryType.image;
  bool get isVideo => this == EntryType.video;
  bool get isAudio => this == EntryType.audio;
  bool get isMedia => isImage || isVideo || isAudio;
}

/// 根据文件名（或带路径名）判断文件类型。
EntryType fileTypeFromName(String name) {
  final ext = _extension(name);
  if (imageExtensions.contains(ext)) return EntryType.image;
  if (videoExtensions.contains(ext)) return EntryType.video;
  if (audioExtensions.contains(ext)) return EntryType.audio;
  return EntryType.other;
}

/// 后缀 → MIME。未知后缀返回 [fallbackMime]。
String mimeTypeFor(String name, {String fallback = 'application/octet-stream'}) {
  final ext = _extension(name);
  return _mimeByExt[ext] ?? fallback;
}

const Set<String> imageExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
};

const Set<String> videoExtensions = {
  'mp4', 'mkv', 'mov', 'avi', 'webm', 'ts', 'm4v', '3gp', 'flv',
};

const Set<String> audioExtensions = {
  'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma',
};

const Map<String, String> _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mkv': 'video/x-matroska',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'webm': 'video/webm',
  'ts': 'video/mp2t',
  '3gp': 'video/3gpp',
  'flv': 'video/x-flv',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'wma': 'audio/x-ms-wma',
};

String _extension(String name) {
  final idx = name.lastIndexOf('.');
  if (idx <= 0 || idx == name.length - 1) return '';
  return name.substring(idx + 1).toLowerCase();
}
