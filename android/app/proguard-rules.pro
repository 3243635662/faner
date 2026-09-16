# =====================================================================
# Faner ProGuard/R8 规则
# 修复 release 下启动闪退：
#   java.lang.RuntimeException: Failed to create an instance of androidx.work.impl.WorkDatabase
# =====================================================================

# --- WorkManager（前台服务链路依赖，SDK 35/36 + R8 下必须保留） ---
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# --- Room（WorkManager 内部数据库实现类，防止被 R8 移除/改写） ---
-keep class androidx.room.** { *; }
-dontwarn androidx.room.**

-keep class * extends androidx.room.RoomDatabase { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    public static <methods>;
}

# --- androidx.startup（WorkManager 自动初始化走这里） ---
-keep class androidx.startup.** { *; }
-dontwarn androidx.startup.**

# --- flutter_foreground_task（前台服务） ---
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# --- media_kit / media_kit_video（视频播放内核） ---
# libmpv 通过 JNI 与插件通道协同工作，release 下保留其附属类避免被 R8 改写。
-keep class com.alexmercerind.media_kit_video.** { *; }
-dontwarn com.alexmercerind.media_kit_video.**
