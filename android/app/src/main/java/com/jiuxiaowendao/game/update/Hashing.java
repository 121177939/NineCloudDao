package com.jiuxiaowendao.game.update;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public final class Hashing {
    private Hashing() {}

    public static String sha256(File file) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[64 * 1024];
            try (FileInputStream input = new FileInputStream(file)) {
                int read;
                while ((read = input.read(buffer)) != -1) {
                    digest.update(buffer, 0, read);
                }
            }
            return toHex(digest.digest());
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("系统缺少 SHA-256", impossible);
        }
    }

    public static String sha256(byte[] data) {
        try {
            return toHex(MessageDigest.getInstance("SHA-256").digest(data));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("系统缺少 SHA-256", impossible);
        }
    }

    private static String toHex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte item : bytes) out.append(String.format("%02x", item));
        return out.toString();
    }
}
