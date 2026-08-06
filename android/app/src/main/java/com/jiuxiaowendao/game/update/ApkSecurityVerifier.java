package com.jiuxiaowendao.game.update;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.content.pm.PackageInfoCompat;

import java.io.File;
import java.util.HashSet;
import java.util.Set;

public final class ApkSecurityVerifier {
    private ApkSecurityVerifier() {}

    public static void verify(@NonNull Context context, @NonNull File apk,
                              @NonNull ReleaseInfo release) throws Exception {
        String actualHash = Hashing.sha256(apk);
        if (!actualHash.equalsIgnoreCase(release.sha256)) {
            throw new SecurityException("APK SHA-256 校验失败");
        }

        PackageManager pm = context.getPackageManager();
        PackageInfo candidate = getArchiveInfo(pm, apk);
        if (candidate == null) throw new SecurityException("下载文件不是有效 APK");
        if (!context.getPackageName().equals(candidate.packageName)) {
            throw new SecurityException("APK 包名不一致：" + candidate.packageName);
        }
        if (!release.packageName.equals(candidate.packageName)) {
            throw new SecurityException("更新清单包名与 APK 不一致");
        }

        long candidateVersion = PackageInfoCompat.getLongVersionCode(candidate);
        long installedVersion = PackageInfoCompat.getLongVersionCode(
                getInstalledInfo(pm, context.getPackageName()));
        if (candidateVersion != release.versionCode) {
            throw new SecurityException("APK 版本号与更新清单不一致");
        }
        if (candidateVersion <= installedVersion) {
            throw new SecurityException("下载的 APK 不是更高版本");
        }

        PackageInfo installed = getInstalledInfo(pm, context.getPackageName());
        Set<String> installedCerts = certificateDigests(installed);
        Set<String> candidateCerts = certificateDigests(candidate);
        if (installedCerts.isEmpty() || candidateCerts.isEmpty()) {
            throw new SecurityException("无法读取 APK 签名证书");
        }
        boolean signerMatched = false;
        for (String cert : installedCerts) {
            if (candidateCerts.contains(cert)) {
                signerMatched = true;
                break;
            }
        }
        if (!signerMatched) {
            throw new SecurityException("APK 签名与当前安装版本不一致");
        }
    }

    private static PackageInfo getInstalledInfo(PackageManager pm, String packageName)
            throws PackageManager.NameNotFoundException {
        if (Build.VERSION.SDK_INT >= 33) {
            return pm.getPackageInfo(packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES));
        }
        int flags = Build.VERSION.SDK_INT >= 28
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;
        //noinspection deprecation
        return pm.getPackageInfo(packageName, flags);
    }

    private static PackageInfo getArchiveInfo(PackageManager pm, File apk) {
        if (Build.VERSION.SDK_INT >= 33) {
            return pm.getPackageArchiveInfo(apk.getAbsolutePath(),
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES));
        }
        int flags = Build.VERSION.SDK_INT >= 28
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;
        //noinspection deprecation
        return pm.getPackageArchiveInfo(apk.getAbsolutePath(), flags);
    }

    private static Set<String> certificateDigests(PackageInfo info) {
        Set<String> result = new HashSet<>();
        Signature[] signatures;
        if (Build.VERSION.SDK_INT >= 28 && info.signingInfo != null) {
            signatures = info.signingInfo.hasMultipleSigners()
                    ? info.signingInfo.getApkContentsSigners()
                    : info.signingInfo.getSigningCertificateHistory();
        } else {
            //noinspection deprecation
            signatures = info.signatures;
        }
        if (signatures != null) {
            for (Signature signature : signatures) {
                result.add(Hashing.sha256(signature.toByteArray()));
            }
        }
        return result;
    }
}
