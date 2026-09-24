/// 统一的 `Result<T>` 封装，避免到处 try/catch 与空值判断。
sealed class Result<T> {
  const Result();

  R fold<R>(R Function(T value) onOk, R Function(String message) onErr);

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;
}

class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  R fold<R>(R Function(T value) onOk, R Function(String message) onErr) =>
      onOk(value);
}

class Err<T> extends Result<T> {
  const Err(this.message, {this.code});

  final String message;

  /// 机器可读的错误码（如 `unauthorized`），供上层做分支处理；
  /// 普通展示用 [message] 即可。
  final String? code;

  @override
  R fold<R>(R Function(T value) onOk, R Function(String message) onErr) =>
      onErr(message);
}

/// 错误码常量。
class ErrorCodes {
  ErrorCodes._();

  /// 需要共享口令 / 口令不正确（HTTP 401）。
  static const String unauthorized = 'unauthorized';
}
