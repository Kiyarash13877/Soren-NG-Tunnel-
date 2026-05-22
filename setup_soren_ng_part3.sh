#!/usr/bin/env bash
# =============================================================
# setup_soren_ng_part3.sh — Soren NG Tunnel
# Final wiring: accompanist permissions, OEM hardening,
# WorkManager keepalive, ProcessGuard zombie cleanup,
# WakeLock manager, Android 13+ compat, final validations
# Run AFTER part 2: bash setup_soren_ng_part3.sh
# PART 3 of 3
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

[ -d "$ROOT" ] || die "SorenNGTunnel not found — run parts 1 and 2 first"

# ─────────────────────────────────────────────────────────────
# WAKE LOCK MANAGER — safe acquire/release, 4-hour cap
# ─────────────────────────────────────────────────────────────
write_wakelock() {
  log "Writing WakeLockManager..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"
  mkdir -p "$B"

  cat > "$B/WakeLockManager.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.content.Context
import android.os.PowerManager
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages a PARTIAL_WAKE_LOCK for the VPN tunnel.
 *
 * Rules:
 *  - Acquired only while VPN is actively routing traffic.
 *  - 4-hour safety cap prevents runaway battery drain.
 *  - Reference-counted=false prevents double-release crashes.
 *  - Always released in VPN cleanup path.
 *  - Thread-safe via synchronized block.
 */
@Singleton
class WakeLockManager @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG = "WakeLockManager"
    private val pm  = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
    @Volatile private var lock: PowerManager.WakeLock? = null
    private val mutex = Any()

    fun acquire() = synchronized(mutex) {
        if (lock?.isHeld == true) { Log.d(TAG,"already held"); return@synchronized }
        val wl = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "com.soreng.tunnel:VpnWakeLock"
        ).apply {
            setReferenceCounted(false)
            acquire(4 * 60 * 60 * 1_000L)   // 4h safety cap
        }
        lock = wl
        Log.i(TAG, "WakeLock acquired")
    }

    fun release() = synchronized(mutex) {
        val wl = lock ?: return@synchronized
        try { if (wl.isHeld) { wl.release(); Log.i(TAG,"WakeLock released") } }
        catch (e: Exception) { Log.w(TAG,"release: ${e.message}") }
        finally { lock = null }
    }

    val isHeld: Boolean get() = synchronized(mutex) { lock?.isHeld == true }
}
HEREDOC
  log "WakeLockManager done"
}

# ─────────────────────────────────────────────────────────────
# PROCESS GUARD — zombie cleanup, PID file management
# ─────────────────────────────────────────────────────────────
write_process_guard() {
  log "Writing ProcessGuard..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"

  cat > "$B/ProcessGuard.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.content.Context
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Scans /proc for zombie native daemons owned by this UID and kills them.
 * Runs at startup to clean up from previous crash/kill.
 * Also manages PID files for process tracking.
 */
@Singleton
class ProcessGuard @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG = "ProcessGuard"

    suspend fun killZombies() = withContext(Dispatchers.IO) {
        val myUid  = android.os.Process.myUid()
        val binDir = File(ctx.filesDir, "bin").absolutePath
        val targets = listOf("xray","tun2socks","psiphon")

        try {
            File("/proc").listFiles { f -> f.name.all { it.isDigit() } }
                ?.forEach { pidDir ->
                    try {
                        val pid = pidDir.name.toIntOrNull() ?: return@forEach
                        // Check UID matches ours
                        val status = File(pidDir, "status")
                        if (!status.exists()) return@forEach
                        val uidLine = status.readLines().find { it.startsWith("Uid:") } ?: return@forEach
                        val uid = uidLine.split("\t").getOrNull(1)?.trim()?.toIntOrNull() ?: return@forEach
                        if (uid != myUid) return@forEach
                        // Check exe path is one of our binaries
                        val exe = try { File(pidDir,"exe").canonicalPath } catch (_:Exception) { return@forEach }
                        if (targets.any { name -> exe.endsWith("/$name") && exe.startsWith(binDir) }) {
                            Log.w(TAG,"Killing zombie: pid=$pid exe=$exe")
                            android.os.Process.killProcess(pid)
                        }
                    } catch (_: Exception) { /* permission denied for other pids — expected */ }
                }
        } catch (e: Exception) {
            Log.w(TAG,"killZombies: ${e.message}")
        }

        // Also kill any processes listed in PID files
        for (name in targets) {
            val pidFile = File(ctx.filesDir, "$name.pid")
            if (pidFile.exists()) {
                val pid = pidFile.readText().trim().toIntOrNull()
                if (pid != null && pid > 0) {
                    try {
                        android.os.Process.killProcess(pid)
                        Log.i(TAG,"Killed pid-file process: $name pid=$pid")
                    } catch (_: Exception) {}
                }
                pidFile.delete()
            }
        }
    }

    suspend fun waitForDeath(proc: Process, timeoutMs: Long = 3_000): Boolean =
        withContext(Dispatchers.IO) {
            withTimeoutOrNull(timeoutMs) { while (proc.isAlive) kotlinx.coroutines.delay(100); true } ?: false
        }

    fun writePid(name: String, pid: Long) =
        runCatching { File(ctx.filesDir,"$name.pid").writeText(pid.toString()) }
    fun deletePid(name: String) =
        runCatching { File(ctx.filesDir,"$name.pid").delete() }
    fun readPid(name: String): Long? =
        runCatching { File(ctx.filesDir,"$name.pid").readText().trim().toLongOrNull() }.getOrNull()
}
HEREDOC
  log "ProcessGuard done"
}

# ─────────────────────────────────────────────────────────────
# OEM KEEPALIVE — WorkManager + foreground service persistence
# for MIUI/HyperOS/EMUI/ColorOS aggressive kill
# ─────────────────────────────────────────────────────────────
write_oem_keepalive() {
  log "Writing OEM keepalive worker..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/utils"
  mkdir -p "$B"

  cat > "$B/VpnKeepAliveWorker.kt" << 'HEREDOC'
package com.soreng.tunnel.utils

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.*
import com.soreng.tunnel.vpn.SorenVpnService
import com.soreng.tunnel.vpn.VpnConnectionState
import java.util.concurrent.TimeUnit

/**
 * WorkManager-based keepalive for aggressive OEM battery managers.
 *
 * MIUI/HyperOS/EMUI/ColorOS kill background processes within minutes.
 * This Worker runs every 15 minutes (minimum WorkManager interval) and
 * restarts the VPN if it was killed without user intent.
 *
 * Schedule via VpnKeepAliveWorker.schedule(context).
 */
class VpnKeepAliveWorker(
    ctx: Context,
    params: WorkerParameters
) : CoroutineWorker(ctx, params) {

    companion object {
        private const val TAG       = "VpnKeepAliveWorker"
        private const val WORK_NAME = "soren_vpn_keepalive"

        fun schedule(ctx: Context) {
            val req = PeriodicWorkRequestBuilder<VpnKeepAliveWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build())
                .setBackoffCriteria(BackoffPolicy.LINEAR, 5, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
                WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, req)
            Log.i(TAG, "Keepalive worker scheduled")
        }

        fun cancel(ctx: Context) {
            WorkManager.getInstance(ctx).cancelUniqueWork(WORK_NAME)
            Log.i(TAG, "Keepalive worker cancelled")
        }
    }

    override suspend fun doWork(): Result {
        val state = SorenVpnService.state.value
        Log.d(TAG, "Keepalive check: state=$state")

        // Only restart if was Connected but process is now dead (OEM killed it)
        if (state is VpnConnectionState.Disconnected) {
            // Check if there's a last config to reconnect with
            val prefs = applicationContext.getSharedPreferences(
                "soren_keepalive_prefs", Context.MODE_PRIVATE)
            val lastCfgId = prefs.getLong("last_cfg_id", -1L)
            if (lastCfgId >= 0) {
                Log.i(TAG, "Keepalive: restarting VPN for config $lastCfgId")
                applicationContext.startForegroundService(
                    Intent(applicationContext, SorenVpnService::class.java).apply {
                        action = SorenVpnService.ACTION_START
                        putExtra(SorenVpnService.EXTRA_CONFIG_ID, lastCfgId)
                    })
            }
        }
        return Result.success()
    }
}
HEREDOC

  cat > "$B/OemCompatHelper.kt" << 'HEREDOC'
package com.soreng.tunnel.utils

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OEM-specific compatibility helpers.
 * Detects MIUI/HyperOS/EMUI/ColorOS and logs guidance for users.
 *
 * NOTE: We cannot programmatically disable OEM battery managers.
 * The correct approach is to prompt users to whitelist the app
 * in OEM settings, combined with WorkManager keepalive.
 */
@Singleton
class OemCompatHelper @Inject constructor(
    @ApplicationContext private val ctx: Context
) {
    private val TAG = "OemCompatHelper"

    enum class OemRom { STOCK, MIUI, EMUI, COLOROS, ONEPLUS, SAMSUNG, UNKNOWN }

    val rom: OemRom by lazy { detectRom() }

    private fun detectRom(): OemRom {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand        = Build.BRAND.lowercase()
        return when {
            getSystemProperty("ro.miui.ui.version.name").isNotBlank() -> OemRom.MIUI
            getSystemProperty("ro.build.version.emui").isNotBlank()   -> OemRom.EMUI
            getSystemProperty("ro.build.version.opporom").isNotBlank()-> OemRom.COLOROS
            brand == "oneplus"                                        -> OemRom.ONEPLUS
            manufacturer == "samsung"                                 -> OemRom.SAMSUNG
            else -> OemRom.UNKNOWN
        }
    }

    fun logRomInfo() {
        Log.i(TAG, "ROM: $rom | Manufacturer: ${Build.MANUFACTURER} | " +
            "Brand: ${Build.BRAND} | API: ${Build.VERSION.SDK_INT}")
        if (rom in listOf(OemRom.MIUI, OemRom.EMUI, OemRom.COLOROS)) {
            Log.w(TAG, "Aggressive OEM ROM detected ($rom). " +
                "User should disable battery optimization for Soren NG " +
                "in OEM battery settings to prevent background kills.")
        }
    }

    fun isAggressiveRom(): Boolean =
        rom in listOf(OemRom.MIUI, OemRom.EMUI, OemRom.COLOROS)

    /** Returns OEM-specific settings hint for the user. */
    fun getBatterySettingsHint(): String = when (rom) {
        OemRom.MIUI    -> "Settings → Apps → Soren NG → Battery saver → No restrictions\n" +
                          "Also: Security app → Battery → App battery saver → No restrictions"
        OemRom.EMUI    -> "Settings → Apps → Soren NG → Battery → Allow background activity"
        OemRom.COLOROS -> "Settings → Battery → More → App energy savings → Soren NG → No restriction"
        OemRom.SAMSUNG -> "Settings → Apps → Soren NG → Battery → Unrestricted"
        OemRom.ONEPLUS -> "Settings → Apps → Soren NG → Battery optimization → Don't optimize"
        else           -> "Settings → Apps → Soren NG → Battery → No restrictions"
    }

    private fun getSystemProperty(key: String): String = try {
        val c = Class.forName("android.os.SystemProperties")
        c.getMethod("get", String::class.java).invoke(null, key) as? String ?: ""
    } catch (_: Exception) { "" }
}
HEREDOC
  log "OEM keepalive done"
}

# ─────────────────────────────────────────────────────────────
# ACCOMPANIST PERMISSIONS + UPDATED build.gradle
# ─────────────────────────────────────────────────────────────
write_accompanist_dep() {
  log "Adding accompanist-permissions dependency..."

  # Patch libs.versions.toml to add accompanist
  local TOML="$ROOT/gradle/libs.versions.toml"
  # Add accompanist version
  sed -i 's/^work            = "2.9.1"/work            = "2.9.1"\naccompanist     = "0.34.0"/' "$TOML"
  # Add accompanist library entry
  sed -i 's/^work-runtime             = /accompanist-permissions  = { group = "com.google.accompanist", name = "accompanist-permissions", version.ref = "accompanist" }\nwork-runtime             = /' "$TOML"

  # Patch app/build.gradle.kts to add dependency
  sed -i 's/implementation(libs.work.runtime)/implementation(libs.work.runtime)\n    implementation(libs.accompanist.permissions)/' \
    "$ROOT/app/build.gradle.kts"

  log "Accompanist added"
}

# ─────────────────────────────────────────────────────────────
# UPDATED DI MODULE — wire WakeLockManager + ProcessGuard
# ─────────────────────────────────────────────────────────────
write_updated_di() {
  log "Writing updated AppModule..."
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
    fun db(@ApplicationContext c: Context): AppDatabase =
        Room.databaseBuilder(c, AppDatabase::class.java, "soren_db")
            .fallbackToDestructiveMigration().build()

    @Provides @Singleton fun configDao(db: AppDatabase):    ConfigDao        = db.configDao()
    @Provides @Singleton fun subDao(db: AppDatabase):       SubscriptionDao  = db.subDao()
    @Provides @Singleton fun statsDao(db: AppDatabase):     SessionStatsDao  = db.statsDao()

    @Provides @Singleton fun socketProtector():             SocketProtector      = SocketProtector()
    @Provides @Singleton fun connVerifier():                ConnectivityVerifier = ConnectivityVerifier()

    @Provides @Singleton
    fun healthChecker(p: SocketProtector): HealthChecker = HealthChecker(p)

    @Provides @Singleton
    fun wakeLockManager(@ApplicationContext c: Context): WakeLockManager = WakeLockManager(c)

    @Provides @Singleton
    fun processGuard(@ApplicationContext c: Context): ProcessGuard = ProcessGuard(c)

    @Provides @Singleton
    fun reconnectManager(): ReconnectManager = ReconnectManager()

    @Provides @Singleton
    fun watchdog(
        ps: com.soreng.tunnel.psiphon.PsiphonManager,
        xr: com.soreng.tunnel.xray.XrayManager,
        t2: com.soreng.tunnel.tunnel.Tun2SocksManager,
        hc: HealthChecker,
        pr: AppPreferences
    ): WatchdogSupervisor = WatchdogSupervisor(ps, xr, t2, hc, pr)
}
HEREDOC
  log "Updated DI done"
}

# ─────────────────────────────────────────────────────────────
# FINAL VPNSERVICE — integrates WakeLockManager, ProcessGuard,
# OEM keepalive scheduling, Android 13+ compat
# ─────────────────────────────────────────────────────────────
write_final_vpn_service() {
  log "Writing final SorenVpnService (with WakeLock, ProcessGuard, OEM keepalive)..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"

  cat > "$B/SorenVpnService.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.soreng.tunnel.notifications.VpnNotificationManager
import com.soreng.tunnel.psiphon.PsiphonManager
import com.soreng.tunnel.stats.StatsManager
import com.soreng.tunnel.storage.AppPreferences
import com.soreng.tunnel.storage.BinaryExtractor
import com.soreng.tunnel.storage.SplitTunnelCache
import com.soreng.tunnel.tunnel.Tun2SocksManager
import com.soreng.tunnel.utils.OemCompatHelper
import com.soreng.tunnel.utils.VpnKeepAliveWorker
import com.soreng.tunnel.xray.XrayManager
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
    @Inject lateinit var wakeLock:     WakeLockManager
    @Inject lateinit var procGuard:    ProcessGuard
    @Inject lateinit var oemHelper:    OemCompatHelper

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

        /** Single source of truth — UI only reads this. */
        val state = MutableStateFlow<VpnConnectionState>(VpnConnectionState.Disconnected)
    }

    override fun onCreate() {
        super.onCreate()
        // Register real protect() bridge BEFORE any sockets are created
        protector.register(this)
        jni.registerProtectCallback(protector)
        oemHelper.logRomInfo()
        Log.i(TAG, "onCreate: protect() bridge active [${jni.getVersion()}]")
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
                VpnKeepAliveWorker.cancel(this)
                svcScope.launch { doShutdown() }
                START_NOT_STICKY
            }
            null -> {
                // Android restarted sticky service after OEM kill
                if (currentCfgId >= 0 && !reconnMgr.isUserStop()) {
                    Log.i(TAG, "Sticky restart — reconnecting cfgId=$currentCfgId")
                    svcScope.launch { reconnMgr.reconnect { doStart(currentCfgId) } }
                }
                START_STICKY
            }
            else -> START_NOT_STICKY
        }
    }

    // ── STRICT 6-STEP STARTUP ────────────────────────────────
    private suspend fun doStart(cfgId: Long) {
        // Pre-flight cleanup
        procGuard.killZombies()
        binExtractor.extractAll()
        splitCache.load()
        currentCfgId = cfgId

        // Save for WorkManager keepalive
        getSharedPreferences("soren_keepalive_prefs", MODE_PRIVATE)
            .edit().putLong("last_cfg_id", cfgId).apply()

        try {
            state.value = VpnConnectionState.Connecting
            postNotif(notif.buildConnecting())

            // [1/6] Psiphon — MUST start first
            Log.i(TAG, "[1/6] Starting Psiphon...")
            psiphon.start()

            // [2/6] Verify Psiphon SOCKS5
            Log.i(TAG, "[2/6] Verifying Psiphon SOCKS5 :$PSIPHON_PORT")
            awaitSocks5(PSIPHON_PORT, 35_000, "Psiphon")

            // [3/6] Xray — all outbound forced via Psiphon SOCKS5
            Log.i(TAG, "[3/6] Starting Xray...")
            xray.start(cfgId, PSIPHON_PORT)

            // [4/6] Verify Xray SOCKS5
            Log.i(TAG, "[4/6] Verifying Xray SOCKS5 :$XRAY_SOCKS_PORT")
            awaitSocks5(XRAY_SOCKS_PORT, 20_000, "Xray")

            // [5/6] TUN + tun2socks
            Log.i(TAG, "[5/6] Building TUN + tun2socks...")
            val pfd = buildTun()
                ?: throw IllegalStateException("VPN establish() null — permission revoked or concurrent call?")
            tunPfd = pfd
            jni.setTunFd(pfd.fd)
            tun2socks.start(
                tunFd     = pfd.fd,
                socksPort = XRAY_SOCKS_PORT,
                mtu       = 1500,
                udp       = prefs.isUdpEnabled()
            )
            delay(600)
            if (!tun2socks.isRunning())
                throw IllegalStateException("tun2socks died immediately after start — check binary")

            // [6/6] End-to-end verification
            // ── UI MUST NOT show CONNECTED until this passes ──
            Log.i(TAG, "[6/6] End-to-end connectivity verification...")
            val probe = verifier.verify(XRAY_SOCKS_PORT, 15_000)
            if (!probe.success) throw IllegalStateException(
                "End-to-end probe FAILED: ${probe.errorMsg}. " +
                "Refusing Connected state — no real traffic confirmed.")

            // ── ALL STEPS PASSED ──────────────────────────────
            Log.i(TAG, "VPN established — latency=${probe.latencyMs}ms")
            state.value = VpnConnectionState.Connected(
                connectedAt    = System.currentTimeMillis(),
                probeLatencyMs = probe.latencyMs
            )
            wakeLock.acquire()
            postNotif(notif.buildConnected())
            stats.startSession()

            // Schedule WorkManager keepalive for OEM ROM survival
            VpnKeepAliveWorker.schedule(this)

            // Start watchdog
            watchdog.start(cfgId, svcScope) { id ->
                val ok = reconnMgr.reconnect { doCleanup(); doStart(id) }
                if (!ok) { doCleanup(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
            }

        } catch (e: CancellationException) {
            Log.i(TAG, "doStart cancelled")
            doCleanup()
        } catch (e: Exception) {
            Log.e(TAG, "VPN start FAILED: ${e.message}", e)
            state.value = VpnConnectionState.Error(e.message ?: "Unknown error")
            postNotif(notif.buildError(e.message ?: "Failed"))
            doCleanup()
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        }
    }

    private suspend fun buildTun(): ParcelFileDescriptor? {
        val ipv6 = prefs.isIPv6Enabled()
        val b = Builder()
            .setSession("SorenNG")
            .setMtu(1500)
            .setBlocking(false)
            .addAddress("10.89.0.1", 30)
            .addDnsServer("198.18.0.2")     // FakeDNS virtual address
            .addDnsServer("1.1.1.1")
            .addRoute("0.0.0.0", 0)          // All IPv4 through VPN
            .addDisallowedApplication(packageName) // Prevent self-routing loop

        if (ipv6) {
            b.addAddress("fd00:1:2:3::1", 128)
             .addRoute("::", 0)
             .addDnsServer("2606:4700:4700::1111")
        } else {
            // Route IPv6 into VPN to prevent leaks — Xray discards if not needed
            for ((addr, prefix) in listOf("2000::" to 3, "fc00::" to 7, "fe80::" to 10)) {
                try { b.addRoute(addr, prefix) } catch (_: Exception) {}
            }
        }

        for (pkg in splitCache.getBypassPackages()) {
            try { b.addDisallowedApplication(pkg) }
            catch (e: Exception) { Log.w(TAG, "bypass $pkg: ${e.message}") }
        }

        // Android 14+ requires explicit permission
        if (Build.VERSION.SDK_INT >= 34) {
            try { b.setMetered(false) } catch (_: Exception) {}
        }

        return b.establish()
    }

    private suspend fun doShutdown() {
        doCleanup()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private suspend fun doCleanup() = cleanupMutex.withLock {
        Log.i(TAG, "doCleanup: ordered shutdown")
        state.value = VpnConnectionState.Disconnecting
        watchdog.stop()
        wakeLock.release()
        stats.stopSession()
        safeStop("tun2socks")  { tun2socks.stop() }
        safeStop("xray")       { xray.stop() }
        safeStop("psiphon")    { psiphon.stop() }
        try {
            tunPfd?.close()
        } catch (e: Exception) { Log.w(TAG, "tunPfd close: ${e.message}") }
        finally { tunPfd = null }
        jni.cleanup()
        safeStop("zombies") { procGuard.killZombies() }
        state.value = VpnConnectionState.Disconnected
        Log.i(TAG, "doCleanup: done")
    }

    private suspend fun safeStop(n: String, b: suspend () -> Unit) =
        try { b() } catch (e: Exception) { Log.w(TAG, "safeStop[$n]: ${e.message}") }

    /**
     * Await SOCKS5 readiness.
     * ALWAYS protects the probe socket to prevent self-routing into TUN.
     */
    private suspend fun awaitSocks5(port: Int, timeoutMs: Long, label: String) =
        withContext(Dispatchers.IO) {
            val deadline = System.currentTimeMillis() + timeoutMs
            var attempts = 0; var lastErr = "timeout"
            while (System.currentTimeMillis() < deadline) {
                attempts++
                try {
                    Socket().use { s ->
                        protector.protect(s)     // CRITICAL — prevent self-routing
                        s.soTimeout   = 1_500
                        s.tcpNoDelay  = true
                        s.connect(InetSocketAddress("127.0.0.1", port), 1_500)
                    }
                    Log.i(TAG, "$label SOCKS5 ready ($attempts attempts)")
                    return@withContext
                } catch (e: Exception) { lastErr = e.message ?: "err"; delay(600) }
            }
            throw IllegalStateException(
                "$label :$port not ready after ${timeoutMs}ms ($attempts attempts). Last: $lastErr")
        }

    private fun postNotif(n: android.app.Notification) = try {
        getSystemService(android.app.NotificationManager::class.java).notify(NOTIF_ID, n)
    } catch (e: Exception) { Log.w(TAG, "postNotif: ${e.message}") }

    override fun onRevoke() {
        Log.w(TAG, "VPN revoked by system")
        reconnMgr.markUserStop()
        VpnKeepAliveWorker.cancel(this)
        svcScope.launch { doCleanup() }
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        reconnMgr.markUserStop()
        jni.unregisterProtectCallback()
        protector.unregister()
        runBlocking { withTimeoutOrNull(5_000) { doCleanup() } }
        svcScope.cancel()
        super.onDestroy()
    }
}
HEREDOC
  log "Final VPN service written"
}

# ─────────────────────────────────────────────────────────────
# UPDATED WATCHDOG — uses WakeLockManager, health checks,
# proper supervision with coroutine isActive
# ─────────────────────────────────────────────────────────────
write_final_watchdog() {
  log "Writing final WatchdogSupervisor..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/vpn"

  cat > "$B/WatchdogSupervisor.kt" << 'HEREDOC'
package com.soreng.tunnel.vpn

import android.util.Log
import kotlinx.coroutines.*
import com.soreng.tunnel.psiphon.PsiphonManager
import com.soreng.tunnel.tunnel.Tun2SocksManager
import com.soreng.tunnel.xray.XrayManager
import com.soreng.tunnel.storage.AppPreferences
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Monitors all tunnel daemons.
 *
 * Tick schedule:
 *   Every 10s: process.isAlive() check
 *   Every 30s: real SOCKS5+HTTP health check (HealthChecker)
 *   Every 60s: log status summary
 *
 * On failure: calls onFail(configId) → ReconnectManager.reconnect()
 * Uses isActive coroutine check — no infinite while(true) that leaks.
 */
@Singleton
class WatchdogSupervisor @Inject constructor(
    private val psiphon:   PsiphonManager,
    private val xray:      XrayManager,
    private val tun2socks: Tun2SocksManager,
    private val health:    HealthChecker,
    private val prefs:     AppPreferences
) {
    private val TAG = "WatchdogSupervisor"
    @Volatile private var job: Job? = null

    fun start(cfgId: Long, scope: CoroutineScope, onFail: suspend (Long) -> Unit) {
        stop()
        job = scope.launch {
            var tick = 0
            while (isActive) {
                delay(10_000)
                tick++
                if (!SorenVpnService.state.value.isActive) break

                // Process liveness check every 10s
                val alive = psiphon.isRunning() && xray.isRunning() && tun2socks.isRunning()
                if (!alive) {
                    Log.w(TAG, "Process down — p=${psiphon.isRunning()} x=${xray.isRunning()} t=${tun2socks.isRunning()}")
                    if (prefs.isAutoReconnectEnabled()) { onFail(cfgId); return@launch }
                    else {
                        SorenVpnService.state.value = VpnConnectionState.Error("Tunnel process died")
                        break
                    }
                }

                // Full health check every 30s
                if (tick % 3 == 0) {
                    val h = health.checkAll()
                    if (!h.allHealthy) {
                        Log.w(TAG, "Health check failed: $h")
                        if (prefs.isAutoReconnectEnabled()) { onFail(cfgId); return@launch }
                        else {
                            SorenVpnService.state.value = VpnConnectionState.Error("Health check failed")
                            break
                        }
                    }
                }

                // Status summary every 60s
                if (tick % 6 == 0) {
                    Log.d(TAG, "Status OK: tick=$tick p=${psiphon.isRunning()} x=${xray.isRunning()} t=${tun2socks.isRunning()}")
                }
            }
        }
        Log.i(TAG, "Watchdog started for cfgId=$cfgId")
    }

    fun stop() {
        job?.cancel(); job = null
        Log.d(TAG, "Watchdog stopped")
    }
}
HEREDOC
  log "Final watchdog done"
}

# ─────────────────────────────────────────────────────────────
# UPDATED SOREN APP — schedules keepalive + OEM detection
# ─────────────────────────────────────────────────────────────
write_final_app() {
  log "Writing final SorenApp..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"

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
import com.soreng.tunnel.utils.BatteryHelper
import com.soreng.tunnel.utils.OemCompatHelper
import javax.inject.Inject

@HiltAndroidApp
class SorenApp : Application() {
    @Inject lateinit var binExtractor: BinaryExtractor
    @Inject lateinit var security:     SecurityManager
    @Inject lateinit var oemHelper:    OemCompatHelper
    @Inject lateinit var battery:      BatteryHelper

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        createChannels()
        scope.launch { binExtractor.extractAll() }
        scope.launch { security.initialize() }
        scope.launch {
            oemHelper.logRomInfo()
            battery.logState()
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_VPN) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_VPN,
                    getString(R.string.channel_vpn),
                    NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false); enableVibration(false)
                })
        }
        if (nm.getNotificationChannel(CHANNEL_ALERT) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ALERT,
                    getString(R.string.channel_alert),
                    NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    companion object {
        const val CHANNEL_VPN   = "soren_vpn"
        const val CHANNEL_ALERT = "soren_alert"
    }
}
HEREDOC
  log "Final SorenApp done"
}

# ─────────────────────────────────────────────────────────────
# ANDROID 13+ COMPAT — POST_NOTIFICATIONS runtime request
# ─────────────────────────────────────────────────────────────
write_android13_compat() {
  log "Writing Android 13+ notification permission helper..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/utils"

  cat > "$B/NotificationPermissionHelper.kt" << 'HEREDOC'
package com.soreng.tunnel.utils

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

/**
 * Android 13+ (API 33) requires POST_NOTIFICATIONS runtime permission.
 * Without it, the VPN foreground notification is silently suppressed,
 * which causes the service to be killed as a background service.
 *
 * Call from MainActivity.onCreate() before starting any VPN operation.
 */
object NotificationPermissionHelper {

    fun requestIfNeeded(activity: ComponentActivity, onResult: (Boolean) -> Unit = {}) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            onResult(true); return
        }
        if (ContextCompat.checkSelfPermission(
                activity, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED) {
            onResult(true); return
        }
        val launcher = activity.registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { granted -> onResult(granted) }
        launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    fun isGranted(activity: ComponentActivity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            activity, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }
}
HEREDOC
  log "Android 13+ compat done"
}

# ─────────────────────────────────────────────────────────────
# UPDATED MAIN ACTIVITY — notification permission + battery hint
# ─────────────────────────────────────────────────────────────
write_final_main_activity() {
  log "Writing final MainActivity..."
  local B="$ROOT/app/src/main/kotlin/$PKGP/ui"

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
import com.soreng.tunnel.utils.NotificationPermissionHelper
import com.soreng.tunnel.utils.BatteryHelper
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @Inject lateinit var security: SecurityManager
    @Inject lateinit var battery:  BatteryHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        security.applyWindowSecurity(this)

        // Android 13+: request notification permission (required for VPN foreground notification)
        NotificationPermissionHelper.requestIfNeeded(this) { granted ->
            if (!granted) {
                android.util.Log.w("MainActivity",
                    "POST_NOTIFICATIONS denied — VPN foreground service may not persist")
            }
        }

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
  log "Final MainActivity done"
}

# ─────────────────────────────────────────────────────────────
# VALIDATION — check all critical files exist and are non-empty
# ─────────────────────────────────────────────────────────────
validate_project() {
  log "Validating project structure..."
  local B="$ROOT/app/src/main/kotlin/$PKGP"
  local PASS=0; local FAIL=0

  check_file() {
    if [ -f "$1" ] && [ -s "$1" ]; then
      PASS=$((PASS+1))
    else
      warn "MISSING or EMPTY: $1"
      FAIL=$((FAIL+1))
    fi
  }

  # JNI
  check_file "$ROOT/app/src/main/jni/soren_jni.cpp"
  check_file "$ROOT/app/src/main/jni/tun_helper.c"
  check_file "$ROOT/app/src/main/jni/CMakeLists.txt"

  # Core Kotlin
  check_file "$B/SorenApp.kt"
  check_file "$B/vpn/SorenVpnService.kt"
  check_file "$B/vpn/SorenJniBridge.kt"
  check_file "$B/vpn/SocketProtector.kt"
  check_file "$B/vpn/VpnConnectionState.kt"
  check_file "$B/vpn/ConnectivityVerifier.kt"
  check_file "$B/vpn/HealthChecker.kt"
  check_file "$B/vpn/WatchdogSupervisor.kt"
  check_file "$B/vpn/ReconnectManager.kt"
  check_file "$B/vpn/WakeLockManager.kt"
  check_file "$B/vpn/ProcessGuard.kt"
  check_file "$B/vpn/BootReceiver.kt"
  check_file "$B/vpn/VpnControlReceiver.kt"

  # Psiphon
  check_file "$B/psiphon/PsiphonManager.kt"
  check_file "$B/psiphon/PsiphonLibBridge.kt"

  # Xray
  check_file "$B/xray/XrayManager.kt"

  # Tunnel
  check_file "$B/tunnel/Tun2SocksManager.kt"

  # Config
  check_file "$B/config/ConfigProfile.kt"
  check_file "$B/config/ConfigParser.kt"
  check_file "$B/config/RuntimeConfigBuilder.kt"

  # Storage
  check_file "$B/storage/AppDatabase.kt"
  check_file "$B/storage/ConfigDao.kt"
  check_file "$B/storage/ConfigRepository.kt"
  check_file "$B/storage/AppPreferences.kt"
  check_file "$B/storage/BinaryExtractor.kt"
  check_file "$B/storage/SplitTunnelCache.kt"
  check_file "$B/storage/SecureConfigStore.kt"

  # Stats
  check_file "$B/stats/StatsManager.kt"

  # UI
  check_file "$B/ui/MainActivity.kt"
  check_file "$B/ui/SorenNavHost.kt"
  check_file "$B/ui/screen/HomeScreen.kt"
  check_file "$B/ui/screen/ConfigsScreen.kt"
  check_file "$B/ui/screen/StatsScreen.kt"
  check_file "$B/ui/screen/SettingsScreen.kt"
  check_file "$B/ui/screen/AddConfigScreen.kt"
  check_file "$B/ui/screen/QrScanScreen.kt"
  check_file "$B/ui/screen/LogsScreen.kt"
  check_file "$B/ui/viewmodel/HomeViewModel.kt"
  check_file "$B/ui/viewmodel/ConfigsViewModel.kt"
  check_file "$B/ui/viewmodel/StatsViewModel.kt"
  check_file "$B/ui/viewmodel/SettingsViewModel.kt"
  check_file "$B/ui/theme/Color.kt"
  check_file "$B/ui/theme/Theme.kt"

  # DI
  check_file "$B/di/AppModule.kt"

  # Notifications
  check_file "$B/notifications/VpnNotificationManager.kt"

  # Security + Utils
  check_file "$B/security/SecurityManager.kt"
  check_file "$B/utils/BatteryHelper.kt"
  check_file "$B/utils/OemCompatHelper.kt"
  check_file "$B/utils/VpnKeepAliveWorker.kt"
  check_file "$B/utils/NotificationPermissionHelper.kt"

  # Gradle
  check_file "$ROOT/settings.gradle.kts"
  check_file "$ROOT/app/build.gradle.kts"
  check_file "$ROOT/gradle/libs.versions.toml"
  check_file "$ROOT/gradle.properties"

  # Manifest
  check_file "$ROOT/app/src/main/AndroidManifest.xml"

  log "Validation: $PASS files OK, $FAIL files missing"
  if [ "$FAIL" -gt 0 ]; then
    warn "Some files are missing — check that all 3 parts ran successfully"
  else
    log "All required files present"
  fi
}

# ─────────────────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  SOREN NG TUNNEL — Generation Complete"
  echo "════════════════════════════════════════════════════════"
  echo ""
  log "Project directory: $ROOT"
  echo ""
  echo "  TRAFFIC FLOW:"
  echo "  User Config → Xray → Psiphon SOCKS5 :1080 → Internet"
  echo ""
  echo "  NEXT STEPS:"
  echo ""
  echo "  1. BUILD NATIVE BINARIES (required — no stubs):"
  echo "     See: $ROOT/README_BINARIES.txt"
  echo ""
  echo "  2. SET ANDROID SDK:"
  echo "     export ANDROID_HOME=\$HOME/Android/Sdk"
  echo ""
  echo "  3. BUILD APK:"
  echo "     cd $ROOT"
  echo "     ./gradlew assembleDebug"
  echo ""
  echo "  4. INSTALL:"
  echo "     ./gradlew installDebug"
  echo ""
  echo "  OEM HARDENING:"
  echo "  - MIUI/HyperOS: Settings → Apps → Soren NG → Battery → No restrictions"
  echo "  - EMUI:         Settings → Apps → Soren NG → Battery → Allow background"
  echo "  - ColorOS:      Settings → Battery → App energy → Soren NG → No restriction"
  echo ""
  echo "  BINARY SOURCES:"
  echo "  xray:      https://github.com/XTLS/Xray-core"
  echo "  tun2socks: https://github.com/xjasonlyu/tun2socks"
  echo "  psiphon:   https://github.com/Psiphon-Inc/psiphon-android"
  echo "             https://github.com/Psiphon-Labs/psiphon-tunnel-core"
  echo ""
  echo "════════════════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────
# PART 3 MAIN
# ─────────────────────────────────────────────────────────────
main_part3() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  SOREN NG TUNNEL — Project Generator  PART 3/3"
  echo "══════════════════════════════════════════════════"
  [ -d "$ROOT" ] || die "SorenNGTunnel not found — run parts 1 and 2 first"

  write_wakelock
  write_process_guard
  write_oem_keepalive
  write_accompanist_dep
  write_updated_di
  write_final_vpn_service
  write_final_watchdog
  write_final_app
  write_android13_compat
  write_final_main_activity
  validate_project
  print_summary
}

main_part3 "$@"
