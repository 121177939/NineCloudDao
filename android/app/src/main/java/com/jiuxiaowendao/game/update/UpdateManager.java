package com.jiuxiaowendao.game.update;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;
import androidx.core.content.pm.PackageInfoCompat;

import com.jiuxiaowendao.game.BuildConfig;

import java.io.File;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public final class UpdateManager {
    public static final int REQUEST_UNKNOWN_SOURCES = 9022;
    private static final String UPDATE_PREFS = "jiuxiao_app_update";
    private static final String KEY_LAST_AUTO_ATTEMPT = "last_auto_attempt_ms";
    private static final String KEY_LAST_SUCCESS_CHECK = "last_success_check_ms";
    private static final long AUTO_CHECK_INTERVAL_MS = 10L * 60L * 1000L;
    private static final long AUTO_RETRY_AFTER_FAILURE_MS = 60L * 1000L;

    private final Activity activity;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final GithubReleaseClient client;
    private final AtomicBoolean checking = new AtomicBoolean(false);
    private boolean firstAutomaticCheckInProcess = true;
    private File pendingInstall;
    private AlertDialog updatePrompt;

    public UpdateManager(@NonNull Activity activity) {
        this.activity = activity;
        this.client = new GithubReleaseClient(
                BuildConfig.GITHUB_OWNER,
                BuildConfig.GITHUB_REPO,
                "JiuxiaoWendaoAndroid/" + BuildConfig.VERSION_NAME
        );
    }


    public void checkAutomatically() {
        if (!client.isConfigured()) return;
        long now = System.currentTimeMillis();
        SharedPreferences preferences = activity.getSharedPreferences(UPDATE_PREFS, Activity.MODE_PRIVATE);
        long lastAttempt = preferences.getLong(KEY_LAST_AUTO_ATTEMPT, 0L);
        long lastSuccess = preferences.getLong(KEY_LAST_SUCCESS_CHECK, 0L);

        // 每次真正冷启动后的第一次检查不受上次成功时间限制。
        // 旧实现会在网络请求开始前就写入30分钟节流；一旦该次请求失败，
        // 后续回到前台也会被静默拦截，看起来像“APP完全收不到更新”。
        boolean processFirst = firstAutomaticCheckInProcess;
        firstAutomaticCheckInProcess = false;
        if (!processFirst) {
            if (now - lastAttempt < AUTO_RETRY_AFTER_FAILURE_MS) return;
            if (lastSuccess > 0L && now - lastSuccess < AUTO_CHECK_INTERVAL_MS) return;
        }
        preferences.edit().putLong(KEY_LAST_AUTO_ATTEMPT, now).apply();
        check(false);
    }

    public void check(boolean userInitiated) {
        if (!client.isConfigured()) {
            if (userInitiated) showMessage("尚未配置 GitHub 更新仓库", "请修改 gradle.properties 中的 GITHUB_OWNER 和 GITHUB_REPO，然后重新构建正式版 APK。");
            return;
        }
        if (!checking.compareAndSet(false, true)) {
            if (userInitiated) toast("正在检查更新");
            return;
        }
        if (userInitiated) toast("正在检查更新……");

        executor.execute(() -> {
            try {
                ReleaseInfo release = client.fetchLatest();
                activity.getSharedPreferences(UPDATE_PREFS, Activity.MODE_PRIVATE)
                        .edit().putLong(KEY_LAST_SUCCESS_CHECK, System.currentTimeMillis()).apply();
                long currentVersion = PackageInfoCompat.getLongVersionCode(
                        activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0));
                if (!activity.getPackageName().equals(release.packageName)) {
                    throw new SecurityException("更新清单包名与当前应用不一致");
                }
                if (release.versionCode <= currentVersion) {
                    if (userInitiated) main.post(() -> showMessage("已是最新版本", "当前版本：" + BuildConfig.VERSION_NAME + "（" + currentVersion + "）"));
                } else {
                    main.post(() -> promptUpdate(release, currentVersion));
                }
            } catch (Exception error) {
                if (userInitiated) main.post(() -> showMessage("检查更新失败", safeMessage(error)));
            } finally {
                checking.set(false);
            }
        });
    }

    public void tryResumeInstall() {
        if (pendingInstall != null && pendingInstall.exists() && canInstallUnknownApps()) {
            File apk = pendingInstall;
            pendingInstall = null;
            launchInstaller(apk);
        }
    }

    public void shutdown() {
        executor.shutdownNow();
    }

    private void promptUpdate(ReleaseInfo release, long currentVersion) {
        if (activity.isFinishing() || activity.isDestroyed()) return;
        if (updatePrompt != null && updatePrompt.isShowing()) return;
        boolean forced = release.mandatory || (release.minSupportedVersionCode > 0
                && currentVersion < release.minSupportedVersionCode);
        String notes = release.notes == null || release.notes.trim().isEmpty()
                ? "本次更新未填写说明。"
                : release.notes.trim();
        String message = "当前版本：" + BuildConfig.VERSION_NAME + "（" + currentVersion + "）\n"
                + "最新版本：" + release.versionName + "（" + release.versionCode + "）\n\n"
                + notes + "\n\n是否立即更新？";

        updatePrompt = new AlertDialog.Builder(activity)
                .setTitle(forced ? "发现必须更新" : "发现新版本")
                .setMessage(message)
                .setPositiveButton("立即更新", (d, which) -> downloadAndInstall(release))
                .setNegativeButton(forced ? null : "暂不更新", null)
                .create();
        updatePrompt.setCancelable(!forced);
        updatePrompt.setCanceledOnTouchOutside(!forced);
        updatePrompt.setOnDismissListener(dialog -> updatePrompt = null);
        updatePrompt.show();
    }

    private void downloadAndInstall(ReleaseInfo release) {
        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(24);
        panel.setPadding(pad, dp(12), pad, dp(8));

        TextView status = new TextView(activity);
        status.setText("准备下载……");
        status.setTextSize(15f);
        status.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        panel.addView(status, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        ProgressBar progress = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(1000);
        progress.setIndeterminate(true);
        LinearLayout.LayoutParams progressParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(10));
        progressParams.topMargin = dp(16);
        panel.addView(progress, progressParams);

        TextView detail = new TextView(activity);
        detail.setGravity(Gravity.END);
        detail.setText("等待连接");
        LinearLayout.LayoutParams detailParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        detailParams.topMargin = dp(10);
        panel.addView(detail, detailParams);

        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setTitle("下载更新")
                .setView(panel)
                .setNegativeButton("取消", null)
                .create();
        dialog.setCanceledOnTouchOutside(false);
        dialog.show();

        AtomicBoolean cancelled = new AtomicBoolean(false);
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> {
            cancelled.set(true);
            dialog.dismiss();
        });

        executor.execute(() -> {
            try {
                File downloadRoot = new File(activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "updates");
                File apk = new File(downloadRoot, "jiuxiao-update-" + release.versionCode + ".apk");
                client.download(release.apkUrl, apk, (received, total) -> {
                    if (cancelled.get()) throw new DownloadCancelledException();
                    main.post(() -> {
                        if (total > 0) {
                            progress.setIndeterminate(false);
                            int value = (int) Math.min(1000L, received * 1000L / total);
                            progress.setProgress(value);
                            detail.setText(String.format(Locale.CHINA, "%.1f / %.1f MB",
                                    received / 1048576.0, total / 1048576.0));
                        } else {
                            progress.setIndeterminate(true);
                            detail.setText(String.format(Locale.CHINA, "已下载 %.1f MB", received / 1048576.0));
                        }
                    });
                });
                if (cancelled.get()) throw new DownloadCancelledException();
                main.post(() -> {
                    status.setText("正在校验版本、SHA-256与签名……");
                    detail.setText("请勿关闭应用");
                    progress.setIndeterminate(true);
                });
                ApkSecurityVerifier.verify(activity, apk, release);
                main.post(() -> {
                    if (dialog.isShowing()) dialog.dismiss();
                    requestInstall(apk);
                });
            } catch (DownloadCancelledException ignored) {
                // 用户主动取消，不弹错误。
            } catch (Exception error) {
                main.post(() -> {
                    if (dialog.isShowing()) dialog.dismiss();
                    showMessage("更新失败", safeMessage(error));
                });
            }
        });
    }

    private void requestInstall(File apk) {
        if (Build.VERSION.SDK_INT >= 26 && !canInstallUnknownApps()) {
            pendingInstall = apk;
            new AlertDialog.Builder(activity)
                    .setTitle("需要安装授权")
                    .setMessage("安卓要求你为“九霄问道”开启“允许来自此来源的应用”。开启后返回本应用，将继续安装。")
                    .setPositiveButton("去开启", (dialog, which) -> {
                        Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:" + activity.getPackageName()));
                        activity.startActivityForResult(intent, REQUEST_UNKNOWN_SOURCES);
                    })
                    .setNegativeButton("取消", null)
                    .show();
            return;
        }
        launchInstaller(apk);
    }

    private boolean canInstallUnknownApps() {
        return Build.VERSION.SDK_INT < 26 || activity.getPackageManager().canRequestPackageInstalls();
    }

    private void launchInstaller(File apk) {
        try {
            Uri uri = FileProvider.getUriForFile(activity,
                    activity.getPackageName() + ".fileprovider", apk);
            Intent intent = new Intent(Intent.ACTION_INSTALL_PACKAGE)
                    .setData(uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try {
                activity.startActivity(intent);
            } catch (Exception unsupported) {
                Intent fallback = new Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                activity.startActivity(fallback);
            }
        } catch (Exception error) {
            showMessage("无法启动安装器", safeMessage(error));
        }
    }

    private void showMessage(String title, String message) {
        new AlertDialog.Builder(activity)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton("确定", null)
                .show();
    }

    private void toast(String message) {
        main.post(() -> Toast.makeText(activity, message, Toast.LENGTH_SHORT).show());
    }

    private String safeMessage(Throwable error) {
        String value = error.getMessage();
        return value == null || value.trim().isEmpty() ? error.getClass().getSimpleName() : value;
    }

    private int dp(int value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }

    private static final class DownloadCancelledException extends RuntimeException {}
}
