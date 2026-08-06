package com.jiuxiaowendao.game;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.ProgressBar;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.jiuxiaowendao.game.update.UpdateManager;
import com.jiuxiaowendao.game.web.LocalGameWebViewClient;

public final class MainActivity extends Activity implements LocalGameWebViewClient.PageListener {

    private WebView webView;
    private ProgressBar pageProgress;
    private UpdateManager updateManager;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(23, 19, 13));
        getWindow().setNavigationBarColor(Color.rgb(8, 10, 8));
        setContentView(R.layout.activity_main);

        webView = findViewById(R.id.gameWebView);
        pageProgress = findViewById(R.id.pageProgress);
        updateManager = new UpdateManager(this);
        configureWebView();

        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) {
            webView.loadUrl(LocalGameWebViewClient.START_URL);
        }

        if (BuildConfig.AUTO_UPDATE_ENABLED) {
            // Do not gate update checks on ConnectivityManager. Some EMUI/Huawei builds can
            // report no validated network even while HTTPS is usable.
            webView.postDelayed(updateManager::checkAutomatically, 2500L);
        }

        if (Build.VERSION.SDK_INT >= 33) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(0, this::handleBack);
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void configureWebView() {
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setSupportMultipleWindows(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setBlockNetworkLoads(false);
        settings.setBlockNetworkImage(false);
        settings.setUserAgentString(settings.getUserAgentString()
                + " JiuxiaoWendaoAndroid/" + BuildConfig.VERSION_NAME
                + " GameBuild/" + BuildConfig.GAME_BUILD_ID);
        if (Build.VERSION.SDK_INT >= 26) settings.setSafeBrowsingEnabled(true);

        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);

        webView.setWebViewClient(new LocalGameWebViewClient(this, this));
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                pageProgress.setProgress(newProgress);
                pageProgress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
            }
        });
        webView.setBackgroundColor(Color.rgb(8, 10, 8));
    }

    private void handleBack() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else finish();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (Build.VERSION.SDK_INT < 33) handleBack();
    }

    @Override
    protected void onSaveInstanceState(@NonNull Bundle outState) {
        webView.saveState(outState);
        super.onSaveInstanceState(outState);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (updateManager != null) {
            updateManager.tryResumeInstall();
            if (BuildConfig.AUTO_UPDATE_ENABLED) updateManager.checkAutomatically();
        }
        if (webView != null) webView.onResume();
    }

    @Override
    protected void onPause() {
        if (webView != null) webView.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (updateManager != null) updateManager.shutdown();
        if (webView != null) {
            webView.stopLoading();
            webView.setWebChromeClient(null);
            webView.setWebViewClient(null);
            webView.destroy();
        }
        super.onDestroy();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable android.content.Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == UpdateManager.REQUEST_UNKNOWN_SOURCES) {
            updateManager.tryResumeInstall();
        }
    }

    @Override
    public void onPageStarted() {
        pageProgress.setVisibility(View.VISIBLE);
    }

    @Override
    public void onPageFinished() {
        pageProgress.setVisibility(View.GONE);
    }

    @Override
    public void onPageError(String message) {
        Toast.makeText(this, "页面载入失败：" + message, Toast.LENGTH_LONG).show();
    }
}
