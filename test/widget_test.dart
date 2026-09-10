import 'package:faner/core/file_type.dart';
import 'package:faner/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fileTypeFromName 正确识别文件类型', () {
    expect(fileTypeFromName('a.jpg'), EntryType.image);
    expect(fileTypeFromName('b.jpeg'), EntryType.image);
    expect(fileTypeFromName('c.mp4'), EntryType.video);
    expect(fileTypeFromName('d.mkv'), EntryType.video);
    expect(fileTypeFromName('e.mp3'), EntryType.audio);
    expect(fileTypeFromName('f.flac'), EntryType.audio);
    expect(fileTypeFromName('g.txt'), EntryType.other);
  });

  test('mimeTypeFor 返回正确 MIME', () {
    expect(mimeTypeFor('a.mp4'), 'video/mp4');
    expect(mimeTypeFor('a.jpg'), 'image/jpeg');
    expect(mimeTypeFor('a.mkv'), 'video/x-matroska');
    expect(mimeTypeFor('a.mp3'), 'audio/mpeg');
    expect(mimeTypeFor('a.xyz'), 'application/octet-stream');
  });

  test('formatDuration 格式化时长', () {
    expect(formatDuration(const Duration(seconds: 65)), '01:05');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
