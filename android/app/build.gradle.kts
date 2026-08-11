import java.util.Properties

plugins {
    id("com.android.application")
}

val appId = providers.gradleProperty("APP_ID").orElse("com.jiuxiaowendao.game").get()
val appVersionCode = providers.gradleProperty("APP_VERSION_CODE").orElse("2001512").get().toInt()
val appVersionName = providers.gradleProperty("APP_VERSION_NAME").orElse("2.2.0-cache133").get()
val githubOwner = providers.gradleProperty("GITHUB_OWNER").orElse("YOUR_GITHUB_NAME").get()
val githubRepo = providers.gradleProperty("GITHUB_REPO").orElse("YOUR_REPOSITORY").get()

fun quoted(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

val signingPropertiesFile = rootProject.file("signing.properties")
val signingProperties = Properties()
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

android {
    namespace = "com.jiuxiaowendao.game"
    compileSdk = 34

    defaultConfig {
        applicationId = appId
        minSdk = 24
        targetSdk = 34
        versionCode = appVersionCode
        versionName = appVersionName

        buildConfigField("String", "GITHUB_OWNER", quoted(githubOwner))
        buildConfigField("String", "GITHUB_REPO", quoted(githubRepo))
        buildConfigField("String", "SUPABASE_HOST", quoted("fyykkqkovccgmamsdeoq.supabase.co"))
        buildConfigField("String", "GAME_BUILD_ID", quoted("v2-2-0-cache135-b-ai-router-glm-admin39-sql263-gated"))
    }

    signingConfigs {
        if (signingPropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            buildConfigField("boolean", "AUTO_UPDATE_ENABLED", "false")
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            buildConfigField("boolean", "AUTO_UPDATE_ENABLED", "true")
            if (signingPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += setOf("META-INF/DEPENDENCIES", "META-INF/LICENSE*", "META-INF/NOTICE*")
        }
    }
}

dependencies {
    implementation("androidx.core:core:1.13.1")
    implementation("androidx.webkit:webkit:1.11.0")
}
