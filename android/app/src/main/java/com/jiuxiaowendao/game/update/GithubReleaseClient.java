package com.jiuxiaowendao.game.update;

import android.text.TextUtils;

import androidx.annotation.NonNull;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

public final class GithubReleaseClient {
    public interface ProgressListener {
        void onProgress(long received, long total);
    }

    private static final String ACCEPT = "application/vnd.github+json";
    private static final String API_VERSION = "2026-03-10";
    private static final int CONNECT_TIMEOUT_MS = 15_000;
    private static final int READ_TIMEOUT_MS = 45_000;
    private static final int MAX_REDIRECTS = 8;
    private static final int MAX_JSON_BYTES = 2 * 1024 * 1024;
    private static final Pattern REPO_PART = Pattern.compile("[A-Za-z0-9_.-]+");

    private final String owner;
    private final String repo;
    private final String userAgent;

    public GithubReleaseClient(String owner, String repo, String userAgent) {
        this.owner = owner;
        this.repo = repo;
        this.userAgent = userAgent;
    }

    public boolean isConfigured() {
        return !TextUtils.isEmpty(owner) && !TextUtils.isEmpty(repo)
                && !owner.startsWith("YOUR_") && !repo.startsWith("YOUR_")
                && REPO_PART.matcher(owner).matches() && REPO_PART.matcher(repo).matches();
    }

    @NonNull
    public ReleaseInfo fetchLatest() throws IOException, JSONException {
        String apiUrl = String.format(Locale.ROOT,
                "https://api.github.com/repos/%s/%s/releases/latest", owner, repo);
        JSONObject release = new JSONObject(readText(apiUrl, true));
        String tagName = release.optString("tag_name", "");
        JSONArray assets = release.optJSONArray("assets");
        if (assets == null) throw new IOException("最新 Release 没有附件");

        Map<String, String> assetUrls = new HashMap<>();
        for (int i = 0; i < assets.length(); i++) {
            JSONObject asset = assets.getJSONObject(i);
            String name = asset.optString("name", "");
            String url = asset.optString("browser_download_url", "");
            if (!name.isEmpty() && !url.isEmpty()) assetUrls.put(name, url);
        }

        String manifestUrl = assetUrls.get("app-update.json");
        if (manifestUrl == null) {
            throw new IOException("最新 Release 缺少 app-update.json");
        }
        if (!assetUrls.containsKey("SHA256SUMS.txt")) {
            throw new IOException("最新 Release 缺少 SHA256SUMS.txt");
        }

        JSONObject manifest = new JSONObject(readText(manifestUrl, false));
        if (manifest.optInt("schemaVersion", 0) != 1) {
            throw new IOException("不支持的更新清单格式");
        }
        long versionCode = manifest.getLong("versionCode");
        String versionName = manifest.getString("versionName");
        String packageName = manifest.getString("packageName");
        String apkAssetName = manifest.optString("apkAssetName", "jiuxiao-wendao-release.apk");
        String apkUrl = assetUrls.get(apkAssetName);
        if (apkUrl == null) throw new IOException("最新 Release 缺少 " + apkAssetName);

        String sha256 = manifest.getString("sha256").trim().toLowerCase(Locale.ROOT);
        if (!sha256.matches("[0-9a-f]{64}")) throw new IOException("更新清单 SHA-256 格式错误");
        String notes = manifest.optString("notes", release.optString("body", ""));
        boolean mandatory = manifest.optBoolean("mandatory", false);
        long minSupported = manifest.optLong("minSupportedVersionCode", 0L);

        return new ReleaseInfo(versionCode, versionName, packageName, apkAssetName,
                apkUrl, sha256, notes, mandatory, minSupported, tagName);
    }

    public void download(@NonNull String url, @NonNull File target,
                         @NonNull ProgressListener listener) throws IOException {
        File parent = target.getParentFile();
        if (parent == null || (!parent.exists() && !parent.mkdirs())) {
            throw new IOException("无法创建更新目录");
        }
        File part = new File(parent, target.getName() + ".part");
        if (part.exists() && !part.delete()) throw new IOException("无法清理旧下载文件");

        HttpURLConnection connection = open(url, false);
        long total = connection.getContentLengthLong();
        long received = 0L;
        try (BufferedInputStream input = new BufferedInputStream(connection.getInputStream());
             FileOutputStream output = new FileOutputStream(part)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = input.read(buffer)) != -1) {
                output.write(buffer, 0, read);
                received += read;
                listener.onProgress(received, total);
            }
            output.getFD().sync();
        } finally {
            connection.disconnect();
        }
        if (total > 0 && received != total) {
            part.delete();
            throw new IOException("APK 下载不完整");
        }
        if (target.exists() && !target.delete()) {
            part.delete();
            throw new IOException("无法替换旧更新文件");
        }
        if (!part.renameTo(target)) {
            part.delete();
            throw new IOException("无法保存下载完成的 APK");
        }
    }

    private String readText(String url, boolean githubApi) throws IOException {
        HttpURLConnection connection = open(url, githubApi);
        try (BufferedInputStream input = new BufferedInputStream(connection.getInputStream());
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[16 * 1024];
            int read;
            int total = 0;
            while ((read = input.read(buffer)) != -1) {
                total += read;
                if (total > MAX_JSON_BYTES) throw new IOException("更新清单过大");
                output.write(buffer, 0, read);
            }
            return output.toString(StandardCharsets.UTF_8.name());
        } finally {
            connection.disconnect();
        }
    }

    private HttpURLConnection open(String initialUrl, boolean githubApi) throws IOException {
        String current = initialUrl;
        for (int i = 0; i <= MAX_REDIRECTS; i++) {
            HttpURLConnection connection = (HttpURLConnection) new URL(current).openConnection();
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("User-Agent", userAgent);
            connection.setRequestProperty("Accept", githubApi ? ACCEPT : "application/octet-stream, application/json;q=0.9, */*;q=0.8");
            if (githubApi) connection.setRequestProperty("X-GitHub-Api-Version", API_VERSION);
            int code = connection.getResponseCode();
            if (code >= 300 && code < 400) {
                String location = connection.getHeaderField("Location");
                connection.disconnect();
                if (location == null || location.isEmpty()) throw new IOException("GitHub 重定向缺少地址");
                current = new URL(new URL(current), location).toString();
                continue;
            }
            if (code < 200 || code >= 300) {
                connection.disconnect();
                throw new IOException("网络请求失败，HTTP " + code);
            }
            return connection;
        }
        throw new IOException("GitHub 重定向次数过多");
    }
}
