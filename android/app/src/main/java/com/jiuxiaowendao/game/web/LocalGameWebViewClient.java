package com.jiuxiaowendao.game.web;

import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.webkit.WebViewAssetLoader;

import com.jiuxiaowendao.game.BuildConfig;
import androidx.webkit.WebViewClientCompat;

public final class LocalGameWebViewClient extends WebViewClientCompat {
    public interface PageListener {
        void onPageStarted();
        void onPageFinished();
        void onPageError(String message);
    }

    public static final String LOCAL_HOST = BuildConfig.SUPABASE_HOST;
    public static final String START_URL = "https://" + LOCAL_HOST + "/assets/game/index.html?android_local=1";

    private final Context context;
    private final WebViewAssetLoader assetLoader;
    private final PageListener listener;

    public LocalGameWebViewClient(@NonNull Context context, @NonNull PageListener listener) {
        this.context = context;
        this.listener = listener;
        this.assetLoader = new WebViewAssetLoader.Builder()
                .setDomain(LOCAL_HOST)
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(context))
                .build();
    }

    @Nullable
    @Override
    public WebResourceResponse shouldInterceptRequest(@NonNull WebView view, @NonNull WebResourceRequest request) {
        return assetLoader.shouldInterceptRequest(request.getUrl());
    }

    @Nullable
    @Override
    @SuppressWarnings("deprecation")
    public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
        return assetLoader.shouldInterceptRequest(Uri.parse(url));
    }

    @Override
    public boolean shouldOverrideUrlLoading(@NonNull WebView view, @NonNull WebResourceRequest request) {
        return handleNavigation(request.getUrl());
    }

    @Override
    @SuppressWarnings("deprecation")
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
        return handleNavigation(Uri.parse(url));
    }

    private boolean handleNavigation(@Nullable Uri uri) {
        if (uri == null) return true;
        String scheme = uri.getScheme();
        String host = uri.getHost();
        if (("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
                && LOCAL_HOST.equalsIgnoreCase(host)) {
            return false;
        }

        if ("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme)
                || "mailto".equalsIgnoreCase(scheme)) {
            try {
                context.startActivity(new Intent(Intent.ACTION_VIEW, uri));
            } catch (Exception ignored) {
                listener.onPageError("无法打开外部链接");
            }
        }
        return true;
    }

    @Override
    public void onPageStarted(@NonNull WebView view, @NonNull String url, @Nullable Bitmap favicon) {
        listener.onPageStarted();
    }

    @Override
    public void onPageFinished(@NonNull WebView view, @NonNull String url) {
        listener.onPageFinished();
    }

    @Override
    public void onReceivedError(@NonNull WebView view, @NonNull WebResourceRequest request,
                                @NonNull androidx.webkit.WebResourceErrorCompat error) {
        if (request.isForMainFrame()) {
            listener.onPageError(String.valueOf(error.getDescription()));
        }
    }
}
