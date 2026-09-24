/// 局域网共享口令的协议约定（服务端与客户端共用，避免两边写死后漂移）。
library;

/// 鉴权请求头名称。
const String authHeaderName = 'x-auth-token';

/// 鉴权 query 参数名。
///
/// 媒体地址（图片/视频/缩略图）由系统组件直接发起请求，无法自定义 header，
/// 因此必须同时支持 query 形式。
const String authQueryParam = 'token';

/// 口令最短长度（太短等于没设）。
const int minPasswordLength = 4;
