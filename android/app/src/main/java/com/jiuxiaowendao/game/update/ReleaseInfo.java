package com.jiuxiaowendao.game.update;

public final class ReleaseInfo {
    public final long versionCode;
    public final String versionName;
    public final String packageName;
    public final String apkAssetName;
    public final String apkUrl;
    public final String sha256;
    public final String notes;
    public final boolean mandatory;
    public final long minSupportedVersionCode;
    public final String tagName;

    public ReleaseInfo(long versionCode, String versionName, String packageName,
                       String apkAssetName, String apkUrl, String sha256,
                       String notes, boolean mandatory, long minSupportedVersionCode,
                       String tagName) {
        this.versionCode = versionCode;
        this.versionName = versionName;
        this.packageName = packageName;
        this.apkAssetName = apkAssetName;
        this.apkUrl = apkUrl;
        this.sha256 = sha256;
        this.notes = notes;
        this.mandatory = mandatory;
        this.minSupportedVersionCode = minSupportedVersionCode;
        this.tagName = tagName;
    }
}
