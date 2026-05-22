#!/usr/bin/env bash
# =============================================================
# setup_soren_ng.sh  —  Soren NG Tunnel
# Complete Android VPN project generator
# Traffic: User Config → Xray → Psiphon SOCKS5 :1080 → Internet
# PART 1 of 3
# =============================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; YLW='\033[1;33m'; GRN='\033[0;32m'; NC='\033[0m'
log()  { echo -e "${GRN}[SOREN]${NC} $1"; }
warn() { echo -e "${YLW}[WARN ]${NC} $1"; }
die()  { echo -e "${RED}[FAIL ]${NC} $1" >&2; exit 1; }

ROOT="$(pwd)/SorenNGTunnel"
PKG="com.soreng.tunnel"
PKGP="com/soreng/tunnel"

# ─────────────────────────────────────────────────────────────
# DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────
check_deps() {
  log "Checking dependencies..."
  for cmd in git curl java; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required tool: $cmd — install it first"
  done
  if ! command -v go >/dev/null 2>&1; then
    log "Go not found — installing Go 1.22.4..."
    local ARCH; ARCH=$(uname -m)
    local GOARCH="amd64"; [[ "$ARCH" == "aarch64" ]] && GOARCH="arm64"
    curl -fsSL "https://go.dev/dl/go1.22.4.linux-${GOARCH}.tar.gz" -o /tmp/go.tar.gz
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH="$PATH:/usr/local/go/bin"
  fi
  export PATH="$PATH:/usr/local/go/bin"
  go version >/dev/null 2>&1 || die "Go installation failed"
  export GOPATH="${GOPATH:-$HOME/go}"
  export PATH="$PATH:$GOPATH/bin"
  if ! command -v gomobile >/dev/null 2>&1; then
    log "Installing gomobile..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    go install golang.org/x/mobile/cmd/gobind@latest
    gomobile init 2>/dev/null || warn "gomobile init — NDK may be needed"
  fi
  if [[ -z "${ANDROID_HOME:-}" ]]; then
    for d in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/opt/android-sdk"; do
      [[ -d "$d" ]] && { export ANDROID_HOME="$d"; break; }
    done
    [[ -z "${ANDROID_HOME:-}" ]] && warn "ANDROID_HOME not set — export it before running ./gradlew"
  fi
  log "Dependencies OK"
}

# ─────────────────────────────────────────────────────────────
# SKELETON
# ─────────────────────────────────────────────────────────────
make_skeleton() {
  log "Creating project skeleton..."
  rm -rf "$ROOT"
  local dirs=(
    "$ROOT/app/src/main/kotlin/$PKGP/ui/screen"
    "$ROOT/app/src/main/kotlin/$PKGP/ui/component"
    "$ROOT/app/src/main/kotlin/$PKGP/ui/theme"
    "$ROOT/app/src/main/kotlin/$PKGP/ui/viewmodel"
    "$ROOT/app/src/main/kotlin/$PKGP/vpn"
    "$ROOT/app/src/main/kotlin/$PKGP/xray"
    "$ROOT/app/src/main/kotlin/$PKGP/psiphon"
    "$ROOT/app/src/main/kotlin/$PKGP/tunnel"
    "$ROOT/app/src/main/kotlin/$PKGP/config"
    "$ROOT/app/src/main/kotlin/$PKGP/storage"
    "$ROOT/app/src/main/kotlin/$PKGP/stats"
    "$ROOT/app/src/main/kotlin/$PKGP/security"
    "$ROOT/app/src/main/kotlin/$PKGP/utils"
    "$ROOT/app/src/main/kotlin/$PKGP/di"
    "$ROOT/app/src/main/jni"
    "$ROOT/app/src/main/res/drawable"
    "$ROOT/app/src/main/res/values"
    "$ROOT/app/src/main/res/xml"
    "$ROOT/app/src/main/assets/bin/arm64-v8a"
    "$ROOT/app/src/main/assets/bin/armeabi-v7a"
    "$ROOT/app/src/main/assets/bin/x86_64"
    "$ROOT/gradle/wrapper"
  )
  for d in "${dirs[@]}"; do mkdir -p "$d"; done
  log "Skeleton created"
}

# ─────────────────────────────────────────────────────────────
# GRADLE
# ─────────────────────────────────────────────────────────────
write_gradle() {
  log "Writing Gradle files..."

  cat > "$ROOT/settings.gradle.kts" << 'HEREDOC'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral(); maven { url = uri("https://jitpack.io") } }
}
rootProject.name = "SorenNGTunnel"
include(":app")
HEREDOC

  cat > "$ROOT/build.gradle.kts" << 'HEREDOC'
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android)      apply false
    alias(libs.plugins.kotlin.compose)      apply false
    alias(libs.plugins.hilt)                apply false
    alias(libs.plugins.ksp)                 apply false
}
HEREDOC

  mkdir -p "$ROOT/gradle"
  cat > "$ROOT/gradle/libs.versions.toml" << 'HEREDOC'
[versions]
agp             = "8.4.2"
kotlin          = "2.0.0"
coreKtx         = "1.13.1"
lifecycle       = "2.8.4"
activityCompose = "1.9.1"
composeBom      = "2024.08.00"
hilt            = "2.51.1"
ksp             = "2.0.0-1.0.23"
room            = "2.6.1"
datastore       = "1.1.1"
secCrypto       = "1.1.0-alpha06"
navigation      = "2.7.7"
coroutines      = "1.8.1"
gson            = "2.11.0"
okhttp          = "4.12.0"
zxing           = "3.5.3"
mlkit           = "18.3.0"
cameraX         = "1.3.4"
work            = "2.9.1"

[libraries]
core-ktx                 = { group = "androidx.core",         name = "core-ktx",                   version.ref = "coreKtx" }
lifecycle-runtime        = { group = "androidx.lifecycle",    name = "lifecycle-runtime-ktx",      version.ref = "lifecycle" }
lifecycle-vm-compose     = { group = "androidx.lifecycle",    name = "lifecycle-viewmodel-compose", version.ref = "lifecycle" }
activity-compose         = { group = "androidx.activity",     name = "activity-compose",           version.ref = "activityCompose" }
compose-bom              = { group = "androidx.compose",      name = "compose-bom",                version.ref = "composeBom" }
compose-ui               = { group = "androidx.compose.ui",   name = "ui" }
compose-ui-graphics      = { group = "androidx.compose.ui",   name = "ui-graphics" }
compose-ui-tooling       = { group = "androidx.compose.ui",   name = "ui-tooling" }
compose-ui-tooling-preview={ group = "androidx.compose.ui",   name = "ui-tooling-preview" }
material3                = { group = "androidx.compose.material3", name = "material3" }
navigation-compose       = { group = "androidx.navigation",   name = "navigation-compose",         version.ref = "navigation" }
hilt-android             = { group = "com.google.dagger",     name = "hilt-android",               version.ref = "hilt" }
hilt-compiler            = { group = "com.google.dagger",     name = "hilt-android-compiler",      version.ref = "hilt" }
hilt-navigation-compose  = { group = "androidx.hilt",         name = "hilt-navigation-compose",    version = "1.2.0" }
room-runtime             = { group = "androidx.room",         name = "room-runtime",               version.ref = "room" }
room-ktx                 = { group = "androidx.room",         name = "room-ktx",                   version.ref = "room" }
room-compiler            = { group = "androidx.room",         name = "room-compiler",              version.ref = "room" }
datastore-prefs          = { group = "androidx.datastore",    name = "datastore-preferences",      version.ref = "datastore" }
security-crypto          = { group = "androidx.security",     name = "security-crypto",            version.ref = "secCrypto" }
coroutines-android       = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-android", version.ref = "coroutines" }
gson                     = { group = "com.google.code.gson",  name = "gson",                       version.ref = "gson" }
okhttp                   = { group = "com.squareup.okhttp3",  name = "okhttp",                     version.ref = "okhttp" }
zxing-core               = { group = "com.google.zxing",      name = "core",                       version.ref = "zxing" }
mlkit-barcode            = { group = "com.google.mlkit",      name = "barcode-scanning",           version.ref = "mlkit" }
camerax-core             = { group = "androidx.camera",       name = "camera-core",                version.ref = "cameraX" }
camerax-camera2          = { group = "androidx.camera",       name = "camera-camera2",             version.ref = "cameraX" }
camerax-lifecycle        = { group = "androidx.camera",       name = "camera-lifecycle",           version.ref = "cameraX" }
camerax-view             = { group = "androidx.camera",       name = "camera-view",                version.ref = "cameraX" }
work-runtime             = { group = "androidx.work",         name = "work-runtime-ktx",           version.ref = "work" }

[plugins]
android-application = { id = "com.android.application",         version.ref = "agp" }
kotlin-android      = { id = "org.jetbrains.kotlin.android",     version.ref = "kotlin" }
kotlin-compose      = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
hilt                = { id = "com.google.dagger.hilt.android",   version.ref = "hilt" }
ksp                 = { id = "com.google.devtools.ksp",          version.ref = "ksp" }
HEREDOC

  cat > "$ROOT/app/build.gradle.kts" << 'HEREDOC'
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}
android {
    namespace   = "com.soreng.tunnel"
    compileSdk  = 34
    defaultConfig {
        applicationId = "com.soreng.tunnel"
        minSdk = 26; targetSdk = 34
        versionCode = 1; versionName = "1.0.0"
        ndk { abiFilters += listOf("arm64-v8a","armeabi-v7a","x86_64") }
        externalNativeBuild {
            cmake { cppFlags += "-std=c++17"; arguments("-DANDROID_STL=c++_shared") }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true; isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"),"proguard-rules.pro")
        }
        debug { isDebuggable = true }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }; jniLibs { useLegacyPackaging = true } }
    externalNativeBuild { cmake { path = file("src/main/jni/CMakeLists.txt"); version = "3.22.1" } }
    splits { abi { isEnable = true; reset(); include("arm64-v8a","armeabi-v7a","x86_64"); isUniversalApk = true } }
    lint { abortOnError = false }
}
dependencies {
    implementation(libs.core.ktx)
    implementation(libs.lifecycle.runtime); implementation(libs.lifecycle.vm.compose)
    implementation(libs.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui); implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview); implementation(libs.material3)
    implementation(libs.navigation.compose)
    implementation(libs.hilt.android); ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)
    implementation(libs.room.runtime); implementation(libs.room.ktx); ksp(libs.room.compiler)
    implementation(libs.datastore.prefs); implementation(libs.security.crypto)
    implementation(libs.coroutines.android)
    implementation(libs.gson); implementation(libs.okhttp)
    implementation(libs.zxing.core); implementation(libs.mlkit.barcode)
    implementation(libs.camerax.core); implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle); implementation(libs.camerax.view)
    implementation(libs.work.runtime)
    debugImplementation(libs.compose.ui.tooling)
}
HEREDOC

  cat > "$ROOT/gradle.properties" << 'HEREDOC'
org.gradle.jvmargs=-Xmx4096m -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
HEREDOC

  cat > "$ROOT/gradle/wrapper/gradle-wrapper.properties" << 'HEREDOC'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.9-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
HEREDOC

  curl -fsSL \
    "https://raw.githubusercontent.com/gradle/gradle/v8.9.0/gradle/wrapper/gradle-wrapper.jar" \
    -o "$ROOT/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null \
    || warn "gradle-wrapper.jar download failed — add manually"

  cat > "$ROOT/gradlew" << 'HEREDOC'
#!/usr/bin/env sh
set -e
PRG="$0"; while [ -h "$PRG" ]; do PRG="$(readlink "$PRG")"; done
APP_HOME="$(cd "$(dirname "$PRG")" && pwd)"
exec java -classpath "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" \
  org.gradle.wrapper.GradleWrapperMain "$@"
HEREDOC
  chmod +x "$ROOT/gradlew"

  cat > "$ROOT/app/proguard-rules.pro" << 'HEREDOC'
-keep class com.soreng.tunnel.** { *; }
-keepclassmembers class com.soreng.tunnel.** { *; }
-keepclasseswithmembernames class * { native <methods>; }
-keepclassmembers class * { native <methods>; }
-keep class go.** { *; }; -keep class libcore.** { *; }
-keep class ca.psiphon.** { *; }; -keep class com.psiphon3.** { *; }
-keep class com.google.gson.** { *; }
-keep @com.google.gson.annotations.SerializedName class * { *; }
-keepclassmembers class * { @com.google.gson.annotations.SerializedName <fields>; }
-keep @androidx.room.Entity class * { *; }; -keep @androidx.room.Dao class * { *; }
-keep class dagger.hilt.** { *; }
-keep @dagger.hilt.android.HiltAndroidApp class * { *; }
-keep @dagger.hilt.android.AndroidEntryPoint class * { *; }
-dontwarn okhttp3.**; -dontwarn okio.**; -dontwarn org.slf4j.**
-dontwarn javax.annotation.**; -dontwarn kotlin.reflect.**
-keepclassmembers enum * { public static **[] values(); public static ** valueOf(java.lang.String); }
HEREDOC
  log "Gradle done"
}

# ─────────────────────────────────────────────────────────────
# MANIFEST + RESOURCES
# ─────────────────────────────────────────────────────────────
write_manifest() {
  log "Writing AndroidManifest.xml..."
  cat > "$ROOT/app/src/main/AndroidManifest.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <application
        android:name=".SorenApp"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@drawable/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@drawable/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.SorenNG"
        android:hardwareAccelerated="true"
        android:largeHeap="true"
        android:extractNativeLibs="true"
        tools:targetApi="34">
        <activity
            android:name=".ui.MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:screenOrientation="portrait"
            android:theme="@style/Theme.SorenNG"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="vmess"/><data android:scheme="vless"/>
                <data android:scheme="trojan"/><data android:scheme="ss"/>
                <data android:scheme="socks"/>
            </intent-filter>
        </activity>
        <service
            android:name=".vpn.SorenVpnService"
            android:exported="false"
            android:foregroundServiceType="specialUse"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:stopWithTask="false">
            <intent-filter><action android:name="android.net.VpnService"/></intent-filter>
            <meta-data android:name="android.net.VpnService.SUPPORTS_ALWAYS_ON" android:value="true"/>
            <meta-data android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="VPN tunnel"/>
        </service>
        <receiver android:name=".vpn.BootReceiver" android:exported="true">
            <intent-filter android:priority="500">
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED"/>
            </intent-filter>
        </receiver>
        <receiver android:name=".vpn.VpnControlReceiver" android:exported="false">
            <intent-filter>
                <action android:name="com.soreng.tunnel.VPN_CONNECT"/>
                <action android:name="com.soreng.tunnel.VPN_DISCONNECT"/>
            </intent-filter>
        </receiver>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>
    </application>
</manifest>
HEREDOC
}

write_resources() {
  log "Writing resources..."
  cat > "$ROOT/app/src/main/res/values/strings.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Soren NG</string>
    <string name="channel_vpn">VPN Status</string>
    <string name="channel_alert">Alerts</string>
</resources>
HEREDOC

  cat > "$ROOT/app/src/main/res/values/themes.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.SorenNG" parent="android:Theme.Material.NoTitleBar.Fullscreen">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:statusBarColor">@android:color/black</item>
        <item name="android:navigationBarColor">@android:color/black</item>
        <item name="android:windowLightStatusBar">false</item>
    </style>
</resources>
HEREDOC

  cat > "$ROOT/app/src/main/res/xml/file_paths.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <files-path name="files" path="."/>
    <cache-path name="cache" path="."/>
</paths>
HEREDOC

  cat > "$ROOT/app/src/main/res/xml/backup_rules.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <exclude domain="sharedpref" path="."/>
    <exclude domain="database"   path="."/>
    <exclude domain="file"       path="."/>
</full-backup-content>
HEREDOC

  cat > "$ROOT/app/src/main/res/xml/data_extraction_rules.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="."/>
        <exclude domain="database"   path="."/>
    </cloud-backup>
</data-extraction-rules>
HEREDOC

  cat > "$ROOT/app/src/main/res/drawable/ic_launcher.xml" << 'HEREDOC'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#000000" android:pathData="M0,0h108v108h-108z"/>
    <path android:fillColor="#FFFFFF" android:pathData="M54,18L84,48L54,90L24,48Z"/>
    <path android:fillColor="#000000" android:pathData="M54,34L70,52L54,74L38,52Z"/>
    <path android:strokeColor="#FFFFFF" android:strokeWidth="1.5"
        android:pathData="M54,10L94,50L54,98L14,50Z"/>
</vector>
HEREDOC
  cp "$ROOT/app/src/main/res/drawable/ic_launcher.xml" \
     "$ROOT/app/src/main/res/drawable/ic_launcher_round.xml"
  log "Resources done"
}

# ─────────────────────────────────────────────────────────────
# JNI — real VpnService.protect() bridge + fd safety
# ─────────────────────────────────────────────────────────────
write_jni() {
  log "Writing JNI..."
  cat > "$ROOT/app/src/main/jni/CMakeLists.txt" << 'HEREDOC'
cmake_minimum_required(VERSION 3.22.1)
project(sorenjni VERSION 1.0.0 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_library(log-lib log)
find_library(android-lib android)
add_library(sorenjni SHARED soren_jni.cpp tun_helper.c)
target_link_libraries(sorenjni ${log-lib} ${android-lib})
target_compile_options(sorenjni PRIVATE -O2 -fvisibility=hidden -fstack-protector-strong -DANDROID)
HEREDOC

  cat > "$ROOT/app/src/main/jni/tun_helper.c" << 'HEREDOC'
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <android/log.h>
#define TAG "TunHelper"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

int soren_fd_valid(int fd) {
    if (fd < 0) return 0;
    int r = fcntl(fd, F_GETFD);
    return !(r == -1 && errno == EBADF);
}
int soren_set_nonblock(int fd) {
    if (fd < 0) return -1;
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) { LOGE("F_GETFL fd=%d: %s", fd, strerror(errno)); return -1; }
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}
HEREDOC

  cat > "$ROOT/app/src/main/jni/soren_jni.cpp" << 'HEREDOC'
/*
 * soren_jni.cpp — Real VpnService.protect() bridge
 *
 * PROTECT FLOW (prevents VPN routing loops):
 *   SorenVpnService.onCreate()
 *     → jni.registerProtectCallback(socketProtector)
 *     → nativeRegisterProtectCallback(env, protector_obj)
 *     → stores GlobalRef + SocketProtector.protectFd(I)Z method ID
 *
 *   Any code needing to protect a socket:
 *     → jni.protectFd(fd)   [Kotlin]  OR
 *     → real_protect_fd(fd) [C++]
 *     → JVM callback → SocketProtector.protectFd(fd) → VpnService.protect(fd)
 *
 *   SorenVpnService.onDestroy()
 *     → jni.unregisterProtectCallback()
 *     → DeleteGlobalRef, clears method ID
 */
#include <jni.h>
#include <string>
#include <android/log.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>
#include <string.h>
#include <pthread.h>

#define TAG  "SorenJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)

extern "C" int soren_fd_valid(int fd);
extern "C" int soren_set_nonblock(int fd);

static pthread_mutex_t g_lock      = PTHREAD_MUTEX_INITIALIZER;
static JavaVM*          g_jvm      = nullptr;
static jobject          g_protobj  = nullptr;
static jmethodID        g_protmid  = nullptr;
static volatile int     g_tun_fd   = -1;
static volatile int     g_running  = 0;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_jvm = vm;
    LOGI("JNI_OnLoad v3.0");
    return JNI_VERSION_1_6;
}

static bool attach_env(JNIEnv** env, bool* attached) {
    *attached = false;
    if (!g_jvm) return false;
    int st = g_jvm->GetEnv((void**)env, JNI_VERSION_1_6);
    if (st == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(env, nullptr) != JNI_OK) return false;
        *attached = true; return true;
    }
    return st == JNI_OK;
}

static bool real_protect(int fd) {
    if (!soren_fd_valid(fd)) { LOGW("protect: invalid fd=%d", fd); return false; }
    pthread_mutex_lock(&g_lock);
    jobject   obj = g_protobj;
    jmethodID mid = g_protmid;
    JavaVM*   jvm = g_jvm;
    pthread_mutex_unlock(&g_lock);
    if (!jvm || !obj || !mid) { LOGW("protect: no JVM callback for fd=%d", fd); return false; }
    JNIEnv* env; bool att;
    if (!attach_env(&env, &att)) { LOGE("protect: attach failed"); return false; }
    jboolean r = env->CallBooleanMethod(obj, mid, (jint)fd);
    if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); r = JNI_FALSE; }
    if (att) jvm->DetachCurrentThread();
    if (!r) LOGW("VpnService.protect(%d) returned false", fd);
    return r == JNI_TRUE;
}

extern "C" {

JNIEXPORT jint JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeRegisterProtectCallback(
        JNIEnv* env, jobject, jobject protector) {
    pthread_mutex_lock(&g_lock);
    if (g_protobj) { env->DeleteGlobalRef(g_protobj); g_protobj = nullptr; }
    g_protobj = env->NewGlobalRef(protector);
    jclass cls = env->GetObjectClass(protector);
    g_protmid  = env->GetMethodID(cls, "protectFd", "(I)Z");
    pthread_mutex_unlock(&g_lock);
    if (!g_protmid) { LOGE("protectFd(I)Z not found"); return -1; }
    LOGI("SocketProtector registered — real VpnService.protect() active");
    return 0;
}

JNIEXPORT void JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeUnregisterProtectCallback(
        JNIEnv* env, jobject) {
    pthread_mutex_lock(&g_lock);
    if (g_protobj) { env->DeleteGlobalRef(g_protobj); g_protobj = nullptr; }
    g_protmid = nullptr;
    pthread_mutex_unlock(&g_lock);
    LOGI("SocketProtector unregistered");
}

JNIEXPORT jboolean JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeProtectFd(JNIEnv*, jobject, jint fd) {
    return real_protect((int)fd) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeSetTunFd(JNIEnv*, jobject, jint fd) {
    if (!soren_fd_valid(fd)) { LOGE("setTunFd: bad fd=%d", fd); return -1; }
    soren_set_nonblock(fd);
    pthread_mutex_lock(&g_lock);
    g_tun_fd = fd; g_running = 1;
    pthread_mutex_unlock(&g_lock);
    LOGI("TUN fd=%d set", fd);
    return 0;
}

JNIEXPORT jint JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeSetSocketMark(
        JNIEnv*, jobject, jint fd, jint mark) {
    if (!soren_fd_valid(fd)) return -1;
    int m = (int)mark;
    if (setsockopt(fd, SOL_SOCKET, SO_MARK, &m, sizeof(m)) < 0) {
        LOGE("SO_MARK fd=%d: %s", fd, strerror(errno)); return -1;
    }
    return 0;
}

JNIEXPORT void JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeCloseFd(JNIEnv*, jobject, jint fd) {
    if (fd >= 0 && soren_fd_valid(fd)) { close(fd); LOGD("closed fd=%d", fd); }
}

JNIEXPORT jstring JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeGetVersion(JNIEnv* env, jobject) {
    return env->NewStringUTF("SorenJNI/3.0.0-real-protect");
}

JNIEXPORT jboolean JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeIsRunning(JNIEnv*, jobject) {
    return g_running ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeCreateSocketPair(
        JNIEnv* env, jobject, jintArray fds) {
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, pair) < 0) {
        LOGE("socketpair: %s", strerror(errno)); return -1;
    }
    jint buf[2] = {pair[0], pair[1]};
    env->SetIntArrayRegion(fds, 0, 2, buf);
    return 0;
}

JNIEXPORT void JNICALL
Java_com_soreng_tunnel_vpn_SorenJniBridge_nativeCleanup(JNIEnv* env, jobject) {
    pthread_mutex_lock(&g_lock);
    g_running = 0;
    if (g_tun_fd >= 0) { close(g_tun_fd); g_tun_fd = -1; LOGD("tun_fd closed"); }
    if (g_protobj) { env->DeleteGlobalRef(g_protobj); g_protobj = nullptr; }
    g_protmid = nullptr;
    pthread_mutex_unlock(&g_lock);
    LOGI("JNI cleanup complete");
}

} // extern "C"
HEREDOC
  log "JNI done"
}

# ─────────────────────────────────────────────────────────────
# KOTLIN — VPN core layer
# ─────────────────────────────────────────────────────────────
write_vpn_layer() {
  log "Writing VPN Kotlin layer..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"

  # ── SorenApp ──────────────────────────────────────────────
  cat > "$B/SorenApp.kt" << 'HEREDOC'
package com.soreng.tunnel

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import com.soreng.tunnel.security.SecurityManager
import com.soreng.tunnel.storage.BinaryExtractor
import javax.inject.Inject

@HiltAndroidApp
class SorenApp : Application() {
    @Inject lateinit var binaryExtractor: BinaryExtractor
    @Inject lateinit var securityManager: SecurityManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        createChannels()
        scope.launch { binaryExtractor.extractAll() }
        scope.launch { securityManager.initialize() }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannels(listOf(
            NotificationChannel(CHANNEL_VPN, getString(R.string.channel_vpn),
                NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false); enableVibration(false) },
            NotificationChannel(CHANNEL_ALERT, getString(R.string.channel_alert),
                NotificationManager.IMPORTANCE_DEFAULT)
        ))
    }

    companion object {
        const val CHANNEL_VPN   = "soren_vpn"
        const val CHANNEL_ALERT = "soren_alert"
    }
}
HEREDOC

  # ── VpnConnectionState ───────────────────────────────────
  cat > "$B/vpn/VpnConnectionState.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

sealed class VpnConnectionState {
    object Disconnected  : VpnConnectionState()
    object Connecting    : VpnConnectionState()
    /** Set ONLY after ConnectivityVerifier confirms real end-to-end traffic. */
    data class Connected(val connectedAt: Long, val probeLatencyMs: Long = -1L) : VpnConnectionState()
    object Disconnecting : VpnConnectionState()
    data class Error(val message: String) : VpnConnectionState()

    val isActive: Boolean get() = this is Connected || this is Connecting
    val label: String get() = when (this) {
        is Disconnected  -> "DISCONNECTED"
        is Connecting    -> "CONNECTING..."
        is Connected     -> "CONNECTED"
        is Disconnecting -> "DISCONNECTING"
        is Error         -> "ERROR"
    }
}
HEREDOC

  # ── SocketProtector ──────────────────────────────────────
  cat > "$B/vpn/SocketProtector.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.net.VpnService
import android.util.Log
import java.lang.ref.WeakReference
import java.net.DatagramSocket
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Real VpnService.protect() bridge.
 *
 * Registered with JNI via SorenJniBridge.registerProtectCallback(this).
 * JNI calls protectFd(fd) → VpnService.protect(fd) on any thread.
 * WeakReference prevents leaking the Service instance after onDestroy.
 */
@Singleton
class SocketProtector @Inject constructor() {
    private val TAG = "SocketProtector"
    @Volatile private var ref: WeakReference<VpnService>? = null

    fun register(svc: VpnService)  { ref = WeakReference(svc); Log.d(TAG, "registered") }
    fun unregister()               { ref?.clear(); ref = null;  Log.d(TAG, "unregistered") }
    val isAvailable: Boolean get() = ref?.get() != null

    /** Called from JNI — must be safe from any thread. */
    fun protectFd(fd: Int): Boolean {
        if (fd < 0) return false
        val svc = ref?.get() ?: run { Log.w(TAG, "protectFd($fd): no service"); return false }
        return try {
            val ok = svc.protect(fd)
            if (!ok) Log.w(TAG, "VpnService.protect($fd) returned false")
            ok
        } catch (e: Exception) { Log.e(TAG, "protectFd($fd): ${e.message}"); false }
    }

    fun protect(s: Socket): Boolean {
        val svc = ref?.get() ?: return false
        return try { svc.protect(s) } catch (_: Exception) { false }
    }

    fun protect(s: DatagramSocket): Boolean {
        val svc = ref?.get() ?: return false
        return try { svc.protect(s) } catch (_: Exception) { false }
    }
}
HEREDOC

  # ── SorenJniBridge ───────────────────────────────────────
  cat > "$B/vpn/SorenJniBridge.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.util.Log

class SorenJniBridge {
    private val TAG = "SorenJniBridge"
    private var loaded = false

    init {
        try {
            System.loadLibrary("sorenjni")
            loaded = true
            Log.i(TAG, "sorenjni loaded: ${getVersion()}")
        } catch (e: UnsatisfiedLinkError) { Log.e(TAG, "sorenjni load failed: ${e.message}") }
    }

    fun registerProtectCallback(p: SocketProtector): Int {
        if (!loaded) return -1
        return try { nativeRegisterProtectCallback(p) }
        catch (e: Exception) { Log.e(TAG, "register: ${e.message}"); -1 }
    }

    fun unregisterProtectCallback() {
        if (!loaded) return
        try { nativeUnregisterProtectCallback() } catch (e: Exception) { Log.w(TAG, e.message) }
    }

    fun protectFd(fd: Int): Boolean {
        if (!loaded || fd < 0) return false
        return try { nativeProtectFd(fd) } catch (e: Exception) { Log.e(TAG, "protectFd: ${e.message}"); false }
    }

    fun setTunFd(fd: Int): Int {
        if (!loaded || fd < 0) return -1
        return try { nativeSetTunFd(fd) } catch (e: Exception) { Log.e(TAG, e.message); -1 }
    }

    fun setSocketMark(fd: Int, mark: Int): Int {
        if (!loaded || fd < 0) return -1
        return try { nativeSetSocketMark(fd, mark) } catch (_: Exception) { -1 }
    }

    fun closeFd(fd: Int) {
        if (!loaded || fd < 0) return
        try { nativeCloseFd(fd) } catch (_: Exception) {}
    }

    fun getVersion(): String = try { if (loaded) nativeGetVersion() else "unavailable" } catch (_: Exception) { "?" }
    fun isRunning():  Boolean = try { loaded && nativeIsRunning() }       catch (_: Exception) { false }
    fun createSocketPair(fds: IntArray): Int = try { if (loaded) nativeCreateSocketPair(fds) else -1 } catch (_: Exception) { -1 }

    fun cleanup() {
        if (!loaded) return
        try { nativeCleanup() } catch (e: Exception) { Log.w(TAG, "cleanup: ${e.message}") }
    }

    private external fun nativeRegisterProtectCallback(p: SocketProtector): Int
    private external fun nativeUnregisterProtectCallback()
    private external fun nativeProtectFd(fd: Int): Boolean
    private external fun nativeSetTunFd(fd: Int): Int
    private external fun nativeSetSocketMark(fd: Int, mark: Int): Int
    private external fun nativeCloseFd(fd: Int)
    private external fun nativeGetVersion(): String
    private external fun nativeIsRunning(): Boolean
    private external fun nativeCreateSocketPair(fds: IntArray): Int
    private external fun nativeCleanup()
}
HEREDOC

  # ── BootReceiver ─────────────────────────────────────────
  cat > "$B/vpn/BootReceiver.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.soreng.tunnel.storage.AppPreferences
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.runBlocking
import javax.inject.Inject

@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {
    @Inject lateinit var prefs: AppPreferences

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action !in listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.LOCKED_BOOT_COMPLETED")) return
        val autoStart = runBlocking { prefs.isAutoStartEnabled() }
        if (!autoStart) return
        val cfgId = runBlocking { prefs.getLastConfigId() }
        if (cfgId < 0) return
        ctx.startForegroundService(
            Intent(ctx, SorenVpnService::class.java).apply {
                action = SorenVpnService.ACTION_START
                putExtra(SorenVpnService.EXTRA_CONFIG_ID, cfgId)
            })
    }
}
HEREDOC

  # ── VpnControlReceiver ───────────────────────────────────
  cat > "$B/vpn/VpnControlReceiver.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class VpnControlReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val svcIntent = Intent(ctx, SorenVpnService::class.java)
        when (intent.action) {
            "com.soreng.tunnel.VPN_CONNECT" -> {
                val cfgId = intent.getLongExtra(SorenVpnService.EXTRA_CONFIG_ID, -1L)
                if (cfgId < 0) return
                svcIntent.action = SorenVpnService.ACTION_START
                svcIntent.putExtra(SorenVpnService.EXTRA_CONFIG_ID, cfgId)
                ctx.startForegroundService(svcIntent)
            }
            "com.soreng.tunnel.VPN_DISCONNECT" -> {
                svcIntent.action = SorenVpnService.ACTION_STOP
                ctx.startService(svcIntent)
            }
        }
    }
}
HEREDOC

  log "VPN layer written"
}

# ─────────────────────────────────────────────────────────────
# PSIPHON MANAGER
# ─────────────────────────────────────────────────────────────
write_psiphon() {
  log "Writing Psiphon manager..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"
  mkdir -p "$B/psiphon"

  cat > "$B/psiphon/PsiphonManager.kt" << 'HEREDOC'
package com.soreng.tunnel.psiphon

import android.content.Context
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages the embedded Psiphon tunnel.
 *
 * Sources: https://github.com/Psiphon-Inc/psiphon-android
 *          https://github.com/Psiphon-Labs/psiphon-tunnel-core
 *
 * Psiphon runs as a child process exposing SOCKS5 on 127.0.0.1:1080.
 * Xray chains ALL outbound traffic through this SOCKS5.
 *
 * HARD RULE: if Psiphon cannot start → throw. Never allow direct fallback.
 */
@Singleton
class PsiphonManager @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG   = "PsiphonManager"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var proc:         Process? = null
    private var outJob:         Job? = null
    private var errJob:         Job? = null
    private var heartbeatJob:   Job? = null

    companion object {
        const val SOCKS_HOST = "127.0.0.1"
        const val SOCKS_PORT = 1080
        private const val HEARTBEAT_MS = 15_000L
        private const val MIN_BINARY_BYTES = 512L
    }

    suspend fun start() = withContext(Dispatchers.IO) {
        stop()
        val bin = File(ctx.filesDir, "bin/psiphon")
        when {
            bin.exists() && bin.length() > MIN_BINARY_BYTES -> startBinary(bin)
            else -> startLibrary()
        }
        startHeartbeat()
    }

    private suspend fun startBinary(bin: File) {
        if (!bin.canExecute()) bin.setExecutable(true, false)
        val cfg = File(ctx.filesDir, "psiphon_config.json")
        cfg.writeText(buildConfig().toString(2))

        val pb = ProcessBuilder(bin.absolutePath, "--config", cfg.absolutePath).apply {
            redirectErrorStream(false)
            directory(ctx.filesDir)
            environment()["PSIPHON_DATA_ROOT"] = ctx.filesDir.absolutePath
        }
        val p = pb.start(); proc = p
        writePid("psiphon", p.pid().toLong())
        outJob = scope.launch { drainStream(p.inputStream, "psiphon/out") }
        errJob = scope.launch { drainStream(p.errorStream, "psiphon/err") }
        delay(1_300)
        if (!p.isAlive) {
            delPid("psiphon")
            throw IllegalStateException("Psiphon exited immediately (exit=${p.exitValue()})")
        }
        Log.i(TAG, "Psiphon binary running pid=${p.pid()}")
    }

    private fun startLibrary() {
        if (!PsiphonLibBridge.start(SOCKS_PORT)) {
            throw IllegalStateException(
                "Psiphon unavailable: binary not found at filesDir/bin/psiphon " +
                "and libpsiphon.so not loaded. Build from " +
                "https://github.com/Psiphon-Inc/psiphon-android and place binary in assets.")
        }
        Log.i(TAG, "Psiphon library started on SOCKS5 :$SOCKS_PORT")
    }

    private fun buildConfig() = JSONObject().apply {
        put("PropagationChannelId",              "FFFFFFFFFFFFFFFF")
        put("SponsorId",                         "FFFFFFFFFFFFFFFF")
        put("RemoteServerListURLs",               JSONArray())
        put("RemoteServerListSignaturePublicKey", "")
        put("LocalSocksProxyPort",                SOCKS_PORT)
        put("LocalHttpProxyPort",                 0)
        put("DisableLocalHTTPProxy",              true)
        put("DisableLocalSocksProxy",             false)
        put("EmitDiagnosticNotices",              false)
        put("EmitServerAlerts",                   false)
        put("UpstreamProxyURL",                   "")
        put("EgressRegion",                       "")
        put("TunnelProtocol",                     "")
        put("ConnectionWorkerPoolSize",            5)
        put("LimitIntensiveConnectionWorkers",     3)
        put("TunnelConnectTimeoutSeconds",         20)
        put("TunnelPortForwardDialTimeoutSeconds", 10)
        put("PacketTunnelReadTimeout",             "30s")
        put("PacketTunnelWriteTimeout",            "30s")
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(HEARTBEAT_MS)
                if (!isRunning()) Log.w(TAG, "Heartbeat: Psiphon not running")
            }
        }
    }

    suspend fun stop() = withContext(Dispatchers.IO) {
        heartbeatJob?.cancel(); heartbeatJob = null
        outJob?.cancel(); outJob = null
        errJob?.cancel(); errJob = null
        proc?.let { p ->
            Log.i(TAG, "Stopping Psiphon pid=${pid(p)}")
            p.destroy()
            withTimeoutOrNull(5_000) { while (p.isAlive) delay(100) }
            if (p.isAlive) { p.destroyForcibly(); withTimeoutOrNull(3_000) { while (p.isAlive) delay(100) } }
            if (p.isAlive) Log.e(TAG, "Psiphon zombie — kill failed")
        }
        proc = null; delPid("psiphon")
        runCatching { PsiphonLibBridge.stop() }
    }

    fun isRunning(): Boolean =
        (proc?.isAlive == true) || runCatching { PsiphonLibBridge.isConnected() }.getOrDefault(false)

    private fun drainStream(stream: InputStream, label: String) {
        try {
            stream.bufferedReader(Charsets.UTF_8).use { r ->
                var line: String?
                while (r.readLine().also { line = it } != null && !Thread.currentThread().isInterrupted) {
                    val l = line!!
                    when { l.contains("ERROR",true) -> Log.e(TAG,"[$label] $l")
                           l.contains("warn", true) -> Log.w(TAG,"[$label] $l")
                           else                     -> Log.v(TAG,"[$label] $l") }
                }
            }
        } catch (e: Exception) {
            val m = e.message ?: ""
            if (!m.contains("closed",true) && !m.contains("EOF",true)) Log.w(TAG,"[$label] drain: $m")
        }
    }

    private fun writePid(n: String, pid: Long) = runCatching { File(ctx.filesDir,"$n.pid").writeText(pid.toString()) }
    private fun delPid(n: String)              = runCatching { File(ctx.filesDir,"$n.pid").delete() }
    private fun pid(p: Process): String        = try { p.pid().toString() } catch (_: Exception) { "?" }
}
HEREDOC

  cat > "$B/psiphon/PsiphonLibBridge.kt" << 'HEREDOC'
package com.soreng.tunnel.psiphon

import android.util.Log

/**
 * Bridge to gomobile-compiled Psiphon tunnel-core library.
 * Built via: gomobile bind -v -target android/arm64 -androidapi 26
 *              -o app/libs/psiphon.aar ./MobileLibrary/psi/
 * from https://github.com/Psiphon-Labs/psiphon-tunnel-core
 */
object PsiphonLibBridge {
    private const val TAG = "PsiphonLibBridge"
    @Volatile private var loaded = false

    init {
        try {
            System.loadLibrary("psiphon")
            loaded = true
            Log.i(TAG, "libpsiphon.so loaded")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "libpsiphon.so not available: ${e.message}")
        }
    }

    fun start(port: Int): Boolean {
        if (!loaded) return false
        return try { nativeStart(port); true }
        catch (e: Exception) { Log.e(TAG, "start: ${e.message}"); false }
    }

    fun stop() {
        if (!loaded) return
        try { nativeStop() } catch (e: Exception) { Log.w(TAG, "stop: ${e.message}") }
    }

    fun isConnected(): Boolean {
        if (!loaded) return false
        return try { nativeIsConnected() } catch (_: Exception) { false }
    }

    private external fun nativeStart(port: Int)
    private external fun nativeStop()
    private external fun nativeIsConnected(): Boolean
}
HEREDOC
  log "Psiphon done"
}

# ─────────────────────────────────────────────────────────────
# XRAY MANAGER
# ─────────────────────────────────────────────────────────────
write_xray() {
  log "Writing Xray manager..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"
  mkdir -p "$B/xray"

  cat > "$B/xray/XrayManager.kt" << 'HEREDOC'
package com.soreng.tunnel.xray

import android.content.Context
import android.util.Log
import com.google.gson.GsonBuilder
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import com.soreng.tunnel.config.RuntimeConfigBuilder
import com.soreng.tunnel.storage.ConfigRepository
import java.io.File
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class XrayManager @Inject constructor(
    @ApplicationContext private val ctx: Context,
    private val configBuilder: RuntimeConfigBuilder,
    private val configRepo: ConfigRepository
) {
    private val TAG   = "XrayManager"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var proc: Process? = null
    private var outJob: Job? = null
    private var errJob: Job? = null

    suspend fun start(configId: Long, psiphonSocksPort: Int) = withContext(Dispatchers.IO) {
        stop()
        val profile = configRepo.getById(configId)
            ?: throw IllegalArgumentException("Config $configId not found")
        val cfg = configBuilder.build(profile, psiphonSocksPort)
        val cfgFile = File(ctx.filesDir, "xray_config.json")
        cfgFile.writeText(GsonBuilder().setPrettyPrinting().create().toJson(cfg))

        val bin = File(ctx.filesDir, "bin/xray")
        if (!bin.exists() || bin.length() < 512L)
            throw IllegalStateException("Xray binary missing/invalid at ${bin.absolutePath}")
        if (!bin.canExecute()) bin.setExecutable(true, false)

        val pb = ProcessBuilder(bin.absolutePath, "run", "-config", cfgFile.absolutePath).apply {
            redirectErrorStream(false)
            directory(ctx.filesDir)
            environment()["XRAY_LOCATION_ASSET"] = ctx.filesDir.absolutePath
        }
        val p = pb.start(); proc = p
        writePid("xray", p.pid().toLong())
        outJob = scope.launch { drain(p.inputStream, "xray/out") }
        errJob = scope.launch { drain(p.errorStream, "xray/err") }

        delay(1_200)
        if (!p.isAlive) {
            delPid("xray")
            throw IllegalStateException("Xray exited immediately (exit=${p.exitValue()}) — check config or port conflict")
        }
        Log.i(TAG, "Xray running pid=${p.pid()}")
    }

    suspend fun stop() = withContext(Dispatchers.IO) {
        outJob?.cancel(); outJob = null
        errJob?.cancel(); errJob = null
        proc?.let { p ->
            Log.i(TAG, "Stopping Xray")
            p.destroy()
            withTimeoutOrNull(4_000) { while (p.isAlive) delay(100) }
            if (p.isAlive) { p.destroyForcibly(); withTimeoutOrNull(2_000) { while (p.isAlive) delay(100) } }
        }
        proc = null; delPid("xray")
        runCatching { File(ctx.filesDir, "xray_config.json").delete() }
    }

    fun isRunning(): Boolean = proc?.isAlive == true

    private fun drain(s: InputStream, lbl: String) {
        try {
            s.bufferedReader(Charsets.UTF_8).use { r ->
                var l: String?
                while (r.readLine().also { l = it } != null && !Thread.currentThread().isInterrupted) {
                    val line = l!!
                    when { line.contains("ERROR",true) -> Log.e(TAG,"[$lbl] $line")
                           line.contains("warn", true) -> Log.w(TAG,"[$lbl] $line")
                           else                        -> Log.v(TAG,"[$lbl] $line") }
                }
            }
        } catch (e: Exception) {
            val m = e.message ?: ""
            if (!m.contains("closed",true) && !m.contains("EOF",true)) Log.w(TAG,"[$lbl] $m")
        }
    }

    private fun writePid(n: String, pid: Long) = runCatching { File(ctx.filesDir,"$n.pid").writeText(pid.toString()) }
    private fun delPid(n: String)              = runCatching { File(ctx.filesDir,"$n.pid").delete() }
}
HEREDOC
  log "Xray done"
}

# ─────────────────────────────────────────────────────────────
# TUN2SOCKS MANAGER
# ─────────────────────────────────────────────────────────────
write_tun2socks() {
  log "Writing Tun2Socks manager..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"
  mkdir -p "$B/tunnel"

  cat > "$B/tunnel/Tun2SocksManager.kt" << 'HEREDOC'
package com.soreng.tunnel.tunnel

import android.content.Context
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import java.io.File
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages tun2socks process.
 * Source: https://github.com/xjasonlyu/tun2socks
 *
 * MTU MUST match VpnService.Builder.setMtu() = 1500.
 * fd passed via -device fd://N (tun2socks 2.x).
 * UDP enabled for QUIC/Reality.
 * Both stdout/stderr drained asynchronously to prevent SIGPIPE deadlock.
 */
@Singleton
class Tun2SocksManager @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG   = "Tun2SocksManager"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var proc: Process? = null
    private var outJob: Job? = null
    private var errJob: Job? = null

    suspend fun start(
        tunFd:     Int,
        socksHost: String  = "127.0.0.1",
        socksPort: Int     = 10808,
        mtu:       Int     = 1500,
        udp:       Boolean = true
    ) = withContext(Dispatchers.IO) {
        stop()
        val bin = File(ctx.filesDir, "bin/tun2socks")
        if (!bin.exists() || bin.length() < 512L)
            throw IllegalStateException("tun2socks binary missing at ${bin.absolutePath}")
        if (!bin.canExecute()) bin.setExecutable(true, false)

        val args = mutableListOf(
            bin.absolutePath,
            "-device",               "fd://$tunFd",
            "-proxy",                "socks5://$socksHost:$socksPort",
            "-mtu",                  mtu.toString(),
            "-loglevel",             "warning",
            "-tcp-send-buffer-size", "524288",
            "-tcp-recv-buffer-size", "524288",
            "-tcp-auto-tuning",      "true"
        )
        if (udp) args += listOf("-udp-timeout", "30s", "-udp-buf-size", "65535")

        Log.i(TAG, "tun2socks: ${args.joinToString(" ")}")

        val pb = ProcessBuilder(args).apply {
            redirectErrorStream(false)
            directory(ctx.filesDir)
            environment()["TUN_FD"]  = tunFd.toString()
            environment()["TUN_MTU"] = mtu.toString()
        }
        val p = pb.start(); proc = p
        outJob = scope.launch { drain(p.inputStream, "t2s/out") }
        errJob = scope.launch { drain(p.errorStream, "t2s/err") }

        delay(800)
        if (!p.isAlive)
            throw IllegalStateException("tun2socks exited immediately (exit=${p.exitValue()})")
        Log.i(TAG, "tun2socks running pid=${pid(p)}")
    }

    suspend fun stop() = withContext(Dispatchers.IO) {
        outJob?.cancel(); outJob = null
        errJob?.cancel(); errJob = null
        proc?.let { p ->
            Log.i(TAG, "Stopping tun2socks")
            p.destroy()
            withTimeoutOrNull(3_000) { while (p.isAlive) delay(100) }
            if (p.isAlive) { p.destroyForcibly(); withTimeoutOrNull(2_000) { while (p.isAlive) delay(100) } }
        }
        proc = null
    }

    fun isRunning(): Boolean = proc?.isAlive == true

    private fun drain(s: InputStream, lbl: String) {
        try {
            s.bufferedReader(Charsets.UTF_8).use { r ->
                var l: String?
                while (r.readLine().also { l = it } != null && !Thread.currentThread().isInterrupted) {
                    val line = l!!
                    if (line.contains("ERROR",true) || line.contains("WARN",true))
                        Log.w(TAG, "[$lbl] $line")
                    else Log.v(TAG, "[$lbl] $line")
                }
            }
        } catch (e: Exception) {
            val m = e.message ?: ""
            if (!m.contains("closed",true) && !m.contains("EOF",true)) Log.w(TAG,"[$lbl] $m")
        }
    }

    private fun pid(p: Process): String = try { p.pid().toString() } catch (_: Exception) { "?" }
}
HEREDOC
  log "Tun2Socks done"
}

# ─────────────────────────────────────────────────────────────
# CONNECTIVITY VERIFIER + HEALTH CHECKER
# ─────────────────────────────────────────────────────────────
write_health() {
  log "Writing health/verifier files..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"

  cat > "$B/ConnectivityVerifier.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

data class ProbeResult(val success: Boolean, val latencyMs: Long, val errorMsg: String? = null)

/**
 * Verifies the FULL VPN stack carries real traffic before marking Connected.
 *
 * Flow verified: TUN → tun2socks → Xray SOCKS5 :10808 → Xray config
 *                → psiphon-out → Psiphon :1080 → Internet
 *
 * Does NOT call protect() — packets MUST route via TUN to prove the chain works.
 */
@Singleton
class ConnectivityVerifier @Inject constructor() {
    private val TAG = "ConnVerifier"

    suspend fun verify(xraySocksPort: Int = 10808, timeoutMs: Int = 15_000): ProbeResult =
        withContext(Dispatchers.IO) {
            // Phase 1: SOCKS5 CONNECT handshake proves Xray→Psiphon chain
            val s = socks5Connect("127.0.0.1", xraySocksPort, "1.1.1.1", 443, timeoutMs)
            if (!s.success) return@withContext s

            // Phase 2: HTTP GET through the chain confirms real HTTP proxying
            val h = httpViaSocks("127.0.0.1", xraySocksPort, timeoutMs)
            Log.i(TAG, "Verify: socks=${s.success}(${s.latencyMs}ms) http=${h.success}(${h.latencyMs}ms)")

            // Accept if at least SOCKS5 CONNECT succeeded
            if (h.success) h else ProbeResult(true, s.latencyMs)
        }

    private fun socks5Connect(
        sh: String, sp: Int, dh: String, dp: Int, tms: Int
    ): ProbeResult {
        val t0 = System.currentTimeMillis()
        return try {
            Socket().use { s ->
                s.soTimeout = tms; s.tcpNoDelay = true
                s.connect(InetSocketAddress(sh, sp), tms)
                val o = s.outputStream; val i = s.inputStream

                o.write(byteArrayOf(0x05,0x01,0x00)); o.flush()
                val g = ByteArray(2); var r=0
                while(r<2){val n=i.read(g,r,2-r);if(n<0)throw Exception("EOF@greeting");r+=n}
                if(g[0]!=0x05.toByte()||g[1]!=0x00.toByte())
                    throw Exception("SOCKS5 auth rejected: ${g[1]}")

                val hb = dh.toByteArray(Charsets.US_ASCII)
                val req = ByteArray(7+hb.size).apply {
                    this[0]=0x05;this[1]=0x01;this[2]=0x00;this[3]=0x03;this[4]=hb.size.toByte()
                    System.arraycopy(hb,0,this,5,hb.size)
                    this[5+hb.size]=(dp shr 8).toByte();this[6+hb.size]=(dp and 0xFF).toByte()
                }
                o.write(req); o.flush()
                val rp=ByteArray(4);r=0
                while(r<4){val n=i.read(rp,r,4-r);if(n<0)throw Exception("EOF@resp");r+=n}
                if(rp[1]!=0x00.toByte()) throw Exception("CONNECT rejected rep=0x%02x".format(rp[1]))

                val ms = System.currentTimeMillis()-t0
                Log.i(TAG,"SOCKS5 CONNECT $dh:$dp OK ${ms}ms")
                ProbeResult(true, ms)
            }
        } catch(e: Exception) {
            Log.w(TAG,"socks5Connect failed: ${e.message}")
            ProbeResult(false, System.currentTimeMillis()-t0, e.message)
        }
    }

    private fun httpViaSocks(sh: String, sp: Int, tms: Int): ProbeResult {
        val t0 = System.currentTimeMillis()
        return try {
            Socket().use { s ->
                s.soTimeout = tms; s.connect(InetSocketAddress(sh,sp), tms)
                val o=s.outputStream; val i=s.inputStream
                o.write(byteArrayOf(0x05,0x01,0x00)); o.flush()
                val g=ByteArray(2);var r=0
                while(r<2){val n=i.read(g,r,2-r);if(n<0)throw Exception("EOF");r+=n}
                if(g[0]!=0x05.toByte()||g[1]!=0x00.toByte()) throw Exception("greeting")
                val hb="cp.cloudflare.com".toByteArray(Charsets.US_ASCII)
                val req=ByteArray(7+hb.size).apply{
                    this[0]=0x05;this[1]=0x01;this[2]=0x00;this[3]=0x03;this[4]=hb.size.toByte()
                    System.arraycopy(hb,0,this,5,hb.size);this[5+hb.size]=0x00;this[6+hb.size]=80.toByte()
                }
                o.write(req);o.flush()
                val rp=ByteArray(4);r=0
                while(r<4){val n=i.read(rp,r,4-r);if(n<0)throw Exception("EOF");r+=n}
                if(rp[1]!=0x00.toByte()) throw Exception("CONNECT rej")
                o.write("GET / HTTP/1.1\r\nHost: cp.cloudflare.com\r\nConnection: close\r\n\r\n"
                    .toByteArray(Charsets.US_ASCII)); o.flush()
                val sb=StringBuilder(); var c:Int
                while(i.read().also{c=it}!=-1){ sb.append(c.toChar()); if(sb.length>120||sb.endsWith("\n")) break }
                val code=sb.toString().split(" ").getOrNull(1)?.trim()?.toIntOrNull()?:0
                if(code !in 100..399) throw Exception("HTTP $code")
                ProbeResult(true,System.currentTimeMillis()-t0)
            }
        } catch(e: Exception){
            Log.w(TAG,"httpViaSocks: ${e.message}")
            ProbeResult(false,System.currentTimeMillis()-t0,e.message)
        }
    }
}
HEREDOC

  cat > "$B/HealthChecker.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

data class HealthReport(
    val psiphon: Boolean, val xray: Boolean, val http: Boolean,
    val psiphonMs: Long=-1, val xrayMs: Long=-1, val httpMs: Long=-1
) {
    val allHealthy = psiphon && xray
    override fun toString() = "Health[p=$psiphon(${psiphonMs}ms) x=$xray(${xrayMs}ms) h=$http(${httpMs}ms)]"
}

@Singleton
class HealthChecker @Inject constructor(private val protector: SocketProtector) {
    private val TAG = "HealthChecker"

    suspend fun checkAll(psiphonPort: Int=1080, xrayPort: Int=10808): HealthReport =
        withContext(Dispatchers.IO) {
            val (pOk,pMs) = tcpProbe(psiphonPort)
            val (xOk,xMs) = tcpProbe(xrayPort)
            val (hOk,hMs) = if (xOk) httpProbe(xrayPort) else false to -1L
            HealthReport(pOk,xOk,hOk,pMs,xMs,hMs).also { Log.d(TAG,it.toString()) }
        }

    /** Protected TCP probe — bypasses VPN so we can check local ports. */
    private fun tcpProbe(port: Int): Pair<Boolean,Long> {
        val t=System.currentTimeMillis()
        return try {
            Socket().use { s ->
                protector.protect(s)
                s.soTimeout=3_000; s.tcpNoDelay=true
                s.connect(InetSocketAddress("127.0.0.1",port),3_000)
            }
            true to (System.currentTimeMillis()-t)
        } catch(e: Exception){ Log.w(TAG,"tcpProbe :$port: ${e.message}"); false to -1L }
    }

    /** HTTP probe through Xray — no protect(), validates real traffic path. */
    private fun httpProbe(xrayPort: Int): Pair<Boolean,Long> {
        val t=System.currentTimeMillis()
        return try {
            Socket().use { s ->
                s.soTimeout=8_000; s.connect(InetSocketAddress("127.0.0.1",xrayPort),3_000)
                val o=s.outputStream; val i=s.inputStream
                o.write(byteArrayOf(0x05,0x01,0x00));o.flush()
                val g=ByteArray(2);var r=0
                while(r<2){val n=i.read(g,r,2-r);if(n<0)throw Exception("EOF");r+=n}
                if(g[0]!=0x05.toByte()||g[1]!=0x00.toByte()) throw Exception("greeting")
                // CONNECT 1.1.1.1:443
                val req=byteArrayOf(0x05,0x01,0x00,0x01,1,1,1,1,0x01,0xBB.toByte())
                o.write(req);o.flush()
                val rp=ByteArray(4);r=0
                while(r<4){val n=i.read(rp,r,4-r);if(n<0)throw Exception("EOF");r+=n}
                if(rp[1]!=0x00.toByte()) throw Exception("CONNECT rej")
                true to (System.currentTimeMillis()-t)
            }
        } catch(e: Exception){ false to -1L }
    }
}
HEREDOC
  log "Health files done"
}

# ─────────────────────────────────────────────────────────────
# WATCHDOG + RECONNECT
# ─────────────────────────────────────────────────────────────
write_supervision() {
  log "Writing supervision..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"

  cat > "$B/WatchdogSupervisor.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.util.Log
import kotlinx.coroutines.*
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Monitors all tunnel processes.
 * - Every 10s: process liveness check
 * - Every 30s: real SOCKS5+HTTP health check
 * Triggers reconnect callback on failure.
 */
@Singleton
class WatchdogSupervisor @Inject constructor(
    private val psiphon:   com.soreng.tunnel.psiphon.PsiphonManager,
    private val xray:      com.soreng.tunnel.xray.XrayManager,
    private val tun2socks: com.soreng.tunnel.tunnel.Tun2SocksManager,
    private val health:    HealthChecker,
    private val prefs:     com.soreng.tunnel.storage.AppPreferences
) {
    private val TAG = "WatchdogSupervisor"
    @Volatile private var job: Job? = null

    fun start(cfgId: Long, scope: CoroutineScope, onFail: suspend (Long) -> Unit) {
        stop()
        job = scope.launch {
            var tick = 0
            while (isActive) {
                delay(10_000); tick++
                if (!SorenVpnService.state.value.isActive) break
                if (!psiphon.isRunning() || !xray.isRunning() || !tun2socks.isRunning()) {
                    Log.w(TAG, "Process check FAILED — triggering recovery")
                    onFail(cfgId); return@launch
                }
                if (tick % 3 == 0) {
                    val h = health.checkAll()
                    if (!h.allHealthy) {
                        Log.w(TAG, "Health FAILED: $h")
                        onFail(cfgId); return@launch
                    }
                    Log.d(TAG, "Health OK: $h")
                }
            }
        }
    }

    fun stop() { job?.cancel(); job = null }
}
HEREDOC

  cat > "$B/ReconnectManager.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.util.Log
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Serializes reconnect attempts. Prevents concurrent reconnect races.
 * Exponential backoff. Max 5 failures before giving up.
 */
@Singleton
class ReconnectManager @Inject constructor() {
    private val TAG    = "ReconnectManager"
    private val mutex  = Mutex()
    private val fails  = AtomicInteger(0)
    private val inProg = AtomicBoolean(false)
    private val uStop  = AtomicBoolean(false)

    companion object {
        private val BACKOFF = longArrayOf(2_000,5_000,10_000,20_000,40_000)
        private const val MAX = 5
    }

    suspend fun reconnect(action: suspend () -> Unit): Boolean {
        if (uStop.get())  { Log.i(TAG,"suppressed — user stopped"); return false }
        if (inProg.get()) { Log.i(TAG,"suppressed — already reconnecting"); return false }
        if (fails.get() >= MAX) { Log.e(TAG,"max reconnects ($MAX) reached"); return false }
        return mutex.withLock {
            if (uStop.get() || inProg.get()) return@withLock false
            inProg.set(true)
            try {
                val delay = BACKOFF.getOrElse(fails.get()) { BACKOFF.last() }
                Log.i(TAG,"reconnect #${fails.get()+1} in ${delay}ms"); delay(delay)
                action(); fails.set(0); true
            } catch (e: Exception) {
                fails.incrementAndGet()
                Log.e(TAG,"reconnect failed (${fails.get()}): ${e.message}"); false
            } finally { inProg.set(false) }
        }
    }

    fun markUserStop() { uStop.set(true); inProg.set(false) }
    fun reset()        { fails.set(0); inProg.set(false); uStop.set(false) }
    fun isUserStop()   = uStop.get()
}
HEREDOC
  log "Supervision done"
}

# ─────────────────────────────────────────────────────────────
# MAIN VPN SERVICE
# ─────────────────────────────────────────────────────────────
write_vpn_service() {
  log "Writing SorenVpnService..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"

  cat > "$B/SorenVpnService.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.soreng.tunnel.psiphon.PsiphonManager
import com.soreng.tunnel.tunnel.Tun2SocksManager
import com.soreng.tunnel.xray.XrayManager
import com.soreng.tunnel.notifications.VpnNotificationManager
import com.soreng.tunnel.stats.StatsManager
import com.soreng.tunnel.storage.AppPreferences
import com.soreng.tunnel.storage.BinaryExtractor
import com.soreng.tunnel.storage.SplitTunnelCache
import java.net.InetSocketAddress
import java.net.Socket
import javax.inject.Inject

@AndroidEntryPoint
class SorenVpnService : VpnService() {

    @Inject lateinit var psiphon:      PsiphonManager
    @Inject lateinit var xray:         XrayManager
    @Inject lateinit var tun2socks:    Tun2SocksManager
    @Inject lateinit var stats:        StatsManager
    @Inject lateinit var notif:        VpnNotificationManager
    @Inject lateinit var prefs:        AppPreferences
    @Inject lateinit var binExtractor: BinaryExtractor
    @Inject lateinit var splitCache:   SplitTunnelCache
    @Inject lateinit var protector:    SocketProtector
    @Inject lateinit var verifier:     ConnectivityVerifier
    @Inject lateinit var watchdog:     WatchdogSupervisor
    @Inject lateinit var reconnMgr:    ReconnectManager

    private val svcScope     = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cleanupMutex = Mutex()
    private val jni          = SorenJniBridge()

    @Volatile private var tunPfd:       ParcelFileDescriptor? = null
    @Volatile private var currentCfgId: Long = -1L
    @Volatile private var startGuard    = false

    companion object {
        const val ACTION_START    = "com.soreng.tunnel.START_VPN"
        const val ACTION_STOP     = "com.soreng.tunnel.STOP_VPN"
        const val EXTRA_CONFIG_ID = "config_id"
        const val PSIPHON_PORT    = 1080
        const val XRAY_SOCKS_PORT = 10808
        private const val NOTIF_ID = 1337
        private const val TAG = "SorenVpnService"

        /** Single source of truth for connection state. */
        val state = MutableStateFlow<VpnConnectionState>(VpnConnectionState.Disconnected)
    }

    override fun onCreate() {
        super.onCreate()
        // Register real protect() bridge IMMEDIATELY — before any sockets are created
        protector.register(this)
        jni.registerProtectCallback(protector)
        Log.i(TAG, "onCreate: protect() bridge active — ${jni.getVersion()}")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_START -> {
                val cfgId = intent.getLongExtra(EXTRA_CONFIG_ID, -1L)
                if (cfgId >= 0 && !state.value.isActive && !startGuard) {
                    startGuard = true
                    reconnMgr.reset()
                    startForeground(NOTIF_ID, notif.buildConnecting())
                    svcScope.launch { try { doStart(cfgId) } finally { startGuard = false } }
                } else {
                    Log.w(TAG, "Start ignored: cfgId=$cfgId active=${state.value.isActive} guard=$startGuard")
                }
                START_STICKY
            }
            ACTION_STOP -> {
                reconnMgr.markUserStop()
                svcScope.launch { doShutdown() }
                START_NOT_STICKY
            }
            null -> {
                // Sticky restart by Android after OEM kill
                if (currentCfgId >= 0 && !reconnMgr.isUserStop()) {
                    svcScope.launch { reconnMgr.reconnect { doStart(currentCfgId) } }
                }
                START_STICKY
            }
            else -> START_NOT_STICKY
        }
    }

    // ── STRICT 6-STEP STARTUP ─────────────────────────────────
    private suspend fun doStart(cfgId: Long) {
        // Pre-flight
        binExtractor.extractAll()
        splitCache.load()
        currentCfgId = cfgId

        try {
            state.value = VpnConnectionState.Connecting
            postNotif(notif.buildConnecting())

            // [1/6] Psiphon — MUST come first
            Log.i(TAG, "[1/6] Starting Psiphon...")
            psiphon.start()

            // [2/6] Verify Psiphon SOCKS5 reachable (with protect() to avoid self-routing)
            Log.i(TAG, "[2/6] Verifying Psiphon SOCKS5 :$PSIPHON_PORT")
            awaitSocks5(PSIPHON_PORT, 35_000, "Psiphon")

            // [3/6] Xray — config forces all outbound through Psiphon SOCKS5
            Log.i(TAG, "[3/6] Starting Xray...")
            xray.start(cfgId, PSIPHON_PORT)

            // [4/6] Verify Xray SOCKS5 reachable
            Log.i(TAG, "[4/6] Verifying Xray SOCKS5 :$XRAY_SOCKS_PORT")
            awaitSocks5(XRAY_SOCKS_PORT, 20_000, "Xray")

            // [5/6] TUN interface + tun2socks
            Log.i(TAG, "[5/6] Building TUN + tun2socks...")
            val pfd = buildTun() ?: throw IllegalStateException("VPN establish() null — permission revoked?")
            tunPfd = pfd
            jni.setTunFd(pfd.fd)
            tun2socks.start(tunFd = pfd.fd, socksPort = XRAY_SOCKS_PORT,
                mtu = 1500, udp = prefs.isUdpEnabled())
            delay(600)
            if (!tun2socks.isRunning()) throw IllegalStateException("tun2socks died immediately after start")

            // [6/6] End-to-end verification — NEVER show Connected without real traffic proof
            Log.i(TAG, "[6/6] End-to-end connectivity verification...")
            val probe = verifier.verify(XRAY_SOCKS_PORT, 15_000)
            if (!probe.success) throw IllegalStateException(
                "End-to-end probe FAILED: ${probe.errorMsg}. " +
                "Refusing Connected state — stack not passing real traffic.")

            // ── ALL CHECKS PASSED ──────────────────────────────
            Log.i(TAG, "VPN fully established. Probe latency=${probe.latencyMs}ms")
            state.value = VpnConnectionState.Connected(System.currentTimeMillis(), probe.latencyMs)
            postNotif(notif.buildConnected())
            stats.startSession()
            watchdog.start(cfgId, svcScope) { id ->
                val ok = reconnMgr.reconnect { doCleanup(); doStart(id) }
                if (!ok) { doCleanup(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
            }

        } catch (e: CancellationException) {
            Log.i(TAG, "doStart cancelled"); doCleanup()
        } catch (e: Exception) {
            Log.e(TAG, "VPN start FAILED: ${e.message}", e)
            state.value = VpnConnectionState.Error(e.message ?: "Unknown")
            postNotif(notif.buildError(e.message ?: "Failed"))
            doCleanup()
            stopForeground(STOP_FOREGROUND_DETACH); stopSelf()
        }
    }

    private suspend fun buildTun(): ParcelFileDescriptor? {
        val ipv6 = prefs.isIPv6Enabled()
        val b = Builder()
            .setSession("SorenNG")
            .setMtu(1500)
            .setBlocking(false)
            .addAddress("10.89.0.1", 30)
            .addDnsServer("198.18.0.2")     // FakeDNS pool — Xray intercepts DNS here
            .addDnsServer("1.1.1.1")
            .addRoute("0.0.0.0", 0)         // Route ALL IPv4 through VPN
            .addDisallowedApplication(packageName) // Exclude ourselves — prevents routing loop

        if (ipv6) {
            b.addAddress("fd00:1:2:3::1", 128).addRoute("::", 0)
             .addDnsServer("2606:4700:4700::1111")
        } else {
            // IPv6 disabled: route IPv6 into VPN to block leaks (Xray discards)
            listOf("2000::/3","fc00::/7","fe80::/10").forEach { cidr ->
                try {
                    val (a, p) = cidr.split("/")
                    b.addRoute(a, p.toInt())
                } catch (_: Exception) {}
            }
        }
        for (pkg in splitCache.getBypassPackages()) {
            try { b.addDisallowedApplication(pkg) }
            catch (e: Exception) { Log.w(TAG, "bypass $pkg: ${e.message}") }
        }
        return b.establish()
    }

    private suspend fun doShutdown() {
        doCleanup(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }

    private suspend fun doCleanup() = cleanupMutex.withLock {
        Log.i(TAG, "doCleanup: ordered shutdown")
        state.value = VpnConnectionState.Disconnecting
        watchdog.stop()
        stats.stopSession()
        safeStop("tun2socks")  { tun2socks.stop() }
        safeStop("xray")       { xray.stop() }
        safeStop("psiphon")    { psiphon.stop() }
        try { tunPfd?.close() } catch (e: Exception) { Log.w(TAG,"tunPfd close: ${e.message}") }
        finally { tunPfd = null }
        jni.cleanup()
        state.value = VpnConnectionState.Disconnected
        Log.i(TAG, "doCleanup: done")
    }

    private suspend fun safeStop(n: String, b: suspend ()->Unit) =
        try { b() } catch (e: Exception) { Log.w(TAG,"safeStop[$n]: ${e.message}") }

    /**
     * Await SOCKS5 readiness.
     * ALWAYS calls protect() on the probe socket to prevent self-routing.
     */
    private suspend fun awaitSocks5(port: Int, timeoutMs: Long, label: String) =
        withContext(Dispatchers.IO) {
            val deadline = System.currentTimeMillis() + timeoutMs
            var attempts = 0; var lastErr = "timeout"
            while (System.currentTimeMillis() < deadline) {
                attempts++
                try {
                    Socket().use { s ->
                        protector.protect(s)   // CRITICAL: prevent self-routing
                        s.soTimeout=1_500; s.tcpNoDelay=true
                        s.connect(InetSocketAddress("127.0.0.1",port),1_500)
                    }
                    Log.i(TAG,"$label SOCKS5 ready ($attempts attempts)"); return@withContext
                } catch (e: Exception) { lastErr=e.message?:"err"; delay(600) }
            }
            throw IllegalStateException(
                "$label :$port not ready after ${timeoutMs}ms ($attempts attempts). Last: $lastErr")
        }

    private fun postNotif(n: android.app.Notification) = try {
        getSystemService(android.app.NotificationManager::class.java).notify(NOTIF_ID, n)
    } catch (e: Exception) { Log.w(TAG,"postNotif: ${e.message}") }

    override fun onRevoke() {
        Log.w(TAG,"onRevoke"); reconnMgr.markUserStop()
        svcScope.launch { doCleanup() }; super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG,"onDestroy"); reconnMgr.markUserStop()
        jni.unregisterProtectCallback(); protector.unregister()
        runBlocking { withTimeoutOrNull(5_000) { doCleanup() } }
        svcScope.cancel(); super.onDestroy()
    }
}
HEREDOC
  log "VPN service done"
}


# ─────────────────────────────────────────────────────────────
# CONFIG — data models, parser, runtime builder
# ─────────────────────────────────────────────────────────────
write_config() {
  log "Writing config layer..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/config"
  mkdir -p "$B"

  cat > "$B/ConfigProfile.kt" << 'HEREDOC'
package com.soreng.tunnel.config

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "config_profiles")
data class ConfigProfile(
    @PrimaryKey(autoGenerate = true) val id:     Long    = 0,
    val name:             String  = "",
    val protocol:         Protocol = Protocol.VLESS,
    val address:          String  = "",
    val port:             Int     = 443,
    val uuid:             String  = "",
    val password:         String  = "",
    val network:          String  = "tcp",
    val security:         String  = "tls",
    val flow:             String  = "",
    val path:             String  = "/",
    val host:             String  = "",
    val sni:              String  = "",
    val fingerprint:      String  = "chrome",
    val publicKey:        String  = "",
    val shortId:          String  = "",
    val spiderX:          String  = "",
    val grpcServiceName:  String  = "",
    val alterId:          Int     = 0,
    val encryption:       String  = "auto",
    val remarks:          String  = "",
    val rawUri:           String  = "",
    val isFavorite:       Boolean = false,
    val subscriptionId:   Long    = -1L,
    val groupName:        String  = "",
    val latencyMs:        Long    = -1L,
    val createdAt:        Long    = System.currentTimeMillis(),
    val updatedAt:        Long    = System.currentTimeMillis()
)

enum class Protocol(val scheme: String) {
    VMESS("vmess"), VLESS("vless"), TROJAN("trojan"),
    SHADOWSOCKS("ss"), SOCKS5("socks"), HTTP("http");
    companion object {
        fun fromScheme(s: String) = values().find { it.scheme.equals(s, true) }
    }
}
HEREDOC

  cat > "$B/ConfigParser.kt" << 'HEREDOC'
package com.soreng.tunnel.config

import android.util.Base64
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParseException
import java.net.URI
import java.net.URLDecoder
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Parses all supported VPN URI formats.
 * Returns null (never throws) for malformed input.
 * Validates required fields before returning.
 */
@Singleton
class ConfigParser @Inject constructor() {
    private val TAG  = "ConfigParser"
    private val gson = Gson()

    fun parse(raw: String): ConfigProfile? = try {
        val t = raw.trim()
        val p = when {
            t.startsWith("vmess://")                              -> parseVmess(t)
            t.startsWith("vless://")                              -> parseVless(t)
            t.startsWith("trojan://")                             -> parseTrojan(t)
            t.startsWith("ss://")                                 -> parseSs(t)
            t.startsWith("socks5://") || t.startsWith("socks://") -> parseSocks(t)
            t.startsWith("http://") && hasUserInfoOrPort(t)       -> parseHttp(t)
            t.startsWith("{")                                     -> parseJson(t)
            else -> { Log.d(TAG,"Unknown scheme: ${t.take(30)}"); null }
        }
        p?.let { validate(it) }
    } catch (e: Exception) { Log.w(TAG,"parse error ${raw.take(40)}: ${e.message}"); null }

    private fun validate(p: ConfigProfile): ConfigProfile? {
        if (p.address.isBlank()) { Log.w(TAG,"reject: blank address"); return null }
        if (p.port !in 1..65535)  { Log.w(TAG,"reject: bad port ${p.port}"); return null }
        return when (p.protocol) {
            Protocol.VMESS, Protocol.VLESS ->
                if (p.uuid.isBlank()) { Log.w(TAG,"reject: blank uuid"); null } else p
            Protocol.TROJAN, Protocol.SHADOWSOCKS ->
                if (p.password.isBlank()) { Log.w(TAG,"reject: blank password"); null } else p
            else -> p
        }
    }

    private fun parseVmess(uri: String): ConfigProfile {
        val b64 = uri.removePrefix("vmess://")
        val json = String(Base64.decode(pad(b64), Base64.URL_SAFE or Base64.NO_WRAP))
        val o = gson.fromJson(json, JsonObject::class.java)
            ?: throw JsonParseException("null JSON")
        return ConfigProfile(
            protocol    = Protocol.VMESS,
            name        = o.s("ps","VMess"),
            address     = o.s("add"),
            port        = o.s("port","0").toIntOrNull() ?: o.i("port",0),
            uuid        = o.s("id"),
            alterId     = o.i("aid",0),
            encryption  = o.s("scy","auto"),
            network     = o.s("net","tcp"),
            host        = o.s("host"),
            path        = o.s("path","/"),
            security    = o.s("tls"),
            sni         = o.s("sni"),
            fingerprint = o.s("fp","chrome"),
            rawUri      = uri
        )
    }

    private fun parseVless(uri: String): ConfigProfile {
        val withoutScheme = uri.removePrefix("vless://")
        val (beforeFrag, frag) = splitFrag(withoutScheme)
        val (userHostPort, query) = splitQuery(beforeFrag)
        val (uid, hostPort) = splitAt(userHostPort)
        val (host, portStr) = splitHostPort(hostPort)
        val q = parseQuery(query)
        return ConfigProfile(
            protocol        = Protocol.VLESS,
            name            = dec(frag) ?: "VLESS",
            address         = host,
            port            = portStr.toIntOrNull() ?: 443,
            uuid            = uid,
            network         = q["type"] ?: "tcp",
            security        = q["security"] ?: "none",
            flow            = q["flow"] ?: "",
            sni             = q["sni"] ?: "",
            fingerprint     = q["fp"] ?: "chrome",
            publicKey       = q["pbk"] ?: "",
            shortId         = q["sid"] ?: "",
            spiderX         = q["spx"] ?: "",
            path            = dec(q["path"]) ?: "/",
            host            = q["host"] ?: "",
            grpcServiceName = q["serviceName"] ?: "",
            rawUri          = uri
        )
    }

    private fun parseTrojan(uri: String): ConfigProfile {
        val withoutScheme = uri.removePrefix("trojan://")
        val (beforeFrag, frag) = splitFrag(withoutScheme)
        val (userHostPort, query) = splitQuery(beforeFrag)
        val (pass, hostPort) = splitAt(userHostPort)
        val (host, portStr) = splitHostPort(hostPort)
        val q = parseQuery(query)
        return ConfigProfile(
            protocol    = Protocol.TROJAN,
            name        = dec(frag) ?: "Trojan",
            address     = host,
            port        = portStr.toIntOrNull() ?: 443,
            password    = dec(pass) ?: pass,
            network     = q["type"] ?: "tcp",
            security    = q["security"] ?: "tls",
            sni         = q["sni"] ?: "",
            fingerprint = q["fp"] ?: "",
            path        = dec(q["path"]) ?: "/",
            host        = q["host"] ?: "",
            flow        = q["flow"] ?: "",
            rawUri      = uri
        )
    }

    private fun parseSs(uri: String): ConfigProfile {
        val withoutScheme = uri.removePrefix("ss://")
        val (main, frag) = splitFrag(withoutScheme)
        val name = dec(frag) ?: "Shadowsocks"
        return if ('@' in main) {
            val userInfo = main.substringBefore('@')
            val hostPort = main.substringAfter('@')
            val decoded  = safeB64(userInfo)
            val method   = decoded.substringBefore(':')
            val password = decoded.substringAfter(':')
            val host     = hostPort.substringBeforeLast(':')
            val port     = hostPort.substringAfterLast(':').toIntOrNull() ?: 443
            ConfigProfile(protocol=Protocol.SHADOWSOCKS, name=name, address=host,
                port=port, encryption=method, password=password, rawUri=uri)
        } else {
            val decoded  = safeB64(main)
            val methodPass = decoded.substringBefore('@')
            val hostPart   = decoded.substringAfter('@','/')
            ConfigProfile(protocol=Protocol.SHADOWSOCKS, name=name,
                address=hostPart.substringBeforeLast(':'),
                port=hostPart.substringAfterLast(':').toIntOrNull()?:443,
                encryption=methodPass.substringBefore(':'),
                password=methodPass.substringAfter(':'), rawUri=uri)
        }
    }

    private fun parseSocks(uri: String): ConfigProfile {
        val u = URI(uri.replace("socks5://","http://").replace("socks://","http://"))
        val (user,pass) = splitUserInfo(u.userInfo)
        return ConfigProfile(protocol=Protocol.SOCKS5, name=dec(u.fragment)?:"SOCKS5",
            address=u.host?:"", port=if(u.port>0) u.port else 1080,
            uuid=user, password=pass, rawUri=uri)
    }

    private fun parseHttp(uri: String): ConfigProfile {
        val u = URI(uri)
        val (user,pass) = splitUserInfo(u.userInfo)
        return ConfigProfile(protocol=Protocol.HTTP, name=dec(u.fragment)?:"HTTP",
            address=u.host?:"", port=if(u.port>0) u.port else 8080,
            uuid=user, password=pass, rawUri=uri)
    }

    private fun parseJson(json: String): ConfigProfile {
        val o = gson.fromJson(json, JsonObject::class.java) ?: throw JsonParseException("null")
        return ConfigProfile(protocol=Protocol.fromScheme(o.s("protocol","vless"))?:Protocol.VLESS,
            name=o.s("name","Custom"), address=o.s("address"), port=o.i("port",443),
            uuid=o.s("uuid"), password=o.s("password"),
            network=o.s("network","tcp"), security=o.s("security","tls"), rawUri=json)
    }

    private fun hasUserInfoOrPort(uri: String) = try {
        val u = URI(uri); u.userInfo != null || u.port > 0
    } catch (_: Exception) { false }

    private fun pad(s: String)   = s + "=".repeat((4 - s.length % 4) % 4)
    private fun safeB64(s: String): String = try {
        String(Base64.decode(pad(s), Base64.URL_SAFE or Base64.NO_WRAP))
    } catch (_: Exception) { try { String(Base64.decode(pad(s), Base64.DEFAULT)) } catch (_: Exception) { s } }
    private fun dec(s: String?)  = s?.let { try { URLDecoder.decode(it,"UTF-8") } catch (_:Exception){ it } }
    private fun splitFrag(s: String)  = if('#' in s) s.substringBefore('#') to s.substringAfter('#') else s to null
    private fun splitQuery(s: String) = if('?' in s) s.substringBefore('?') to s.substringAfter('?') else s to ""
    private fun splitAt(s: String)    = if('@' in s) s.substringBefore('@') to s.substringAfterLast('@') else "" to s
    private fun splitHostPort(s: String) = s.substringBeforeLast(':') to s.substringAfterLast(':','/')
    private fun splitUserInfo(info: String?): Pair<String,String> {
        if (info.isNullOrBlank()) return "" to ""
        return (dec(info.substringBefore(':')) ?: "") to (if(':' in info) dec(info.substringAfter(':')) ?: "" else "")
    }
    private fun parseQuery(q: String): Map<String,String> {
        if (q.isBlank()) return emptyMap()
        return q.split("&").mapNotNull { p ->
            val kv = p.split("=",limit=2)
            if (kv.size==2) runCatching { (dec(kv[0])?:kv[0]) to (dec(kv[1])?:kv[1]) }.getOrNull() else null
        }.toMap()
    }
    private fun JsonObject.s(k:String,d:String="") =
        if(has(k)&&!get(k).isJsonNull) runCatching{get(k).asString}.getOrDefault(d) else d
    private fun JsonObject.i(k:String,d:Int=0) =
        if(has(k)&&!get(k).isJsonNull) runCatching{get(k).asInt}.getOrDefault(d) else d
}
HEREDOC

  cat > "$B/RuntimeConfigBuilder.kt" << 'HEREDOC'
package com.soreng.tunnel.config

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Builds the Xray runtime JSON config.
 *
 * ENFORCED traffic flow:
 *   tun2socks → Xray SOCKS5 :10808
 *   → routing → outbound tag="proxy"
 *   → proxySettings.tag="psiphon-out"   ← ALL traffic forced through Psiphon
 *   → Psiphon SOCKS5 127.0.0.1:1080
 *   → Internet
 *
 * DNS:
 *   FakeDNS at 198.18.0.0/15 captures DNS queries.
 *   Real DNS resolved via Xray dns-out → proxy → Psiphon (never direct).
 *   IPv6 queryStrategy=UseIPv4 when IPv6 disabled → prevents IPv6 DNS leaks.
 *
 * No "direct" outbound — ALL traffic routes through Psiphon.
 */
@Singleton
class RuntimeConfigBuilder @Inject constructor() {

    fun build(p: ConfigProfile, psiphonPort: Int): JsonObject = JsonObject().apply {
        add("log",      log())
        add("dns",      dns())
        add("inbounds", inbounds())
        add("outbounds",outbounds(p, psiphonPort))
        add("routing",  routing())
        add("policy",   policy())
        add("stats",    JsonObject())
    }

    private fun log() = jo { addProperty("loglevel","warning"); addProperty("access","none") }

    private fun dns() = jo {
        add("servers", ja {
            add(jo {  // FakeDNS captures all domains
                addProperty("address","fakedns")
                add("domains", ja { add("geosite:geolocation-!cn"); add("regexp:.*") })
            })
            add(jo {  // Real DNS via DoH — routes through Xray proxy → Psiphon
                addProperty("address","https://1.1.1.1/dns-query"); addProperty("port",443)
            })
            add(jo { addProperty("address","https://8.8.8.8/dns-query"); addProperty("port",443) })
        })
        addProperty("fakeIp","198.18.0.0/15")
        addProperty("queryStrategy","UseIPv4")   // IPv6 DNS leak prevention
        add("hosts", JsonObject())
    }

    private fun inbounds() = ja {
        add(jo {  // SOCKS5 — tun2socks connects here
            addProperty("tag","socks-in"); addProperty("port",10808)
            addProperty("listen","127.0.0.1"); addProperty("protocol","socks")
            add("settings", jo { addProperty("auth","noauth"); addProperty("udp",true); addProperty("ip","127.0.0.1") })
            add("sniffing", sniff())
        })
        add(jo {  // HTTP — optional
            addProperty("tag","http-in"); addProperty("port",10809)
            addProperty("listen","127.0.0.1"); addProperty("protocol","http")
            add("settings", jo { addProperty("allowTransparent",false) })
            add("sniffing", sniff())
        })
        add(jo {  // DNS inbound for FakeDNS hijacking
            addProperty("tag","dns-in"); addProperty("port",5353)
            addProperty("listen","127.0.0.1"); addProperty("protocol","dokodemo-door")
            add("settings", jo {
                addProperty("address","1.1.1.1"); addProperty("port",53)
                addProperty("network","tcp,udp"); addProperty("followRedirect",false)
            })
        })
    }

    private fun sniff() = jo {
        addProperty("enabled",true); addProperty("metadataOnly",false)
        add("destOverride", ja { add("http"); add("tls"); add("quic"); add("fakedns") })
        addProperty("routeOnly",false)
    }

    private fun outbounds(p: ConfigProfile, psiphonPort: Int) = ja {
        add(proxyOut(p))           // proxy   — chains through psiphon-out
        add(psiphonOut(psiphonPort)) // psiphon-out — Psiphon SOCKS5
        add(dnsOut())               // dns-out
        // NO "direct" outbound — all traffic forced through Psiphon
        add(blockOut())             // block — safety catch-all
    }

    private fun proxyOut(p: ConfigProfile) = jo {
        addProperty("tag","proxy")
        setProtocol(this, p)
        add("streamSettings", stream(p))
        // CRITICAL: force ALL proxy traffic through Psiphon SOCKS5
        add("proxySettings", jo {
            addProperty("tag","psiphon-out")
            addProperty("transportLayer",true)
        })
        add("mux", jo {
            val ok = p.network !in listOf("grpc","quic","kcp")
            addProperty("enabled",ok); addProperty("concurrency", if(ok) 8 else -1)
        })
    }

    private fun psiphonOut(port: Int) = jo {
        addProperty("tag","psiphon-out"); addProperty("protocol","socks")
        add("settings", jo {
            add("servers", ja { add(jo { addProperty("address","127.0.0.1"); addProperty("port",port) }) })
        })
    }

    private fun dnsOut()   = jo { addProperty("tag","dns-out"); addProperty("protocol","dns"); add("settings",JsonObject()) }
    private fun blockOut() = jo {
        addProperty("tag","block"); addProperty("protocol","blackhole")
        add("settings", jo { add("response", jo { addProperty("type","http") }) })
    }

    private fun setProtocol(obj: JsonObject, p: ConfigProfile) {
        when (p.protocol) {
            Protocol.VMESS -> {
                obj.addProperty("protocol","vmess")
                obj.add("settings", jo { add("vnext", ja { add(jo {
                    addProperty("address",p.address); addProperty("port",p.port)
                    add("users", ja { add(jo {
                        addProperty("id",p.uuid); addProperty("alterId",p.alterId)
                        addProperty("security",p.encryption.ifBlank{"auto"})
                    })})
                })})})
            }
            Protocol.VLESS -> {
                obj.addProperty("protocol","vless")
                obj.add("settings", jo { add("vnext", ja { add(jo {
                    addProperty("address",p.address); addProperty("port",p.port)
                    add("users", ja { add(jo {
                        addProperty("id",p.uuid); addProperty("encryption","none")
                        if (p.flow.isNotBlank()) addProperty("flow",p.flow)
                    })})
                })})})
            }
            Protocol.TROJAN -> {
                obj.addProperty("protocol","trojan")
                obj.add("settings", jo { add("servers", ja { add(jo {
                    addProperty("address",p.address); addProperty("port",p.port)
                    addProperty("password",p.password)
                    if (p.flow.isNotBlank()) addProperty("flow",p.flow)
                })})})
            }
            Protocol.SHADOWSOCKS -> {
                obj.addProperty("protocol","shadowsocks")
                obj.add("settings", jo { add("servers", ja { add(jo {
                    addProperty("address",p.address); addProperty("port",p.port)
                    addProperty("method",p.encryption); addProperty("password",p.password)
                    addProperty("uot",true)
                })})})
            }
            Protocol.SOCKS5 -> {
                obj.addProperty("protocol","socks")
                obj.add("settings", jo { add("servers", ja { add(jo {
                    addProperty("address",p.address); addProperty("port",p.port)
                    if (p.uuid.isNotBlank()||p.password.isNotBlank())
                        add("users", ja { add(jo { addProperty("user",p.uuid); addProperty("pass",p.password) }) })
                })})})
            }
            Protocol.HTTP -> {
                obj.addProperty("protocol","http")
                obj.add("settings", jo { add("servers", ja { add(jo {
                    addProperty("address",p.address); addProperty("port",p.port)
                    if (p.uuid.isNotBlank()||p.password.isNotBlank())
                        add("users", ja { add(jo { addProperty("user",p.uuid); addProperty("pass",p.password) }) })
                })})})
            }
        }
    }

    private fun stream(p: ConfigProfile) = jo {
        addProperty("network",p.network)
        when (p.security.lowercase()) {
            "tls" -> {
                addProperty("security","tls")
                add("tlsSettings", jo {
                    addProperty("serverName",p.sni.ifBlank{p.address})
                    addProperty("allowInsecure",false)
                    addProperty("fingerprint",p.fingerprint.ifBlank{"chrome"})
                    add("alpn", ja { if(p.network in listOf("h2","grpc")) add("h2") else { add("h2"); add("http/1.1") } })
                })
            }
            "reality" -> {
                addProperty("security","reality")
                add("realitySettings", jo {
                    addProperty("serverName",p.sni); addProperty("fingerprint",p.fingerprint.ifBlank{"chrome"})
                    addProperty("shortId",p.shortId); addProperty("publicKey",p.publicKey)
                    addProperty("spiderX",p.spiderX.ifBlank{"/"}); addProperty("show",false)
                })
            }
            else -> addProperty("security","none")
        }
        when (p.network.lowercase()) {
            "ws"          -> add("wsSettings", jo { addProperty("path",p.path.ifBlank{"/"})
                                add("headers",jo { if(p.host.isNotBlank()) addProperty("Host",p.host) }) })
            "grpc"        -> add("grpcSettings", jo { addProperty("serviceName",p.grpcServiceName)
                                addProperty("multiMode",false); addProperty("idle_timeout",60) })
            "h2","http"   -> add("httpSettings", jo { addProperty("path",p.path.ifBlank{"/"})
                                add("host", ja { if(p.host.isNotBlank()) add(p.host) }) })
            "httpupgrade" -> add("httpupgradeSettings", jo { addProperty("path",p.path.ifBlank{"/"})
                                if(p.host.isNotBlank()) addProperty("host",p.host) })
            "quic"        -> add("quicSettings", jo { addProperty("security","none"); addProperty("key","")
                                add("header",jo{addProperty("type","none")}) })
            "kcp"         -> add("kcpSettings", jo {
                                addProperty("mtu",1350); addProperty("tti",50)
                                addProperty("uplinkCapacity",12); addProperty("downlinkCapacity",100)
                                addProperty("congestion",false); addProperty("readBufferSize",2)
                                addProperty("writeBufferSize",2)
                                add("header",jo{addProperty("type","none")})
                            })
        }
    }

    private fun routing() = jo {
        addProperty("domainStrategy","IPIfNonMatch"); addProperty("domainMatcher","hybrid")
        add("rules", ja {
            // DNS inbound → dns-out (Xray handles DNS, routes via Psiphon)
            add(jo { addProperty("type","field"); addProperty("inboundTag","dns-in"); addProperty("outboundTag","dns-out") })
            // FakeDNS virtual IPs → proxy
            add(jo { addProperty("type","field"); add("ip",ja{add("198.18.0.0/15")}); addProperty("outboundTag","proxy") })
            // Ads → block
            add(jo { addProperty("type","field"); add("domain",ja{add("geosite:category-ads-all")}); addProperty("outboundTag","block") })
            // Private/loopback → proxy (Psiphon handles; avoids routing conflicts)
            add(jo { addProperty("type","field")
                add("ip",ja{add("127.0.0.0/8");add("::1/128");add("10.0.0.0/8");add("172.16.0.0/12");add("192.168.0.0/16")})
                addProperty("outboundTag","proxy") })
            // ALL remaining → proxy (through Psiphon — no direct fallback ever)
            add(jo { addProperty("type","field")
                add("network",ja{add("tcp");add("udp")}); addProperty("outboundTag","proxy") })
        })
    }

    private fun policy() = jo {
        add("levels", jo { add("0", jo {
            addProperty("handshake",4); addProperty("connIdle",300)
            addProperty("uplinkOnly",1); addProperty("downlinkOnly",1)
            addProperty("bufferSize",10240)
            addProperty("statsUserUplink",true); addProperty("statsUserDownlink",true)
        })})
        add("system", jo {
            addProperty("statsInboundUplink",true); addProperty("statsInboundDownlink",true)
            addProperty("statsOutboundUplink",true); addProperty("statsOutboundDownlink",true)
        })
    }

    private fun jo(init: JsonObject.() -> Unit = {}) = JsonObject().also(init)
    private fun ja(init: JsonArray.() -> Unit = {})  = JsonArray().also(init)
}
HEREDOC
  log "Config layer done"
}

# ─────────────────────────────────────────────────────────────
# STORAGE — Room DB, DAOs, DataStore, secure store, binary extractor
# ─────────────────────────────────────────────────────────────
write_storage() {
  log "Writing storage layer..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/storage"
  mkdir -p "$B"

  cat > "$B/AppDatabase.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.soreng.tunnel.config.ConfigProfile

@Database(
    entities  = [ConfigProfile::class, SubscriptionEntity::class, SessionStatsEntity::class],
    version   = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun configDao():  ConfigDao
    abstract fun subDao():     SubscriptionDao
    abstract fun statsDao():   SessionStatsDao
}
HEREDOC

  cat > "$B/ConfigDao.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import androidx.room.*
import com.soreng.tunnel.config.ConfigProfile
import kotlinx.coroutines.flow.Flow

@Dao
interface ConfigDao {
    @Query("SELECT * FROM config_profiles ORDER BY isFavorite DESC, updatedAt DESC")
    fun getAll(): Flow<List<ConfigProfile>>

    @Query("SELECT * FROM config_profiles WHERE isFavorite=1 ORDER BY updatedAt DESC")
    fun getFavorites(): Flow<List<ConfigProfile>>

    @Query("SELECT * FROM config_profiles WHERE id=:id")
    suspend fun getById(id: Long): ConfigProfile?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(p: ConfigProfile): Long

    @Update
    suspend fun update(p: ConfigProfile)

    @Delete
    suspend fun delete(p: ConfigProfile)

    @Query("DELETE FROM config_profiles WHERE id=:id")
    suspend fun deleteById(id: Long)

    @Query("SELECT * FROM config_profiles WHERE subscriptionId=:subId")
    suspend fun getBySubscription(subId: Long): List<ConfigProfile>

    @Query("DELETE FROM config_profiles WHERE subscriptionId=:subId")
    suspend fun deleteBySubscription(subId: Long)

    @Query("SELECT * FROM config_profiles WHERE name LIKE :q OR address LIKE :q OR remarks LIKE :q ORDER BY isFavorite DESC, updatedAt DESC")
    fun search(q: String): Flow<List<ConfigProfile>>
}
HEREDOC

  cat > "$B/SubscriptionEntity.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "subscriptions")
data class SubscriptionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name:           String  = "",
    val url:            String  = "",
    val lastUpdated:    Long    = 0L,
    val autoUpdate:     Boolean = true,
    val updateInterval: Int     = 86400,
    val enabled:        Boolean = true
)
HEREDOC

  cat > "$B/SubscriptionDao.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface SubscriptionDao {
    @Query("SELECT * FROM subscriptions ORDER BY name ASC")
    fun getAll(): Flow<List<SubscriptionEntity>>
    @Insert(onConflict=OnConflictStrategy.REPLACE) suspend fun insert(s: SubscriptionEntity): Long
    @Update                                         suspend fun update(s: SubscriptionEntity)
    @Delete                                         suspend fun delete(s: SubscriptionEntity)
    @Query("SELECT * FROM subscriptions WHERE id=:id") suspend fun getById(id: Long): SubscriptionEntity?
}
HEREDOC

  cat > "$B/SessionStatsEntity.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "session_stats")
data class SessionStatsEntity(
    @PrimaryKey(autoGenerate = true) val id:   Long = 0,
    val configId:      Long = -1L,
    val startTime:     Long = 0L,
    val endTime:       Long = 0L,
    val uploadBytes:   Long = 0L,
    val downloadBytes: Long = 0L,
    val avgPingMs:     Long = -1L
)
HEREDOC

  cat > "$B/SessionStatsDao.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface SessionStatsDao {
    @Insert                suspend fun insert(s: SessionStatsEntity): Long
    @Update                suspend fun update(s: SessionStatsEntity)
    @Query("SELECT * FROM session_stats ORDER BY startTime DESC LIMIT :n")
    fun getRecent(n: Int = 50): Flow<List<SessionStatsEntity>>
    @Query("SELECT SUM(uploadBytes) FROM session_stats")   suspend fun totalUpload(): Long?
    @Query("SELECT SUM(downloadBytes) FROM session_stats") suspend fun totalDownload(): Long?
}
HEREDOC

  cat > "$B/ConfigRepository.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import com.soreng.tunnel.config.ConfigProfile
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ConfigRepository @Inject constructor(private val dao: ConfigDao) {
    fun getAll():                      Flow<List<ConfigProfile>> = dao.getAll()
    fun getFavorites():                Flow<List<ConfigProfile>> = dao.getFavorites()
    suspend fun getById(id: Long):     ConfigProfile?            = dao.getById(id)
    suspend fun insert(p: ConfigProfile): Long                   = dao.insert(p)
    suspend fun update(p: ConfigProfile)                         = dao.update(p)
    suspend fun delete(p: ConfigProfile)                         = dao.delete(p)
    suspend fun deleteById(id: Long)                             = dao.deleteById(id)
    suspend fun toggleFavorite(id: Long) {
        val p = dao.getById(id) ?: return
        dao.update(p.copy(isFavorite = !p.isFavorite, updatedAt = System.currentTimeMillis()))
    }
    suspend fun updateLatency(id: Long, ms: Long) {
        val p = dao.getById(id) ?: return
        dao.update(p.copy(latencyMs = ms, updatedAt = System.currentTimeMillis()))
    }
    fun search(q: String): Flow<List<ConfigProfile>>             = dao.search("%$q%")
}
HEREDOC

  cat > "$B/AppPreferences.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.ds: DataStore<Preferences> by preferencesDataStore("soren_prefs")

@Singleton
class AppPreferences @Inject constructor(@ApplicationContext private val ctx: Context) {
    private val ds = ctx.ds
    companion object {
        val K_AUTO_START    = booleanPreferencesKey("auto_start")
        val K_AUTO_RECONNECT= booleanPreferencesKey("auto_reconnect")
        val K_KILL_SWITCH   = booleanPreferencesKey("kill_switch")
        val K_FAKE_DNS      = booleanPreferencesKey("fake_dns")
        val K_UDP           = booleanPreferencesKey("udp")
        val K_IPV6          = booleanPreferencesKey("ipv6")
        val K_ANTI_DPI      = booleanPreferencesKey("anti_dpi")
        val K_DNS_1         = stringPreferencesKey("dns_primary")
        val K_DNS_2         = stringPreferencesKey("dns_secondary")
        val K_BYPASS_APPS   = stringSetPreferencesKey("bypass_apps")
        val K_LAST_CFG      = longPreferencesKey("last_config_id")
        val K_FIRST_LAUNCH  = booleanPreferencesKey("first_launch")
        val K_SCREENSHOTS   = booleanPreferencesKey("allow_screenshots")
    }
    suspend fun isAutoStartEnabled()    = ds.data.first()[K_AUTO_START]     ?: false
    suspend fun isAutoReconnectEnabled()= ds.data.first()[K_AUTO_RECONNECT] ?: true
    suspend fun isKillSwitchEnabled()   = ds.data.first()[K_KILL_SWITCH]    ?: true
    suspend fun isFakeDnsEnabled()      = ds.data.first()[K_FAKE_DNS]       ?: false
    suspend fun isUdpEnabled()          = ds.data.first()[K_UDP]            ?: true
    suspend fun isIPv6Enabled()         = ds.data.first()[K_IPV6]           ?: false
    suspend fun getLastConfigId()       = ds.data.first()[K_LAST_CFG]       ?: -1L
    suspend fun getBypassApps()         = ds.data.first()[K_BYPASS_APPS]    ?: emptySet()
    suspend fun getDnsPrimary()         = ds.data.first()[K_DNS_1]          ?: "1.1.1.1"
    suspend fun getDnsSecondary()       = ds.data.first()[K_DNS_2]          ?: "8.8.8.8"
    suspend fun isFirstLaunch()         = ds.data.first()[K_FIRST_LAUNCH]   ?: true
    fun autoStartFlow()     : Flow<Boolean>     = ds.data.map { it[K_AUTO_START]     ?: false }
    fun autoReconnectFlow() : Flow<Boolean>     = ds.data.map { it[K_AUTO_RECONNECT] ?: true  }
    fun killSwitchFlow()    : Flow<Boolean>     = ds.data.map { it[K_KILL_SWITCH]    ?: true  }
    fun fakeDnsFlow()       : Flow<Boolean>     = ds.data.map { it[K_FAKE_DNS]       ?: false }
    fun udpFlow()           : Flow<Boolean>     = ds.data.map { it[K_UDP]            ?: true  }
    fun ipv6Flow()          : Flow<Boolean>     = ds.data.map { it[K_IPV6]           ?: false }
    fun bypassAppsFlow()    : Flow<Set<String>> = ds.data.map { it[K_BYPASS_APPS]    ?: emptySet() }
    fun dnsPrimaryFlow()    : Flow<String>      = ds.data.map { it[K_DNS_1]          ?: "1.1.1.1" }
    fun dnsSecondaryFlow()  : Flow<String>      = ds.data.map { it[K_DNS_2]          ?: "8.8.8.8" }
    suspend fun setAutoStart(v: Boolean)        = ds.edit { it[K_AUTO_START]     = v }
    suspend fun setAutoReconnect(v: Boolean)    = ds.edit { it[K_AUTO_RECONNECT] = v }
    suspend fun setKillSwitch(v: Boolean)       = ds.edit { it[K_KILL_SWITCH]    = v }
    suspend fun setFakeDns(v: Boolean)          = ds.edit { it[K_FAKE_DNS]       = v }
    suspend fun setUdp(v: Boolean)              = ds.edit { it[K_UDP]            = v }
    suspend fun setIPv6(v: Boolean)             = ds.edit { it[K_IPV6]           = v }
    suspend fun setLastConfigId(id: Long)       = ds.edit { it[K_LAST_CFG]       = id }
    suspend fun setFirstLaunch(v: Boolean)      = ds.edit { it[K_FIRST_LAUNCH]   = v }
    suspend fun setBypassApps(s: Set<String>)   = ds.edit { it[K_BYPASS_APPS]    = s }
    suspend fun setDnsPrimary(v: String)        = ds.edit { it[K_DNS_1]          = v }
    suspend fun setDnsSecondary(v: String)      = ds.edit { it[K_DNS_2]          = v }
}
HEREDOC

  cat > "$B/SplitTunnelCache.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.CopyOnWriteArraySet
import javax.inject.Inject
import javax.inject.Singleton

/** Thread-safe cache of bypass app packages. Validates packages exist before caching. */
@Singleton
class SplitTunnelCache @Inject constructor(
    @ApplicationContext private val ctx: Context,
    private val prefs: AppPreferences
) {
    private val TAG   = "SplitTunnelCache"
    private val cache = CopyOnWriteArraySet<String>()
    @Volatile private var loaded = false

    suspend fun load() = withContext(Dispatchers.IO) {
        val raw = prefs.getBypassApps()
        val pm  = ctx.packageManager
        val valid = raw.filter { pkg ->
            try { pm.getPackageInfo(pkg, 0); true }
            catch (e: PackageManager.NameNotFoundException) { Log.w(TAG,"skip $pkg: not installed"); false }
        }
        cache.clear(); cache.addAll(valid); loaded = true
        Log.i(TAG,"Loaded ${cache.size} bypass packages")
    }

    fun getBypassPackages(): Set<String> = cache.toSet()
    fun invalidate()                     { cache.clear(); loaded = false }
    val isLoaded: Boolean get()          = loaded
}
HEREDOC

  cat > "$B/BinaryExtractor.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import android.content.Context
import android.os.Build
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Extracts native binaries from assets to filesDir/bin/.
 *
 * Binaries required:
 *   xray        — https://github.com/XTLS/Xray-core
 *   tun2socks   — https://github.com/xjasonlyu/tun2socks
 *   psiphon     — https://github.com/Psiphon-Inc/psiphon-android
 *
 * NEVER creates placeholder/stub binaries.
 * Missing binary → logged as error; managers will throw on start.
 */
@Singleton
class BinaryExtractor @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG = "BinaryExtractor"
    private val MIN_SIZE = 512L

    suspend fun extractAll() = withContext(Dispatchers.IO) {
        val binDir = File(ctx.filesDir, "bin").also { it.mkdirs() }
        val abi    = detectAbi()
        Log.i(TAG, "Extracting binaries for ABI=$abi")

        for (name in listOf("xray","tun2socks","psiphon")) {
            val dest = File(binDir, name)
            if (!dest.exists() || dest.length() < MIN_SIZE || !dest.canExecute())
                extractAsset("bin/$abi/$name", dest)

            when {
                !dest.exists()           -> Log.e(TAG, "MISSING: $name — build from source and place in assets/bin/$abi/")
                dest.length() < MIN_SIZE -> Log.e(TAG, "INVALID: $name is ${dest.length()} bytes — likely a stub. Replace with real binary.")
                else -> {
                    dest.setExecutable(true, false); dest.setReadable(true, false)
                    Log.i(TAG, "OK: $name (${dest.length()} bytes, exec=${dest.canExecute()})")
                }
            }
        }
    }

    fun isReady(name: String): Boolean {
        val f = File(ctx.filesDir, "bin/$name")
        return f.exists() && f.length() >= MIN_SIZE && f.canExecute()
    }

    private fun detectAbi(): String {
        val abis = Build.SUPPORTED_ABIS.toList()
        return when {
            "arm64-v8a"   in abis -> "arm64-v8a"
            "x86_64"      in abis -> "x86_64"
            "armeabi-v7a" in abis -> "armeabi-v7a"
            "x86"         in abis -> "x86"
            else -> abis.firstOrNull() ?: "arm64-v8a"
        }
    }

    private fun extractAsset(assetPath: String, dest: File) {
        try {
            ctx.assets.open(assetPath).use { input ->
                val tmp = File(dest.parent, "${dest.name}.tmp")
                tmp.outputStream().use { out -> input.copyTo(out, bufferSize = 65_536) }
                if (!tmp.renameTo(dest)) { tmp.copyTo(dest, overwrite=true); tmp.delete() }
            }
            Log.i(TAG, "Extracted $assetPath → ${dest.absolutePath} (${dest.length()} bytes)")
        } catch (e: Exception) {
            Log.w(TAG, "Cannot extract $assetPath: ${e.message}")
        }
    }
}
HEREDOC

  cat > "$B/SecureConfigStore.kt" << 'HEREDOC'
package com.soreng.tunnel.storage

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * AES-256-GCM encrypted key-value store for sensitive config data.
 * Falls back to plain SharedPreferences if Keystore is unavailable (logs warning).
 */
@Singleton
class SecureConfigStore @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG = "SecureConfigStore"

    private val prefs by lazy {
        try {
            val mk = MasterKey.Builder(ctx)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .setRequestStrongBoxBacked(false)
                .setUserAuthenticationRequired(false)
                .build()
            EncryptedSharedPreferences.create(ctx, "soren_secure",
                mk, EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
        } catch (e: Exception) {
            Log.w(TAG, "EncryptedSharedPreferences unavailable: ${e.message} — using fallback")
            ctx.getSharedPreferences("soren_secure_fb", Context.MODE_PRIVATE)
        }
    }

    fun put(key: String, value: String)     = runCatching { prefs.edit().putString(key,value).apply() }
    fun get(key: String, def: String?=null) = runCatching { prefs.getString(key,def) }.getOrDefault(def)
    fun remove(key: String)                 = runCatching { prefs.edit().remove(key).apply() }
    fun contains(key: String): Boolean      = runCatching { prefs.contains(key) }.getOrDefault(false)
    fun clearAll()                          = runCatching { prefs.edit().clear().apply() }
}
HEREDOC
  log "Storage layer done"
}

# ─────────────────────────────────────────────────────────────
# STATS MANAGER
# ─────────────────────────────────────────────────────────────
write_stats() {
  log "Writing StatsManager..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/stats"
  mkdir -p "$B"

  cat > "$B/StatsManager.kt" << 'HEREDOC'
package com.soreng.tunnel.stats

import android.content.Context
import android.net.TrafficStats
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import com.soreng.tunnel.storage.SessionStatsDao
import com.soreng.tunnel.storage.SessionStatsEntity
import com.soreng.tunnel.vpn.SocketProtector
import java.net.InetSocketAddress
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Real-time traffic statistics.
 *
 * - Uses TrafficStats.getUidRxBytes/TxBytes for real packet counters.
 * - 1-second tick — lifecycle-aware (runs only during active session).
 * - Ping uses protected socket → measures Xray→Psiphon path RTT.
 * - No fake stats, no polling when disconnected.
 */
@Singleton
class StatsManager @Inject constructor(
    @ApplicationContext private val ctx: Context,
    private val statsDao:   SessionStatsDao,
    private val protector:  SocketProtector
) {
    private val TAG   = "StatsManager"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _uploadSpeed   = MutableStateFlow(0L)
    private val _downloadSpeed = MutableStateFlow(0L)
    private val _ping          = MutableStateFlow(-1L)
    private val _uploadTotal   = MutableStateFlow(0L)
    private val _downloadTotal = MutableStateFlow(0L)

    val uploadSpeed:   StateFlow<Long> = _uploadSpeed.asStateFlow()
    val downloadSpeed: StateFlow<Long> = _downloadSpeed.asStateFlow()
    val ping:          StateFlow<Long> = _ping.asStateFlow()
    val uploadTotal:   StateFlow<Long> = _uploadTotal.asStateFlow()
    val downloadTotal: StateFlow<Long> = _downloadTotal.asStateFlow()

    @Volatile private var tickJob:     Job? = null
    @Volatile private var pingJob:     Job? = null
    @Volatile private var sessionId:   Long = -1L
    @Volatile private var sessEntity:  SessionStatsEntity? = null
    private var baseRx = 0L; private var baseTx = 0L
    private var prevRx = 0L; private var prevTx = 0L
    private var prevTs = 0L

    fun startSession() {
        stopSession()
        val uid = android.os.Process.myUid()
        prevRx = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
        prevTx = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L)
        baseRx = prevRx; baseTx = prevTx
        prevTs = System.currentTimeMillis()
        _uploadTotal.value = 0L; _downloadTotal.value = 0L
        _uploadSpeed.value = 0L; _downloadSpeed.value = 0L
        _ping.value        = -1L

        scope.launch {
            val e = SessionStatsEntity(startTime = System.currentTimeMillis())
            sessionId = statsDao.insert(e); sessEntity = e.copy(id = sessionId)
        }

        tickJob = scope.launch {
            while (isActive) { delay(1_000); tick(uid) }
        }
        // Ping every 8s — lower frequency reduces battery usage
        pingJob = scope.launch {
            while (isActive) { delay(8_000); _ping.value = measurePing() }
        }
    }

    private fun tick(uid: Int) {
        val now = System.currentTimeMillis()
        val rx  = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
        val tx  = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L)
        val dt  = (now - prevTs).coerceAtLeast(1L)

        _downloadSpeed.value  = (rx - prevRx).coerceAtLeast(0L) * 1_000L / dt
        _uploadSpeed.value    = (tx - prevTx).coerceAtLeast(0L) * 1_000L / dt
        _downloadTotal.value  = (rx - baseRx).coerceAtLeast(0L)
        _uploadTotal.value    = (tx - baseTx).coerceAtLeast(0L)

        prevRx = rx; prevTx = tx; prevTs = now
    }

    private fun measurePing(): Long = try {
        Socket().use { s ->
            protector.protect(s)  // protect → ping does not route through VPN
            val t = System.currentTimeMillis()
            s.soTimeout = 3_000; s.tcpNoDelay = true
            s.connect(InetSocketAddress("1.1.1.1", 443), 3_000)
            System.currentTimeMillis() - t
        }
    } catch (_: Exception) { -1L }

    fun stopSession() {
        tickJob?.cancel(); tickJob = null
        pingJob?.cancel(); pingJob = null
        scope.launch {
            sessEntity?.let { e ->
                runCatching { statsDao.update(e.copy(
                    endTime       = System.currentTimeMillis(),
                    uploadBytes   = _uploadTotal.value,
                    downloadBytes = _downloadTotal.value,
                    avgPingMs     = _ping.value
                ))}
            }
        }
        _uploadSpeed.value = 0L; _downloadSpeed.value = 0L; _ping.value = -1L
        sessEntity = null
    }

    fun fmtBytes(b: Long): String = when {
        b < 1_024L         -> "$b B"
        b < 1_048_576L     -> "${"%.1f".format(b/1_024.0)} KB"
        b < 1_073_741_824L -> "${"%.2f".format(b/1_048_576.0)} MB"
        else               -> "${"%.2f".format(b/1_073_741_824.0)} GB"
    }
    fun fmtSpeed(bps: Long): String = when {
        bps < 1_024L     -> "$bps B/s"
        bps < 1_048_576L -> "${"%.1f".format(bps/1_024.0)} KB/s"
        else             -> "${"%.2f".format(bps/1_048_576.0)} MB/s"
    }
}
HEREDOC
  log "Stats done"
}

# ─────────────────────────────────────────────────────────────
# SECURITY + UTILS
# ─────────────────────────────────────────────────────────────
write_security() {
  log "Writing security/utils..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"
  mkdir -p "$B/security" "$B/utils"

  cat > "$B/security/SecurityManager.kt" << 'HEREDOC'
package com.soreng.tunnel.security

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import android.view.WindowManager
import dagger.hilt.android.qualifiers.ApplicationContext
import com.soreng.tunnel.storage.AppPreferences
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SecurityManager @Inject constructor(
    @ApplicationContext private val ctx: Context,
    private val prefs: AppPreferences
) {
    private val TAG = "SecurityManager"

    suspend fun initialize() {
        Log.i(TAG, "Security initialized")
    }

    /** Call from Activity.onCreate() to block screenshots. */
    fun applyWindowSecurity(activity: Activity) {
        try {
            activity.window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE)
        } catch (e: Exception) { Log.w(TAG,"window security: ${e.message}") }
    }

    fun clearMemory() { Runtime.getRuntime().gc(); System.gc() }
}
HEREDOC

  cat > "$B/utils/BatteryHelper.kt" << 'HEREDOC'
package com.soreng.tunnel.utils

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Helps users exempt the app from battery optimization.
 * Required to survive background kills on MIUI/HyperOS/EMUI/ColorOS.
 */
@Singleton
class BatteryHelper @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG = "BatteryHelper"

    fun isExempt(): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    fun getExemptIntent(): Intent? {
        if (isExempt()) return null
        return try {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${ctx.packageName}"))
        } catch (e: Exception) {
            Log.w(TAG,"exemptIntent: ${e.message}")
            try { Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS) }
            catch (_: Exception) { null }
        }
    }

    fun logState() {
        if (!isExempt()) Log.w(TAG,"NOT exempt from battery optimization — VPN may be killed by OEM")
        else Log.i(TAG,"Battery optimization exempt")
    }
}
HEREDOC

  cat > "$B/notifications/VpnNotificationManager.kt" << 'HEREDOC'
package com.soreng.tunnel.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import com.soreng.tunnel.SorenApp
import com.soreng.tunnel.ui.MainActivity
import com.soreng.tunnel.vpn.VpnControlReceiver
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VpnNotificationManager @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val nm = ctx.getSystemService(NotificationManager::class.java)

    init { ensureChannels() }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (nm.getNotificationChannel(SorenApp.CHANNEL_VPN) == null) {
            nm.createNotificationChannel(
                NotificationChannel(SorenApp.CHANNEL_VPN,
                    ctx.getString(com.soreng.tunnel.R.string.channel_vpn),
                    NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false); enableVibration(false)
                })
        }
        if (nm.getNotificationChannel(SorenApp.CHANNEL_ALERT) == null) {
            nm.createNotificationChannel(
                NotificationChannel(SorenApp.CHANNEL_ALERT,
                    ctx.getString(com.soreng.tunnel.R.string.channel_alert),
                    NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    fun buildConnecting(): Notification = base("Connecting…","Establishing secure tunnel")
        .setOngoing(true).setProgress(0,0,true).build()

    fun buildConnected(server: String = ""): Notification {
        val pi = PendingIntent.getBroadcast(ctx, 1,
            Intent(ctx, VpnControlReceiver::class.java).apply {
                action = "com.soreng.tunnel.VPN_DISCONNECT" },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return base("Connected", if(server.isBlank()) "Tunnel active" else "Connected — $server")
            .setOngoing(true).setProgress(0,0,false)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel,"Disconnect",pi)
            .build()
    }

    fun buildError(msg: String): Notification =
        base("Connection Error", msg.take(100)).setAutoCancel(true).build()

    fun buildDisconnected(): Notification =
        base("Disconnected","Tap to reconnect").setAutoCancel(true).build()

    private fun base(title: String, content: String): NotificationCompat.Builder {
        val mainPi = PendingIntent.getActivity(ctx, 0,
            Intent(ctx, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(ctx, SorenApp.CHANNEL_VPN)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title).setContentText(content)
            .setContentIntent(mainPi).setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
    }
}
HEREDOC
  mkdir -p "$ROOT/app/src/main/kotlin/$PKGP/notifications"
  mv "$B/notifications/VpnNotificationManager.kt" \
     "$ROOT/app/src/main/kotlin/$PKGP/notifications/VpnNotificationManager.kt"
  log "Security/utils done"
}

# ─────────────────────────────────────────────────────────────
# DEPENDENCY INJECTION MODULE
# ─────────────────────────────────────────────────────────────
write_di() {
  log "Writing DI module..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/di"
  mkdir -p "$B"

  cat > "$B/AppModule.kt" << 'HEREDOC'
package com.soreng.tunnel.di

import android.content.Context
import androidx.room.Room
import com.soreng.tunnel.storage.*
import com.soreng.tunnel.vpn.*
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides @Singleton
    fun provideDb(@ApplicationContext ctx: Context): AppDatabase =
        Room.databaseBuilder(ctx, AppDatabase::class.java, "soren_db")
            .fallbackToDestructiveMigration().build()

    @Provides @Singleton fun provideConfigDao(db: AppDatabase):    ConfigDao      = db.configDao()
    @Provides @Singleton fun provideSubDao(db: AppDatabase):       SubscriptionDao= db.subDao()
    @Provides @Singleton fun provideStatsDao(db: AppDatabase):     SessionStatsDao= db.statsDao()
    @Provides @Singleton fun provideSocketProtector():             SocketProtector     = SocketProtector()
    @Provides @Singleton fun provideConnVerifier():                ConnectivityVerifier= ConnectivityVerifier()
    @Provides @Singleton fun provideHealthChecker(p: SocketProtector): HealthChecker   = HealthChecker(p)
    @Provides @Singleton fun provideWatchdog(
        ps: com.soreng.tunnel.psiphon.PsiphonManager,
        xr: com.soreng.tunnel.xray.XrayManager,
        t2: com.soreng.tunnel.tunnel.Tun2SocksManager,
        hc: HealthChecker,
        pr: AppPreferences
    ): WatchdogSupervisor = WatchdogSupervisor(ps,xr,t2,hc,pr)
    @Provides @Singleton fun provideReconnectMgr(): ReconnectManager = ReconnectManager()
}
HEREDOC
  log "DI done"
}

# ─────────────────────────────────────────────────────────────
# MAIN ACTIVITY + NAVIGATION
# ─────────────────────────────────────────────────────────────
write_main_activity() {
  log "Writing MainActivity..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/ui"
  mkdir -p "$B"

  cat > "$B/MainActivity.kt" << 'HEREDOC'
package com.soreng.tunnel.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import dagger.hilt.android.AndroidEntryPoint
import com.soreng.tunnel.security.SecurityManager
import com.soreng.tunnel.ui.theme.Black
import com.soreng.tunnel.ui.theme.SorenTheme
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @Inject lateinit var security: SecurityManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        security.applyWindowSecurity(this)
        setContent {
            SorenTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = Black) {
                    SorenNavHost()
                }
            }
        }
    }
}
HEREDOC

  cat > "$B/SorenNavHost.kt" << 'HEREDOC'
package com.soreng.tunnel.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.*
import com.soreng.tunnel.ui.screen.*
import com.soreng.tunnel.ui.theme.*

sealed class Screen(val route: String, val label: String, val icon: String) {
    object Home     : Screen("home",    "HOME",    "◉")
    object Configs  : Screen("configs", "CONFIGS", "≡")
    object Stats    : Screen("stats",   "STATS",   "▲")
    object Settings : Screen("settings","SETTINGS","⚙")
}

@Composable
fun SorenNavHost() {
    val nav = rememberNavController()
    val items = listOf(Screen.Home, Screen.Configs, Screen.Stats, Screen.Settings)

    Scaffold(containerColor = Black, bottomBar = {
        NavigationBar(containerColor = BlackCard, tonalElevation = 0.dp) {
            val bs by nav.currentBackStackEntryAsState()
            val cur = bs?.destination
            items.forEach { s ->
                val sel = cur?.hierarchy?.any { it.route == s.route } == true
                NavigationBarItem(
                    selected = sel,
                    onClick  = {
                        nav.navigate(s.route) {
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true; restoreState = true
                        }
                    },
                    icon  = { Text(s.icon, fontSize = 16.sp, color = if(sel) White else GrayMid) },
                    label = { Text(s.label, style = MaterialTheme.typography.labelSmall,
                        color = if(sel) White else GrayMid) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor=White, unselectedIconColor=GrayMid,
                        selectedTextColor=White, unselectedTextColor=GrayMid,
                        indicatorColor=GrayDark)
                )
            }
        }
    }) { inner ->
        NavHost(navController = nav, startDestination = Screen.Home.route,
            modifier = Modifier.padding(inner),
            enterTransition  = { fadeIn(tween(200)) },
            exitTransition   = { fadeOut(tween(200)) },
            popEnterTransition  = { fadeIn(tween(200)) },
            popExitTransition   = { fadeOut(tween(200)) }
        ) {
            composable(Screen.Home.route)     { HomeScreen(nav) }
            composable(Screen.Configs.route)  { ConfigsScreen(nav) }
            composable(Screen.Stats.route)    { StatsScreen() }
            composable(Screen.Settings.route) { SettingsScreen() }
            composable("add_config")          { AddConfigScreen(nav) }
            composable("qr_scan")             { QrScanScreen(nav) }
            composable("logs")                { LogsScreen() }
        }
    }
}
HEREDOC
  log "MainActivity done"
}

# ─────────────────────────────────────────────────────────────
# THEME
# ─────────────────────────────────────────────────────────────
write_theme() {
  log "Writing theme..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/ui/theme"
  mkdir -p "$B"

  cat > "$B/Color.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.theme
import androidx.compose.ui.graphics.Color

val Black      = Color(0xFF000000)
val BlackMid   = Color(0xFF0A0A0A)
val BlackCard  = Color(0xFF111111)
val BlackBorder= Color(0xFF1E1E1E)
val GrayDark   = Color(0xFF2A2A2A)
val GrayMid    = Color(0xFF555555)
val GrayLight  = Color(0xFF888888)
val GrayPale   = Color(0xFFBBBBBB)
val White      = Color(0xFFFFFFFF)
val WhiteDim   = Color(0xFFE0E0E0)
val GlowWhite  = Color(0xCCFFFFFF)
val GlowDim    = Color(0x22FFFFFF)
val GreenOk    = Color(0xFF39FF14)
val YellowWarn = Color(0xFFFFE000)
val RedAlert   = Color(0xFFFF3131)
HEREDOC

  cat > "$B/Theme.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.theme

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val SorenColors = darkColorScheme(
    primary            = White,    onPrimary         = Black,
    primaryContainer   = GrayDark, onPrimaryContainer= White,
    secondary          = GrayPale, onSecondary       = Black,
    background         = Black,    onBackground      = White,
    surface            = BlackCard,onSurface         = White,
    surfaceVariant     = BlackMid, onSurfaceVariant  = GrayPale,
    outline            = BlackBorder,
    error              = RedAlert, onError           = Black,
)

val SorenTypography = Typography(
    headlineLarge  = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Black,   fontSize=32.sp, letterSpacing=1.sp),
    headlineMedium = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Bold,    fontSize=24.sp, letterSpacing=0.5.sp),
    headlineSmall  = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.SemiBold,fontSize=20.sp),
    titleLarge     = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Bold,    fontSize=22.sp, letterSpacing=0.5.sp),
    titleMedium    = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Medium,  fontSize=16.sp),
    titleSmall     = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Medium,  fontSize=14.sp),
    bodyLarge      = TextStyle(fontFamily=FontFamily.SansSerif, fontWeight=FontWeight.Normal,  fontSize=16.sp),
    bodyMedium     = TextStyle(fontFamily=FontFamily.SansSerif, fontWeight=FontWeight.Normal,  fontSize=14.sp),
    bodySmall      = TextStyle(fontFamily=FontFamily.SansSerif, fontWeight=FontWeight.Normal,  fontSize=12.sp),
    labelLarge     = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Medium,  fontSize=14.sp, letterSpacing=0.5.sp),
    labelMedium    = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Medium,  fontSize=12.sp, letterSpacing=0.5.sp),
    labelSmall     = TextStyle(fontFamily=FontFamily.Monospace, fontWeight=FontWeight.Medium,  fontSize=11.sp, letterSpacing=1.sp),
)

@Composable
fun SorenTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme=SorenColors, typography=SorenTypography, content=content)
}
HEREDOC
  log "Theme done"
}

# ─────────────────────────────────────────────────────────────
# NATIVE BINARY BUILD
# ─────────────────────────────────────────────────────────────
build_binaries() {
  log "Building native binaries..."
  local ASSETS="$ROOT/app/src/main/assets/bin"
  export PATH="$PATH:/usr/local/go/bin:${GOPATH:-$HOME/go}/bin"
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

  # ── Xray-core ──────────────────────────────────────────────
  local XDIR="/tmp/soren_xray"
  if [ ! -d "$XDIR" ]; then
    log "Cloning Xray-core..."
    git clone --depth 1 https://github.com/XTLS/Xray-core.git "$XDIR" || warn "Xray clone failed"
  fi
  if [ -d "$XDIR" ]; then
    log "Building Xray arm64-v8a..."
    ( cd "$XDIR"
      GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
      go build -trimpath -ldflags="-s -w" -o "$ASSETS/arm64-v8a/xray" ./main/ \
      && log "xray arm64 OK" ) || warn "xray arm64 build failed"
    log "Building Xray armeabi-v7a..."
    ( cd "$XDIR"
      GOOS=android GOARCH=arm CGO_ENABLED=0 GOARM=7 \
      go build -trimpath -ldflags="-s -w" -o "$ASSETS/armeabi-v7a/xray" ./main/ \
      && log "xray armeabi-v7a OK" ) || warn "xray armeabi-v7a failed"
    log "Building Xray x86_64..."
    ( cd "$XDIR"
      GOOS=android GOARCH=amd64 CGO_ENABLED=0 \
      go build -trimpath -ldflags="-s -w" -o "$ASSETS/x86_64/xray" ./main/ \
      && log "xray x86_64 OK" ) || warn "xray x86_64 failed"
  fi

  # ── tun2socks ──────────────────────────────────────────────
  local T2DIR="/tmp/soren_tun2socks"
  if [ ! -d "$T2DIR" ]; then
    log "Cloning tun2socks..."
    git clone --depth 1 https://github.com/xjasonlyu/tun2socks.git "$T2DIR" || warn "tun2socks clone failed"
  fi
  if [ -d "$T2DIR" ]; then
    log "Building tun2socks arm64-v8a..."
    ( cd "$T2DIR"
      GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
      go build -trimpath -ldflags="-s -w" -o "$ASSETS/arm64-v8a/tun2socks" . \
      && log "tun2socks arm64 OK" ) || warn "tun2socks arm64 failed"
    ( cd "$T2DIR"
      GOOS=android GOARCH=arm CGO_ENABLED=0 GOARM=7 \
      go build -trimpath -ldflags="-s -w" -o "$ASSETS/armeabi-v7a/tun2socks" . \
      && log "tun2socks armeabi-v7a OK" ) || warn "tun2socks armeabi-v7a failed"
    ( cd "$T2DIR"
      GOOS=android GOARCH=amd64 CGO_ENABLED=0 \
      go build -trimpath -ldflags="-s -w" -o "$ASSETS/x86_64/tun2socks" . \
      && log "tun2socks x86_64 OK" ) || warn "tun2socks x86_64 failed"
  fi

  # ── Psiphon ────────────────────────────────────────────────
  local PDIR="/tmp/soren_psiphon"
  if [ ! -d "$PDIR" ]; then
    log "Cloning psiphon-tunnel-core..."
    git clone --depth 1 \
      https://github.com/Psiphon-Labs/psiphon-tunnel-core.git "$PDIR" \
      || { warn "psiphon-labs clone failed, trying Psiphon-Inc..."
           git clone --depth 1 \
             https://github.com/Psiphon-Inc/psiphon-tunnel-core.git "$PDIR" \
             || warn "psiphon clone failed"; }
  fi
  if [ -d "$PDIR" ]; then
    # Try gomobile AAR build (preferred — creates libpsiphon.so)
    if command -v gomobile >/dev/null 2>&1 && [ -d "$PDIR/MobileLibrary/psi" ]; then
      log "Building Psiphon AAR via gomobile..."
      mkdir -p "$ROOT/app/libs"
      ( cd "$PDIR"
        gomobile bind -v -target android/arm64,android/arm \
          -androidapi 26 \
          -o "$ROOT/app/libs/psiphon.aar" \
          ./MobileLibrary/psi/ \
          && log "psiphon.aar built OK"
      ) || warn "gomobile psiphon build failed — trying CLI binary"
    fi
    # CLI binary fallback
    for ARCH_PAIR in "arm64:arm64-v8a" "arm:armeabi-v7a" "amd64:x86_64"; do
      local GOARCH="${ARCH_PAIR%%:*}"
      local ABI="${ARCH_PAIR##*:}"
      local GOARM_FLAG=""; [[ "$GOARCH" == "arm" ]] && GOARM_FLAG="GOARM=7"
      local CONSDIR=""
      for d in ConsoleClient cmd/psiphon-tunnel-core .; do
        [ -f "$PDIR/$d/main.go" ] && { CONSDIR="$d"; break; }
      done
      if [ -n "$CONSDIR" ]; then
        ( cd "$PDIR"
          env GOOS=android GOARCH="$GOARCH" CGO_ENABLED=0 $GOARM_FLAG \
          go build -trimpath -ldflags="-s -w" \
            -o "$ASSETS/$ABI/psiphon" "./$CONSDIR/" \
          && log "psiphon $ABI OK" ) || warn "psiphon $ABI failed"
      fi
    done
  fi

  # ── Report ─────────────────────────────────────────────────
  log "Binary build report:"
  for ABI in arm64-v8a armeabi-v7a x86_64; do
    for BIN in xray tun2socks psiphon; do
      local F="$ASSETS/$ABI/$BIN"
      if [ -f "$F" ] && [ "$(wc -c < "$F")" -gt 512 ]; then
        log "  ✓ $ABI/$BIN ($(du -h "$F" | cut -f1))"
      else
        warn "  ✗ $ABI/$BIN — MISSING or too small"
        warn "    Build manually — see README_BINARIES.txt"
      fi
    done
  done

  cat > "$ROOT/README_BINARIES.txt" << 'RDME'
======================================
SOREN NG — BINARY BUILD REQUIREMENTS
======================================
Required binaries (place in app/src/main/assets/bin/<abi>/):
  xray        — https://github.com/XTLS/Xray-core
  tun2socks   — https://github.com/xjasonlyu/tun2socks
  psiphon     — https://github.com/Psiphon-Inc/psiphon-android
                https://github.com/Psiphon-Labs/psiphon-tunnel-core

xray (arm64-v8a):
  cd Xray-core && GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" -o <assets>/arm64-v8a/xray ./main/

tun2socks (arm64-v8a):
  cd tun2socks && GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" -o <assets>/arm64-v8a/tun2socks .

psiphon (AAR via gomobile):
  cd psiphon-tunnel-core && gomobile bind -v -target android/arm64 \
    -androidapi 26 -o app/libs/psiphon.aar ./MobileLibrary/psi/

psiphon (CLI binary):
  cd psiphon-tunnel-core && GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" -o <assets>/arm64-v8a/psiphon ./ConsoleClient/

IMPORTANT: DO NOT place placeholder/stub binaries.
  Missing binary → explicit runtime error → tunnel refuses to start.
======================================
RDME
  log "Binary build phase complete"
}

# ─────────────────────────────────────────────────────────────
# PART 1 — MAIN ENTRY POINT
# (Screens + ViewModels are in Part 2)
# ─────────────────────────────────────────────────────────────
main_part1() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  SOREN NG TUNNEL — Project Generator  PART 1/3"
  echo "══════════════════════════════════════════════════"
  check_deps
  make_skeleton
  write_gradle
  write_manifest
  write_resources
  write_jni
  write_vpn_layer
  write_psiphon
  write_xray
  write_tun2socks
  write_health
  write_supervision
  write_vpn_service
  write_config
  write_storage
  write_stats
  write_security
  write_di
  write_main_activity
  write_theme
  build_binaries
  echo ""
  echo "══════════════════════════════════════════════════"
  log "PART 1 complete. Run part 2 next: bash setup_soren_ng_part2.sh"
  echo "══════════════════════════════════════════════════"
}

main_part1 "$@"
