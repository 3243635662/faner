import 'dart:io';

import '../../core/path_utils.dart';
import '../server_context.dart';

/// GET /api/list?path=xxx
Future<void> handleList(HttpRequest request, ServerContext ctx) async {
  final path = request.uri.queryParameters['path'] ?? '';
  if (normalizeRelPath(path) == null) return forbidden(request); // 路径穿越 → 403
  final guard = PathGuard(ctx.root);
  final abs = guard.resolve(path);
  if (abs == null) return forbidden(request);
  if (!await Directory(abs).exists()) return notFound(request);

  final result = await ctx.localFileService.listEntries(path);
  result.fold(
    (entries) => writeJson(request, {
      'currentPath': path,
      'entries': entries.map((e) => e.toJson()).toList(),
    }),
    (err) => serverError(request, err),
  );
}
