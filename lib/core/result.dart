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
  const Err(this.message);

  final String message;

  @override
  R fold<R>(R Function(T value) onOk, R Function(String message) onErr) =>
      onErr(message);
}
