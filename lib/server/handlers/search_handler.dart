import 'dart:io';

import '../server_context.dart';

/// GET /api/search?q=xxx
Future<void> handleSearch(HttpRequest request, ServerContext ctx) async {
  final query = request.uri.queryParameters['q'] ?? '';
  final result = await ctx.localFileService.search(query);
  result.fold(
    (entries) => writeJson(request, {
      'entries': entries.map((e) => e.toJson()).toList(),
    }),
    (err) => serverError(request, err),
  );
}
