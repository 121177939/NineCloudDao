# 当前版本不启用代码压缩。以后开启 R8 时保留 WebView JavaScript 接口。
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
