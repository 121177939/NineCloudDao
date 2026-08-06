package org.gradle.wrapper;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Properties;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Minimal, self-contained Gradle distribution bootstrap used by this project.
 * It honors the standard gradle-wrapper.properties keys needed here, verifies
 * the official distribution SHA-256, extracts safely, then launches Gradle.
 */
public final class GradleWrapperMain {
    private static final int BUFFER_SIZE = 64 * 1024;

    private GradleWrapperMain() {}

    public static void main(String[] args) throws Exception {
        Path projectRoot = locateProjectRoot();
        Path propertiesFile = projectRoot.resolve("gradle/wrapper/gradle-wrapper.properties");
        Properties properties = loadProperties(propertiesFile);

        String distributionUrl = require(properties, "distributionUrl");
        String expectedSha256 = require(properties, "distributionSha256Sum").toLowerCase();
        int timeout = parseInt(properties.getProperty("networkTimeout"), 10000);

        URI uri = URI.create(distributionUrl);
        String archiveName = Paths.get(uri.getPath()).getFileName().toString();
        if (!archiveName.endsWith(".zip")) {
            throw new IllegalArgumentException("Only ZIP Gradle distributions are supported: " + archiveName);
        }
        String distributionName = archiveName.substring(0, archiveName.length() - 4);
        String urlHash = sha256Hex(distributionUrl.getBytes(java.nio.charset.StandardCharsets.UTF_8)).substring(0, 16);

        Path gradleUserHome = resolveGradleUserHome();
        Path distributionRoot = gradleUserHome.resolve("wrapper/dists").resolve(distributionName).resolve(urlHash);
        Files.createDirectories(distributionRoot);
        Path lockPath = distributionRoot.resolve(".install.lock");

        Path gradleHome;
        try (FileChannel channel = FileChannel.open(lockPath,
                StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock ignored = channel.lock()) {
            gradleHome = findGradleHome(distributionRoot);
            if (gradleHome == null) {
                installDistribution(uri.toURL(), expectedSha256, timeout, archiveName, distributionRoot);
                gradleHome = findGradleHome(distributionRoot);
            }
        }

        if (gradleHome == null) {
            throw new IOException("Gradle distribution was not installed correctly under " + distributionRoot);
        }

        boolean windows = System.getProperty("os.name", "").toLowerCase().contains("win");
        Path executable = gradleHome.resolve("bin").resolve(windows ? "gradle.bat" : "gradle");
        if (!Files.isRegularFile(executable)) {
            throw new IOException("Gradle executable missing: " + executable);
        }
        if (!windows) {
            executable.toFile().setExecutable(true, true);
        }

        String[] command = new String[args.length + 1];
        command[0] = executable.toAbsolutePath().toString();
        System.arraycopy(args, 0, command, 1, args.length);

        Process process = new ProcessBuilder(command)
                .directory(projectRoot.toFile())
                .inheritIO()
                .start();
        int exitCode = process.waitFor();
        System.exit(exitCode);
    }

    private static Path locateProjectRoot() throws Exception {
        Path location = Paths.get(GradleWrapperMain.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI()).toAbsolutePath().normalize();
        Path cursor = Files.isRegularFile(location) ? location.getParent() : location;
        while (cursor != null) {
            if (Files.isRegularFile(cursor.resolve("gradle/wrapper/gradle-wrapper.properties"))) {
                return cursor;
            }
            cursor = cursor.getParent();
        }
        throw new IOException("Cannot locate project root from " + location);
    }

    private static Properties loadProperties(Path path) throws IOException {
        if (!Files.isRegularFile(path)) {
            throw new IOException("Missing wrapper properties: " + path);
        }
        Properties properties = new Properties();
        try (InputStream input = Files.newInputStream(path)) {
            properties.load(input);
        }
        return properties;
    }

    private static String require(Properties properties, String key) {
        String value = properties.getProperty(key);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Missing required property: " + key);
        }
        return value.trim();
    }

    private static int parseInt(String value, int fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return Math.max(1000, Integer.parseInt(value.trim()));
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static Path resolveGradleUserHome() {
        String env = System.getenv("GRADLE_USER_HOME");
        if (env != null && !env.isBlank()) {
            return Paths.get(env).toAbsolutePath().normalize();
        }
        return Paths.get(System.getProperty("user.home"), ".gradle").toAbsolutePath().normalize();
    }

    private static Path findGradleHome(Path root) throws IOException {
        try (var stream = Files.list(root)) {
            return stream
                    .filter(Files::isDirectory)
                    .filter(path -> Files.isRegularFile(path.resolve("bin/gradle"))
                            || Files.isRegularFile(path.resolve("bin/gradle.bat")))
                    .findFirst()
                    .orElse(null);
        }
    }

    private static void installDistribution(URL url, String expectedSha256, int timeout,
                                            String archiveName, Path distributionRoot) throws Exception {
        Path partial = distributionRoot.resolve(archiveName + ".part");
        Path archive = distributionRoot.resolve(archiveName);
        Path extractRoot = distributionRoot.resolve(".extracting");
        deleteRecursively(partial);
        deleteRecursively(extractRoot);
        Files.createDirectories(extractRoot);

        System.out.println("Downloading Gradle distribution: " + url);
        download(url, partial, timeout);
        String actualSha256 = sha256File(partial);
        if (!MessageDigest.isEqual(actualSha256.getBytes(java.nio.charset.StandardCharsets.US_ASCII),
                expectedSha256.getBytes(java.nio.charset.StandardCharsets.US_ASCII))) {
            Files.deleteIfExists(partial);
            throw new SecurityException("Gradle distribution SHA-256 mismatch. Expected "
                    + expectedSha256 + " but got " + actualSha256);
        }
        try {
            Files.move(partial, archive, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException atomicFailure) {
            Files.move(partial, archive, StandardCopyOption.REPLACE_EXISTING);
        }

        unzipSafely(archive, extractRoot);
        Path extractedHome = findGradleHome(extractRoot);
        if (extractedHome == null) {
            throw new IOException("Downloaded archive did not contain a Gradle home directory");
        }
        Path finalHome = distributionRoot.resolve(extractedHome.getFileName().toString());
        deleteRecursively(finalHome);
        try {
            Files.move(extractedHome, finalHome, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException atomicFailure) {
            Files.move(extractedHome, finalHome, StandardCopyOption.REPLACE_EXISTING);
        }
        deleteRecursively(extractRoot);
        Files.deleteIfExists(archive);
        Files.writeString(distributionRoot.resolve(".sha256"), actualSha256 + System.lineSeparator());
    }

    private static void download(URL initialUrl, Path target, int timeout) throws IOException {
        URL current = initialUrl;
        for (int redirects = 0; redirects < 8; redirects++) {
            HttpURLConnection connection = (HttpURLConnection) current.openConnection();
            connection.setConnectTimeout(timeout);
            connection.setReadTimeout(Math.max(timeout, 30000));
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("User-Agent", "JiuxiaoWendao-GradleBootstrap/1.0");
            int code = connection.getResponseCode();
            if (code >= 300 && code < 400) {
                String location = connection.getHeaderField("Location");
                connection.disconnect();
                if (location == null || location.isBlank()) {
                    throw new IOException("Redirect without Location from " + current);
                }
                current = new URL(current, location);
                continue;
            }
            if (code < 200 || code >= 300) {
                connection.disconnect();
                throw new IOException("HTTP " + code + " downloading " + current);
            }
            try (InputStream in = new BufferedInputStream(connection.getInputStream(), BUFFER_SIZE);
                 OutputStream out = new BufferedOutputStream(Files.newOutputStream(target,
                         StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING), BUFFER_SIZE)) {
                byte[] buffer = new byte[BUFFER_SIZE];
                int count;
                while ((count = in.read(buffer)) >= 0) {
                    if (count > 0) out.write(buffer, 0, count);
                }
            } finally {
                connection.disconnect();
            }
            return;
        }
        throw new IOException("Too many redirects downloading " + initialUrl);
    }

    private static void unzipSafely(Path archive, Path targetRoot) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(new BufferedInputStream(Files.newInputStream(archive), BUFFER_SIZE))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                Path output = targetRoot.resolve(entry.getName()).normalize();
                if (!output.startsWith(targetRoot)) {
                    throw new SecurityException("Unsafe ZIP entry: " + entry.getName());
                }
                if (entry.isDirectory()) {
                    Files.createDirectories(output);
                } else {
                    Files.createDirectories(output.getParent());
                    try (OutputStream out = new BufferedOutputStream(Files.newOutputStream(output,
                            StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING), BUFFER_SIZE)) {
                        byte[] buffer = new byte[BUFFER_SIZE];
                        int count;
                        while ((count = zip.read(buffer)) >= 0) {
                            if (count > 0) out.write(buffer, 0, count);
                        }
                    }
                }
                zip.closeEntry();
            }
        }
    }

    private static String sha256File(Path file) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = new BufferedInputStream(Files.newInputStream(file), BUFFER_SIZE)) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                if (count > 0) digest.update(buffer, 0, count);
            }
        }
        return HexFormat.of().formatHex(digest.digest());
    }

    private static String sha256Hex(byte[] data) throws NoSuchAlgorithmException {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
    }

    private static void deleteRecursively(Path path) throws IOException {
        if (path == null || !Files.exists(path)) return;
        if (Files.isDirectory(path)) {
            try (var stream = Files.list(path)) {
                for (Path child : stream.toList()) {
                    deleteRecursively(child);
                }
            }
        }
        Files.deleteIfExists(path);
    }
}
