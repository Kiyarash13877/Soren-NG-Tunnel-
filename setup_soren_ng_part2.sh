#!/usr/bin/env bash
# =============================================================
# setup_soren_ng_part2.sh — Soren NG Tunnel
# UI Screens, ViewModels, QR Scanner
# Run AFTER part 1: bash setup_soren_ng_part2.sh
# PART 2 of 3
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

[ -d "$ROOT" ] || die "SorenNGTunnel not found — run part 1 first"

# ─────────────────────────────────────────────────────────────
# HOME SCREEN + VIEWMODEL
# ─────────────────────────────────────────────────────────────
write_home() {
  log "Writing HomeScreen..."
  local BS="$ROOT/app/src/main/kotlin/$PKGP/ui/screen"
  local BV="$ROOT/app/src/main/kotlin/$PKGP/ui/viewmodel"
  mkdir -p "$BS" "$BV"

  cat > "$BV/HomeViewModel.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.viewmodel

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.soreng.tunnel.config.ConfigProfile
import com.soreng.tunnel.stats.StatsManager
import com.soreng.tunnel.storage.AppPreferences
import com.soreng.tunnel.storage.ConfigRepository
import com.soreng.tunnel.vpn.SorenVpnService
import com.soreng.tunnel.vpn.VpnConnectionState
import javax.inject.Inject

@HiltViewModel
class HomeViewModel @Inject constructor(
    app: Application,
    private val stats: StatsManager,
    private val prefs: AppPreferences,
    private val repo:  ConfigRepository
) : AndroidViewModel(app) {

    val state:         StateFlow<VpnConnectionState> = SorenVpnService.state
    val uploadSpeed    = stats.uploadSpeed
    val downloadSpeed  = stats.downloadSpeed
    val ping           = stats.ping
    val uploadTotal    = stats.uploadTotal
    val downloadTotal  = stats.downloadTotal

    private val _selected = MutableStateFlow<ConfigProfile?>(null)
    val selected: StateFlow<ConfigProfile?> = _selected.asStateFlow()

    private val _history = MutableStateFlow<List<Pair<Long,Long>>>(emptyList())
    val history: StateFlow<List<Pair<Long,Long>>> = _history.asStateFlow()

    @Volatile private var connectPending = false

    init {
        loadLastConfig()
        collectHistory()
        observeState()
    }

    private fun loadLastConfig() = viewModelScope.launch {
        val id = prefs.getLastConfigId()
        _selected.value = if (id >= 0) repo.getById(id)
                          else repo.getAll().first().firstOrNull()
    }

    private fun collectHistory() = viewModelScope.launch {
        state.flatMapLatest { s ->
            if (s is VpnConnectionState.Connected)
                combine(uploadSpeed, downloadSpeed) { u, d -> u to d }
            else flowOf(0L to 0L).also { _history.value = emptyList() }
        }.collect { pair ->
            if (pair.first > 0 || pair.second > 0)
                _history.update { (it + pair).takeLast(60) }
        }
    }

    private fun observeState() = viewModelScope.launch {
        state.collect { s ->
            if (s is VpnConnectionState.Disconnected || s is VpnConnectionState.Error)
                connectPending = false
        }
    }

    fun connect(cfgId: Long) {
        if (connectPending || state.value.isActive) return
        connectPending = true
        viewModelScope.launch {
            prefs.setLastConfigId(cfgId)
            val ctx = getApplication<Application>()
            ctx.startForegroundService(
                Intent(ctx, SorenVpnService::class.java).apply {
                    action = SorenVpnService.ACTION_START
                    putExtra(SorenVpnService.EXTRA_CONFIG_ID, cfgId)
                })
        }
    }

    fun disconnect() {
        connectPending = false
        val ctx = getApplication<Application>()
        ctx.startService(Intent(ctx, SorenVpnService::class.java).apply {
            action = SorenVpnService.ACTION_STOP })
    }

    fun selectConfig(p: ConfigProfile) {
        _selected.value = p
        viewModelScope.launch { prefs.setLastConfigId(p.id) }
    }

    fun fmt(bps: Long)  = stats.fmtSpeed(bps)
    fun fmtB(b: Long)   = stats.fmtBytes(b)
}
HEREDOC

  cat > "$BS/HomeScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.soreng.tunnel.ui.viewmodel.HomeViewModel
import com.soreng.tunnel.vpn.VpnConnectionState
import com.soreng.tunnel.ui.theme.*

@Composable
fun HomeScreen(nav: NavController, vm: HomeViewModel = hiltViewModel()) {
    val state    by vm.state.collectAsState()
    val ulSpeed  by vm.uploadSpeed.collectAsState()
    val dlSpeed  by vm.downloadSpeed.collectAsState()
    val ping     by vm.ping.collectAsState()
    val ulTotal  by vm.uploadTotal.collectAsState()
    val dlTotal  by vm.downloadTotal.collectAsState()
    val selected by vm.selected.collectAsState()
    val history  by vm.history.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Black)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Header
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column {
                Text("SOREN NG", style = MaterialTheme.typography.headlineLarge, color = White,
                    fontWeight = FontWeight.Black)
                Text("TUNNEL v1.0", style = MaterialTheme.typography.labelSmall,
                    color = GrayMid, letterSpacing = 3.sp)
            }
            Box(Modifier.size(8.dp).background(
                if (state is VpnConnectionState.Connected) GreenOk else GrayDark,
                CircleShape))
        }
        Spacer(Modifier.height(12.dp))

        // Selected config chip
        Box(Modifier.fillMaxWidth()
            .border(1.dp, BlackBorder, RoundedCornerShape(8.dp))
            .background(BlackCard, RoundedCornerShape(8.dp))
            .clickable { nav.navigate("configs") }
            .padding(horizontal = 16.dp, vertical = 10.dp)
        ) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text(selected?.name?.ifBlank { selected?.address } ?: "— TAP TO SELECT CONFIG —",
                    style = MaterialTheme.typography.bodyMedium, color = GrayPale, maxLines = 1,
                    modifier = Modifier.weight(1f))
                if (selected != null)
                    Text(selected!!.protocol.name, style = MaterialTheme.typography.labelSmall,
                        color = GrayMid, modifier = Modifier
                            .border(1.dp, GrayDark, RoundedCornerShape(4.dp))
                            .padding(horizontal = 6.dp, vertical = 2.dp))
            }
        }
        Spacer(Modifier.height(24.dp))

        // Connect button
        ConnectButton(state) {
            if (state.isActive) vm.disconnect()
            else selected?.let { vm.connect(it.id) }
        }
        Spacer(Modifier.height(20.dp))

        // Status
        val statusColor = when (state) {
            is VpnConnectionState.Connected   -> GreenOk
            is VpnConnectionState.Connecting,
            is VpnConnectionState.Disconnecting-> YellowWarn
            is VpnConnectionState.Error        -> RedAlert
            else                               -> GrayMid
        }
        Text(state.label, style = MaterialTheme.typography.labelMedium,
            color = statusColor, letterSpacing = 2.sp, textAlign = TextAlign.Center)
        if (state is VpnConnectionState.Error)
            Text((state as VpnConnectionState.Error).message.take(80),
                style = MaterialTheme.typography.bodySmall, color = RedAlert.copy(alpha=0.8f),
                textAlign = TextAlign.Center, modifier = Modifier.padding(top=4.dp))
        Spacer(Modifier.height(24.dp))

        // Speed row
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceEvenly) {
            StatChip("▲ UP",   vm.fmt(ulSpeed))
            StatChip("▼ DOWN", vm.fmt(dlSpeed))
            StatChip("◈ PING", if (ping < 0) "—" else "${ping}ms")
        }
        Spacer(Modifier.height(16.dp))

        // Live graph
        if (history.isNotEmpty()) TrafficGraph(history)
        Spacer(Modifier.height(16.dp))

        // Totals
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceEvenly) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("TOTAL ▲", style = MaterialTheme.typography.labelSmall, color = GrayMid, letterSpacing = 1.sp)
                Text(vm.fmtB(ulTotal), style = MaterialTheme.typography.bodyMedium, color = GrayPale)
            }
            Box(Modifier.width(1.dp).height(36.dp).background(BlackBorder))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("TOTAL ▼", style = MaterialTheme.typography.labelSmall, color = GrayMid, letterSpacing = 1.sp)
                Text(vm.fmtB(dlTotal), style = MaterialTheme.typography.bodyMedium, color = GrayPale)
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}

@Composable
private fun ConnectButton(state: VpnConnectionState, onClick: () -> Unit) {
    val inf = rememberInfiniteTransition(label="ring")
    val rot by inf.animateFloat(0f, 360f,
        infiniteRepeatable(tween(3000, easing=LinearEasing)), label="rot")
    val pulse by inf.animateFloat(0.95f, 1.05f,
        infiniteRepeatable(tween(1200, easing=FastOutSlowInEasing), RepeatMode.Reverse), label="pulse")
    val glow by inf.animateFloat(0.3f, 0.9f,
        infiniteRepeatable(tween(1500, easing=FastOutSlowInEasing), RepeatMode.Reverse), label="glow")

    val ringColor = when (state) {
        is VpnConnectionState.Connected    -> GreenOk
        is VpnConnectionState.Connecting,
        is VpnConnectionState.Disconnecting-> YellowWarn
        is VpnConnectionState.Error        -> RedAlert
        else -> GrayDark
    }
    val isConnected   = state is VpnConnectionState.Connected
    val isTransitioning = state is VpnConnectionState.Connecting || state is VpnConnectionState.Disconnecting

    Box(Modifier.size(220.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(220.dp)) {
            val r = size.minDimension / 2f
            drawCircle(ringColor.copy(alpha = if (isConnected) glow*0.2f else 0.05f),
                radius = r, style = Stroke(width = 24.dp.toPx()))
            if (isTransitioning) {
                drawArc(ringColor, rotationAngle = rot, startAngle = rot,
                    sweepAngle = 120f, useCenter = false,
                    style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round))
            } else if (isConnected) {
                drawCircle(ringColor.copy(alpha = glow*0.5f),
                    radius = r - 12.dp.toPx(), style = Stroke(width = 2.dp.toPx()))
            }
        }
        Button(
            onClick = onClick,
            modifier = Modifier.size(160.dp).scale(if (isConnected) pulse else 1f),
            shape  = CircleShape,
            colors = ButtonDefaults.buttonColors(
                containerColor = when (state) {
                    is VpnConnectionState.Connected   -> Color(0xFF001A00)
                    is VpnConnectionState.Connecting  -> Color(0xFF1A1A00)
                    is VpnConnectionState.Error       -> Color(0xFF1A0000)
                    else -> BlackCard
                },
                contentColor = White
            ),
            border    = BorderStroke(if (isConnected) 2.dp else 1.dp,
                ringColor.copy(alpha = if (isConnected) glow else 0.5f)),
            elevation = ButtonDefaults.buttonElevation(0.dp)
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(when (state) {
                    is VpnConnectionState.Connected    -> "◉"
                    is VpnConnectionState.Connecting,
                    is VpnConnectionState.Disconnecting-> "◌"
                    is VpnConnectionState.Error        -> "✗"
                    else -> "◎"
                }, fontSize = 36.sp, color = ringColor)
                Spacer(Modifier.height(4.dp))
                Text(when (state) {
                    is VpnConnectionState.Connected    -> "DISCONNECT"
                    is VpnConnectionState.Connecting   -> "CANCEL"
                    is VpnConnectionState.Disconnecting-> "STOPPING"
                    is VpnConnectionState.Error        -> "RETRY"
                    else -> "CONNECT"
                }, style = MaterialTheme.typography.labelSmall, color = GrayPale, letterSpacing = 2.sp)
            }
        }
    }
}

@Composable
private fun StatChip(label: String, value: String) {
    Column(
        modifier = Modifier
            .border(1.dp, BlackBorder, RoundedCornerShape(8.dp))
            .background(BlackCard, RoundedCornerShape(8.dp))
            .padding(horizontal = 18.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = GrayMid, letterSpacing = 1.sp)
        Spacer(Modifier.height(4.dp))
        Text(value, style = MaterialTheme.typography.titleSmall, color = White, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun TrafficGraph(history: List<Pair<Long,Long>>) {
    val maxVal = history.maxOfOrNull { maxOf(it.first, it.second) }?.coerceAtLeast(1L) ?: 1L
    Box(Modifier.fillMaxWidth().height(90.dp)
        .border(1.dp, BlackBorder, RoundedCornerShape(8.dp))
        .background(BlackCard, RoundedCornerShape(8.dp))
        .padding(8.dp)
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width; val h = size.height; val n = history.size
            if (n < 2) return@Canvas
            for (i in 1..3) drawLine(GrayDark.copy(0.25f),
                Offset(0f, h*i/4f), Offset(w, h*i/4f), strokeWidth = 1f)
            val dlPath = Path()
            history.forEachIndexed { i, (_, dl) ->
                val x = i.toFloat()/(n-1)*w; val y = h-(dl.toFloat()/maxVal*h)
                if (i==0) dlPath.moveTo(x,y) else dlPath.lineTo(x,y)
            }
            drawPath(dlPath, White, style = Stroke(2f, cap = StrokeCap.Round))
            val ulPath = Path()
            history.forEachIndexed { i, (ul, _) ->
                val x = i.toFloat()/(n-1)*w; val y = h-(ul.toFloat()/maxVal*h)
                if (i==0) ulPath.moveTo(x,y) else ulPath.lineTo(x,y)
            }
            drawPath(ulPath, GrayMid, style = Stroke(1.5f, cap = StrokeCap.Round))
        }
    }
}
HEREDOC
  log "Home screen done"
}

# ─────────────────────────────────────────────────────────────
# CONFIGS SCREEN + VIEWMODEL
# ─────────────────────────────────────────────────────────────
write_configs() {
  log "Writing ConfigsScreen..."
  local BS="$ROOT/app/src/main/kotlin/$PKGP/ui/screen"
  local BV="$ROOT/app/src/main/kotlin/$PKGP/ui/viewmodel"

  cat > "$BV/ConfigsViewModel.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.viewmodel

import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.soreng.tunnel.config.ConfigParser
import com.soreng.tunnel.config.ConfigProfile
import com.soreng.tunnel.stats.StatsManager
import com.soreng.tunnel.storage.AppPreferences
import com.soreng.tunnel.storage.ConfigRepository
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject

@HiltViewModel
class ConfigsViewModel @Inject constructor(
    app: Application,
    private val repo:   ConfigRepository,
    private val parser: ConfigParser,
    private val prefs:  AppPreferences,
    private val stats:  StatsManager
) : AndroidViewModel(app) {

    private val _search = MutableStateFlow("")
    val search: StateFlow<String> = _search.asStateFlow()

    val configs: StateFlow<List<ConfigProfile>> = _search
        .debounce(300)
        .flatMapLatest { q -> if (q.isBlank()) repo.getAll() else repo.search(q) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _importFeedback = MutableStateFlow<String?>(null)
    val importFeedback: StateFlow<String?> = _importFeedback.asStateFlow()

    fun setSearch(q: String)          { _search.value = q }
    fun clearFeedback()               { _importFeedback.value = null }
    fun toggleFavorite(id: Long)      = viewModelScope.launch { repo.toggleFavorite(id) }
    fun delete(p: ConfigProfile)      = viewModelScope.launch { repo.delete(p) }
    fun selectConfig(p: ConfigProfile)= viewModelScope.launch { prefs.setLastConfigId(p.id) }

    fun importUris(text: String) = viewModelScope.launch {
        var count = 0
        text.lines().map { it.trim() }.filter { it.isNotBlank() }.forEach { line ->
            parser.parse(line)?.let { repo.insert(it); count++ }
        }
        _importFeedback.value = if (count > 0) "Imported $count config(s)" else "No valid configs found"
    }

    fun importFromClipboard() {
        val cm = getApplication<Application>()
            .getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = cm.primaryClip?.getItemAt(0)?.text?.toString() ?: run {
            _importFeedback.value = "Clipboard empty"; return
        }
        importUris(text)
    }

    fun testLatency(p: ConfigProfile) = viewModelScope.launch {
        val ms = stats.run {
            // Measure via protected socket to server address
            try {
                val s = java.net.Socket()
                val t = System.currentTimeMillis()
                s.soTimeout = 3000
                s.connect(java.net.InetSocketAddress(p.address, p.port), 3000)
                val rtt = System.currentTimeMillis() - t
                s.close(); rtt
            } catch (_: Exception) { -1L }
        }
        repo.updateLatency(p.id, ms)
    }

    fun importSubscription(url: String, name: String) = viewModelScope.launch {
        try {
            val client = OkHttpClient.Builder()
                .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS).build()
            val resp = client.newCall(Request.Builder().url(url).get().build()).execute()
            if (!resp.isSuccessful) { _importFeedback.value = "HTTP ${resp.code}"; return@launch }
            val body = resp.body?.string() ?: return@launch
            val decoded = try {
                String(android.util.Base64.decode(body.trim(), android.util.Base64.DEFAULT))
            } catch (_: Exception) { body }
            importUris(decoded)
        } catch (e: Exception) {
            Log.e("ConfigsVM", "Sub import: ${e.message}")
            _importFeedback.value = "Import failed: ${e.message?.take(60)}"
        }
    }
}
HEREDOC

  cat > "$BS/ConfigsScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.soreng.tunnel.config.ConfigProfile
import com.soreng.tunnel.config.Protocol
import com.soreng.tunnel.ui.viewmodel.ConfigsViewModel
import com.soreng.tunnel.ui.theme.*

@Composable
fun ConfigsScreen(nav: NavController, vm: ConfigsViewModel = hiltViewModel()) {
    val configs  by vm.configs.collectAsState()
    val search   by vm.search.collectAsState()
    val feedback by vm.importFeedback.collectAsState()
    var showAdd  by remember { mutableStateOf(false) }
    var showSub  by remember { mutableStateOf(false) }
    var subUrl   by remember { mutableStateOf("") }
    var subName  by remember { mutableStateOf("") }

    LaunchedEffect(feedback) {
        if (feedback != null) { kotlinx.coroutines.delay(3000); vm.clearFeedback() }
    }

    Column(Modifier.fillMaxSize().background(Black)) {
        Row(Modifier.fillMaxWidth().padding(20.dp, 16.dp),
            Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text("CONFIGS", style = MaterialTheme.typography.headlineMedium, color = White, letterSpacing = 3.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IconButton(onClick = { nav.navigate("qr_scan") }) {
                    Text("⊡", fontSize = 20.sp, color = GrayPale)
                }
                IconButton(onClick = { showAdd = !showAdd }) {
                    Text("+", fontSize = 24.sp, color = White, fontWeight = FontWeight.Bold)
                }
            }
        }

        OutlinedTextField(value = search, onValueChange = vm::setSearch,
            placeholder = { Text("search...", color = GrayMid, style = MaterialTheme.typography.bodySmall) },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor=GrayDark, unfocusedBorderColor=BlackBorder,
                cursorColor=White, focusedTextColor=White, unfocusedTextColor=GrayPale,
                focusedContainerColor=BlackCard, unfocusedContainerColor=BlackCard),
            shape = RoundedCornerShape(8.dp), singleLine = true,
            textStyle = MaterialTheme.typography.bodySmall)

        AnimatedVisibility(showAdd) {
            Row(Modifier.fillMaxWidth().padding(20.dp, 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ActionBtn("PASTE", "◫", Modifier.weight(1f)) { vm.importFromClipboard() }
                ActionBtn("MANUAL","✎", Modifier.weight(1f)) { nav.navigate("add_config") }
                ActionBtn("SUB",   "↓", Modifier.weight(1f)) { showSub = true }
            }
        }

        feedback?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = if (it.startsWith("Import")) GreenOk else RedAlert,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        }

        if (configs.isEmpty()) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("◎", fontSize = 48.sp, color = GrayDark)
                    Spacer(Modifier.height(12.dp))
                    Text("NO CONFIGS", style = MaterialTheme.typography.headlineSmall,
                        color = GrayDark, letterSpacing = 3.sp)
                    Text("add a config to begin", style = MaterialTheme.typography.bodySmall, color = GrayMid)
                }
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 80.dp, top = 8.dp)) {
                items(configs, key = { it.id }) { p ->
                    ConfigCard(p,
                        onSelect    = { vm.selectConfig(p) },
                        onDelete    = { vm.delete(p) },
                        onFavorite  = { vm.toggleFavorite(p.id) },
                        onPing      = { vm.testLatency(p) }
                    )
                }
            }
        }
    }

    if (showSub) AlertDialog(
        onDismissRequest = { showSub = false },
        containerColor   = BlackCard,
        title = { Text("Add Subscription", color = White, style = MaterialTheme.typography.titleMedium) },
        text  = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = subName, onValueChange = { subName = it },
                    label = { Text("Name", color = GrayMid) }, singleLine = true,
                    colors = outlinedColors(), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = subUrl, onValueChange = { subUrl = it },
                    label = { Text("URL", color = GrayMid) }, singleLine = true,
                    colors = outlinedColors(), modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton(onClick = {
            if (subUrl.isNotBlank()) { vm.importSubscription(subUrl, subName); showSub = false }
        }) { Text("IMPORT", color = White) } },
        dismissButton = { TextButton(onClick = { showSub = false }) { Text("CANCEL", color = GrayMid) } }
    )
}

@Composable
private fun ActionBtn(label: String, icon: String, mod: Modifier, onClick: () -> Unit) {
    OutlinedButton(onClick, modifier = mod.height(48.dp), shape = RoundedCornerShape(8.dp),
        border = BorderStroke(1.dp, GrayDark),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = GrayPale, containerColor = BlackCard)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(icon, fontSize = 14.sp); Text(label, style = MaterialTheme.typography.labelSmall, letterSpacing = 1.sp)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConfigCard(p: ConfigProfile, onSelect: ()->Unit, onDelete: ()->Unit, onFavorite: ()->Unit, onPing: ()->Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()
        .border(1.dp, if (p.isFavorite) GrayDark else BlackBorder, RoundedCornerShape(10.dp))
        .background(BlackCard, RoundedCornerShape(10.dp))
        .combinedClickable(onClick = onSelect, onLongClick = { expanded = !expanded })
        .padding(14.dp)
    ) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(p.name.ifBlank { p.address },
                    style = MaterialTheme.typography.titleSmall, color = White, maxLines = 1)
                Spacer(Modifier.height(3.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(p.protocol.name, style = MaterialTheme.typography.labelSmall, color = GrayMid,
                        modifier = Modifier.border(1.dp,GrayDark,RoundedCornerShape(4.dp))
                            .padding(horizontal=5.dp, vertical=1.dp))
                    Text("${p.address}:${p.port}",
                        style = MaterialTheme.typography.bodySmall, color = GrayMid, maxLines = 1)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                if (p.isFavorite) Text("★", color = White, fontSize = 12.sp)
                if (p.latencyMs > 0) Text("${p.latencyMs}ms",
                    style = MaterialTheme.typography.labelSmall,
                    color = when { p.latencyMs < 100 -> GreenOk; p.latencyMs < 300 -> YellowWarn; else -> RedAlert })
            }
        }
        AnimatedVisibility(expanded) {
            Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((lbl, action) in listOf("★ FAV" to onFavorite, "⏱ PING" to onPing, "✕ DEL" to onDelete)) {
                    TextButton(onClick = { action(); expanded = false },
                        modifier = Modifier.weight(1f).border(1.dp, GrayDark, RoundedCornerShape(4.dp)),
                        colors = ButtonDefaults.textButtonColors(contentColor = GrayPale)) {
                        Text(lbl, style = MaterialTheme.typography.labelSmall, letterSpacing = 1.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun outlinedColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor=GrayDark, unfocusedBorderColor=BlackBorder,
    cursorColor=White, focusedTextColor=White, unfocusedTextColor=GrayPale,
    focusedContainerColor=BlackCard, unfocusedContainerColor=BlackCard)
HEREDOC
  log "Configs screen done"
}

# ─────────────────────────────────────────────────────────────
# STATS SCREEN + VIEWMODEL
# ─────────────────────────────────────────────────────────────
write_stats_screen() {
  log "Writing StatsScreen..."
  local BS="$ROOT/app/src/main/kotlin/$PKGP/ui/screen"
  local BV="$ROOT/app/src/main/kotlin/$PKGP/ui/viewmodel"

  cat > "$BV/StatsViewModel.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import com.soreng.tunnel.stats.StatsManager
import com.soreng.tunnel.vpn.SorenVpnService
import com.soreng.tunnel.vpn.VpnConnectionState
import javax.inject.Inject

@HiltViewModel
class StatsViewModel @Inject constructor(private val stats: StatsManager) : ViewModel() {
    val uploadSpeed   = stats.uploadSpeed
    val downloadSpeed = stats.downloadSpeed
    val ping          = stats.ping
    val uploadTotal   = stats.uploadTotal
    val downloadTotal = stats.downloadTotal

    private val _history  = MutableStateFlow<List<Pair<Long,Long>>>(emptyList())
    private val _duration = MutableStateFlow("00:00:00")
    val history:  StateFlow<List<Pair<Long,Long>>> = _history.asStateFlow()
    val duration: StateFlow<String>                = _duration.asStateFlow()

    init {
        // History — only while connected
        viewModelScope.launch {
            SorenVpnService.state.flatMapLatest { s ->
                if (s is VpnConnectionState.Connected)
                    combine(uploadSpeed, downloadSpeed) { u, d -> u to d }
                else flowOf(0L to 0L).also { _history.value = emptyList() }
            }.collect { p -> if (p.first > 0 || p.second > 0) _history.update { (it + p).takeLast(60) } }
        }
        // Session timer — lifecycle-aware isActive loop
        viewModelScope.launch {
            while (isActive) {
                delay(1_000)
                val s = SorenVpnService.state.value
                _duration.value = if (s is VpnConnectionState.Connected) {
                    val e = (System.currentTimeMillis() - s.connectedAt) / 1_000L
                    "%02d:%02d:%02d".format(e/3600, (e%3600)/60, e%60)
                } else "00:00:00"
            }
        }
    }

    fun fmt(bps: Long)  = stats.fmtSpeed(bps)
    fun fmtB(b: Long)   = stats.fmtBytes(b)
}
HEREDOC

  cat > "$BS/StatsScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.hilt.navigation.compose.hiltViewModel
import com.soreng.tunnel.ui.viewmodel.StatsViewModel
import com.soreng.tunnel.ui.theme.*

@Composable
fun StatsScreen(vm: StatsViewModel = hiltViewModel()) {
    val ulSpeed  by vm.uploadSpeed.collectAsState()
    val dlSpeed  by vm.downloadSpeed.collectAsState()
    val ping     by vm.ping.collectAsState()
    val ulTotal  by vm.uploadTotal.collectAsState()
    val dlTotal  by vm.downloadTotal.collectAsState()
    val history  by vm.history.collectAsState()
    val duration by vm.duration.collectAsState()

    Column(Modifier.fillMaxSize().background(Black)
        .verticalScroll(rememberScrollState()).padding(20.dp)) {
        Text("STATISTICS", style = MaterialTheme.typography.headlineMedium,
            color = White, letterSpacing = 3.sp)
        Spacer(Modifier.height(20.dp))

        // Live graph
        Text("LIVE TRAFFIC", style = MaterialTheme.typography.labelSmall, color = GrayMid, letterSpacing = 2.sp)
        Spacer(Modifier.height(8.dp))
        LiveGraph(history, Modifier.fillMaxWidth().height(140.dp))
        Spacer(Modifier.height(20.dp))

        // Grid
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("UPLOAD",   vm.fmt(ulSpeed), "▲", Modifier.weight(1f))
            StatCard("DOWNLOAD", vm.fmt(dlSpeed), "▼", Modifier.weight(1f))
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("PING",    if (ping < 0) "—" else "${ping}ms", "◈", Modifier.weight(1f))
            StatCard("SESSION", duration,                            "⏱", Modifier.weight(1f))
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("TOTAL ▲", vm.fmtB(ulTotal), "∑", Modifier.weight(1f))
            StatCard("TOTAL ▼", vm.fmtB(dlTotal), "∑", Modifier.weight(1f))
        }
        Spacer(Modifier.height(80.dp))
    }
}

@Composable
private fun StatCard(label: String, value: String, icon: String, mod: Modifier) {
    Column(mod.border(1.dp, BlackBorder, RoundedCornerShape(10.dp))
        .background(BlackCard, RoundedCornerShape(10.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(icon, fontSize = 11.sp, color = GrayMid)
            Text(label, style = MaterialTheme.typography.labelSmall, color = GrayMid, letterSpacing = 1.sp)
        }
        Text(value, style = MaterialTheme.typography.titleMedium, color = White, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun LiveGraph(history: List<Pair<Long,Long>>, modifier: Modifier) {
    Box(modifier.border(1.dp, BlackBorder, RoundedCornerShape(10.dp))
        .background(BlackCard, RoundedCornerShape(10.dp)).padding(10.dp)) {
        if (history.size >= 2) {
            val maxVal = history.maxOfOrNull { maxOf(it.first,it.second) }?.coerceAtLeast(1L) ?: 1L
            Canvas(Modifier.fillMaxSize()) {
                val w=size.width; val h=size.height; val n=history.size
                for (i in 1..3) drawLine(GrayDark.copy(0.3f), Offset(0f,h*i/4f), Offset(w,h*i/4f), 1f)
                val dlFill=Path().also { path ->
                    path.moveTo(0f,h)
                    history.forEachIndexed { i, (_,dl) ->
                        val x=i.toFloat()/(n-1)*w; val y=h-dl.toFloat()/maxVal*h
                        path.lineTo(x,y)
                    }
                    path.lineTo(w,h); path.close()
                }
                drawPath(dlFill, Brush.verticalGradient(0f to White.copy(0.12f), 1f to Color.Transparent))
                val dl=Path()
                history.forEachIndexed{i,(_,d)->{val x=i.toFloat()/(n-1)*w;val y=h-d.toFloat()/maxVal*h;if(i==0)dl.moveTo(x,y)else dl.lineTo(x,y)}}
                drawPath(dl, White, style=Stroke(2f,cap=StrokeCap.Round))
                val ul=Path()
                history.forEachIndexed{i,(u,_)->{val x=i.toFloat()/(n-1)*w;val y=h-u.toFloat()/maxVal*h;if(i==0)ul.moveTo(x,y)else ul.lineTo(x,y)}}
                drawPath(ul, GrayMid, style=Stroke(1.5f,cap=StrokeCap.Round))
            }
        }
        Row(Modifier.align(Alignment.TopEnd).padding(2.dp), horizontalArrangement=Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)){
                Box(Modifier.size(8.dp,2.dp).background(White)); Text("▼",fontSize=9.sp,color=GrayPale)
            }
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)){
                Box(Modifier.size(8.dp,2.dp).background(GrayMid)); Text("▲",fontSize=9.sp,color=GrayMid)
            }
        }
    }
}
HEREDOC
  log "Stats screen done"
}

# ─────────────────────────────────────────────────────────────
# SETTINGS SCREEN + VIEWMODEL
# ─────────────────────────────────────────────────────────────
write_settings() {
  log "Writing SettingsScreen..."
  local BS="$ROOT/app/src/main/kotlin/$PKGP/ui/screen"
  local BV="$ROOT/app/src/main/kotlin/$PKGP/ui/viewmodel"

  cat > "$BV/SettingsViewModel.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.viewmodel

import android.app.Application
import android.content.pm.PackageManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.soreng.tunnel.storage.AppPreferences
import com.soreng.tunnel.storage.SplitTunnelCache
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    app: Application,
    private val prefs:      AppPreferences,
    private val splitCache: SplitTunnelCache
) : AndroidViewModel(app) {

    val autoStart    = prefs.autoStartFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)
    val autoReconnect= prefs.autoReconnectFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)
    val killSwitch   = prefs.killSwitchFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)
    val fakeDns      = prefs.fakeDnsFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)
    val udp          = prefs.udpFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)
    val ipv6         = prefs.ipv6Flow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)
    val dnsPrimary   = prefs.dnsPrimaryFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "1.1.1.1")
    val dnsSecondary = prefs.dnsSecondaryFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "8.8.8.8")
    val bypassApps   = prefs.bypassAppsFlow().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    fun setAutoStart(v: Boolean)    = viewModelScope.launch { prefs.setAutoStart(v) }
    fun setAutoReconnect(v: Boolean)= viewModelScope.launch { prefs.setAutoReconnect(v) }
    fun setKillSwitch(v: Boolean)   = viewModelScope.launch { prefs.setKillSwitch(v) }
    fun setFakeDns(v: Boolean)      = viewModelScope.launch { prefs.setFakeDns(v) }
    fun setUdp(v: Boolean)          = viewModelScope.launch { prefs.setUdp(v) }
    fun setIpv6(v: Boolean)         = viewModelScope.launch { prefs.setIPv6(v) }
    fun setDnsPrimary(v: String)    = viewModelScope.launch { prefs.setDnsPrimary(v) }
    fun setDnsSecondary(v: String)  = viewModelScope.launch { prefs.setDnsSecondary(v) }

    fun addBypassApp(pkg: String) = viewModelScope.launch {
        val cur = prefs.getBypassApps().toMutableSet()
        cur.add(pkg); prefs.setBypassApps(cur); splitCache.invalidate()
    }
    fun removeBypassApp(pkg: String) = viewModelScope.launch {
        val cur = prefs.getBypassApps().toMutableSet()
        cur.remove(pkg); prefs.setBypassApps(cur); splitCache.invalidate()
    }

    fun getInstalledApps(): List<Pair<String,String>> {
        val pm = getApplication<Application>().packageManager
        return pm.getInstalledApplications(PackageManager.GET_META_DATA)
            .filter { it.packageName != getApplication<Application>().packageName }
            .map { it.packageName to (pm.getApplicationLabel(it).toString()) }
            .sortedBy { it.second }
    }
}
HEREDOC

  cat > "$BS/SettingsScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.unit.*
import androidx.hilt.navigation.compose.hiltViewModel
import com.soreng.tunnel.ui.viewmodel.SettingsViewModel
import com.soreng.tunnel.ui.theme.*

@Composable
fun SettingsScreen(vm: SettingsViewModel = hiltViewModel()) {
    val autoStart    by vm.autoStart.collectAsState()
    val autoReconnect by vm.autoReconnect.collectAsState()
    val killSwitch   by vm.killSwitch.collectAsState()
    val fakeDns      by vm.fakeDns.collectAsState()
    val udp          by vm.udp.collectAsState()
    val ipv6         by vm.ipv6.collectAsState()
    val dnsPrimary   by vm.dnsPrimary.collectAsState()
    val dnsSecondary by vm.dnsSecondary.collectAsState()
    val bypassApps   by vm.bypassApps.collectAsState()
    var showSplit    by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().background(Black)
        .verticalScroll(rememberScrollState()).padding(20.dp)) {
        Text("SETTINGS", style = MaterialTheme.typography.headlineMedium,
            color = White, letterSpacing = 3.sp)
        Spacer(Modifier.height(20.dp))

        Section("CONNECTION") {
            Toggle("Auto Start on Boot",  autoStart,     vm::setAutoStart)
            Toggle("Auto Reconnect",       autoReconnect, vm::setAutoReconnect)
            Toggle("Kill Switch",          killSwitch,    vm::setKillSwitch)
        }
        Spacer(Modifier.height(14.dp))
        Section("TUNNEL") {
            Toggle("FakeDNS",     fakeDns, vm::setFakeDns)
            Toggle("UDP Forward", udp,     vm::setUdp)
            Toggle("IPv6",        ipv6,    vm::setIpv6)
        }
        Spacer(Modifier.height(14.dp))
        Section("DNS") {
            DnsInput("Primary DNS",   dnsPrimary,   vm::setDnsPrimary)
            DnsInput("Secondary DNS", dnsSecondary, vm::setDnsSecondary)
        }
        Spacer(Modifier.height(14.dp))
        Section("SPLIT TUNNEL") {
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp),
                Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Column {
                    Text("Bypass Apps", style = MaterialTheme.typography.bodyMedium, color = GrayPale)
                    Text("${bypassApps.size} app(s) excluded",
                        style = MaterialTheme.typography.bodySmall, color = GrayMid)
                }
                OutlinedButton(onClick = { showSplit = true },
                    border = BorderStroke(1.dp, GrayDark),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = GrayPale)) {
                    Text("MANAGE", style = MaterialTheme.typography.labelSmall, letterSpacing = 1.sp)
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        Section("ABOUT") {
            InfoRow("Version",  "1.0.0")
            InfoRow("Core",     "Xray-core + Psiphon")
            InfoRow("Protocol", "tun2socks + SOCKS5")
        }
        Spacer(Modifier.height(80.dp))
    }

    if (showSplit) SplitTunnelDialog(vm, bypassApps) { showSplit = false }
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()
        .border(1.dp, BlackBorder, RoundedCornerShape(10.dp))
        .background(BlackCard, RoundedCornerShape(10.dp))
        .padding(horizontal = 16.dp, vertical = 4.dp)) {
        Spacer(Modifier.height(10.dp))
        Text(title, style = MaterialTheme.typography.labelSmall, color = GrayMid, letterSpacing = 2.sp)
        Spacer(Modifier.height(6.dp))
        content()
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun Toggle(label: String, value: Boolean, onToggle: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp),
        Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = GrayPale)
        Switch(checked = value, onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(
                checkedThumbColor=White, checkedTrackColor=GrayDark,
                uncheckedThumbColor=GrayMid, uncheckedTrackColor=BlackMid,
                uncheckedBorderColor=GrayDark))
    }
}

@Composable
private fun DnsInput(label: String, value: String, onChange: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp),
        Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = GrayPale,
            modifier = Modifier.width(110.dp))
        OutlinedTextField(value = value, onValueChange = onChange,
            modifier = Modifier.weight(1f), singleLine = true,
            textStyle = MaterialTheme.typography.bodySmall,
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor=GrayDark, unfocusedBorderColor=BlackBorder,
                cursorColor=White, focusedTextColor=White, unfocusedTextColor=GrayPale,
                focusedContainerColor=BlackMid, unfocusedContainerColor=BlackMid),
            shape = RoundedCornerShape(6.dp))
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = GrayPale)
        Text(value,  style = MaterialTheme.typography.bodyMedium, color = GrayMid)
    }
}

@Composable
private fun SplitTunnelDialog(vm: SettingsViewModel, bypassed: Set<String>, onDismiss: () -> Unit) {
    val apps = remember { vm.getInstalledApps() }
    AlertDialog(onDismissRequest = onDismiss, containerColor = BlackCard,
        title = { Text("Bypass Apps", color = White, style = MaterialTheme.typography.titleMedium) },
        text = {
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 400.dp)) {
                items(apps) { (pkg, name) ->
                    Row(Modifier.fillMaxWidth().clickable {
                        if (pkg in bypassed) vm.removeBypassApp(pkg) else vm.addBypassApp(pkg)
                    }.padding(vertical = 6.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(name, style = MaterialTheme.typography.bodySmall, color = White, maxLines = 1)
                            Text(pkg, style = MaterialTheme.typography.labelSmall, color = GrayMid, maxLines = 1)
                        }
                        Checkbox(checked = pkg in bypassed, onCheckedChange = { checked ->
                            if (checked) vm.addBypassApp(pkg) else vm.removeBypassApp(pkg)
                        }, colors = CheckboxDefaults.colors(
                            checkedColor = White, uncheckedColor = GrayMid, checkmarkColor = Black))
                    }
                }
            }
        },
        confirmButton = { TextButton(onDismiss) { Text("DONE", color = White) } }
    )
}
HEREDOC
  log "Settings screen done"
}

# ─────────────────────────────────────────────────────────────
# ADD CONFIG + QR SCAN SCREENS
# ─────────────────────────────────────────────────────────────
write_add_qr_screens() {
  log "Writing AddConfig and QR screens..."
  local BS="$ROOT/app/src/main/kotlin/$PKGP/ui/screen"

  cat > "$BS/AddConfigScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.unit.*
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.soreng.tunnel.ui.viewmodel.ConfigsViewModel
import com.soreng.tunnel.ui.theme.*

@Composable
fun AddConfigScreen(nav: NavController, vm: ConfigsViewModel = hiltViewModel()) {
    var rawUri   by remember { mutableStateOf("") }
    val feedback by vm.importFeedback.collectAsState()

    LaunchedEffect(feedback) {
        if (feedback != null) {
            kotlinx.coroutines.delay(2000)
            vm.clearFeedback()
            if (feedback?.startsWith("Imported") == true) nav.popBackStack()
        }
    }

    Column(Modifier.fillMaxSize().background(Black).padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton({ nav.popBackStack() }) {
                Text("← BACK", style = MaterialTheme.typography.labelSmall,
                    color = GrayPale, letterSpacing = 2.sp)
            }
            Spacer(Modifier.weight(1f))
            Text("ADD CONFIG", style = MaterialTheme.typography.titleMedium,
                color = White, letterSpacing = 2.sp)
            Spacer(Modifier.weight(1f))
        }
        Spacer(Modifier.height(24.dp))

        Text("PASTE URI / JSON", style = MaterialTheme.typography.labelSmall,
            color = GrayMid, letterSpacing = 2.sp)
        Spacer(Modifier.height(8.dp))

        OutlinedTextField(value = rawUri, onValueChange = { rawUri = it },
            modifier = Modifier.fillMaxWidth().height(180.dp),
            placeholder = { Text("vmess://...\nvless://...\ntrojan://...\nss://...",
                color = GrayDark, style = MaterialTheme.typography.bodySmall) },
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor=GrayDark, unfocusedBorderColor=BlackBorder,
                cursorColor=White, focusedTextColor=White, unfocusedTextColor=GrayPale,
                focusedContainerColor=BlackCard, unfocusedContainerColor=BlackCard),
            shape = RoundedCornerShape(10.dp),
            textStyle = MaterialTheme.typography.bodySmall)

        Spacer(Modifier.height(16.dp))

        Button(onClick = { if (rawUri.isNotBlank()) vm.importUris(rawUri) },
            modifier = Modifier.fillMaxWidth().height(50.dp),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = GrayDark, contentColor = White)) {
            Text("IMPORT", style = MaterialTheme.typography.labelLarge, letterSpacing = 3.sp)
        }

        feedback?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = if (it.startsWith("Imported")) GreenOk else RedAlert)
        }

        Spacer(Modifier.height(24.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { nav.navigate("qr_scan") },
                modifier = Modifier.weight(1f).height(48.dp), shape = RoundedCornerShape(8.dp),
                border = BorderStroke(1.dp, GrayDark),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = GrayPale)) {
                Text("⊡ QR SCAN", style = MaterialTheme.typography.labelSmall, letterSpacing = 1.sp)
            }
            OutlinedButton(onClick = { vm.importFromClipboard() },
                modifier = Modifier.weight(1f).height(48.dp), shape = RoundedCornerShape(8.dp),
                border = BorderStroke(1.dp, GrayDark),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = GrayPale)) {
                Text("◫ PASTE", style = MaterialTheme.typography.labelSmall, letterSpacing = 1.sp)
            }
        }
    }
}
HEREDOC

  cat > "$BS/QrScanScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import android.Manifest
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.google.accompanist.permissions.*
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.soreng.tunnel.ui.viewmodel.ConfigsViewModel
import com.soreng.tunnel.ui.theme.*
import java.util.concurrent.Executors

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun QrScanScreen(nav: NavController, vm: ConfigsViewModel = hiltViewModel()) {
    val camPerm = rememberPermissionState(Manifest.permission.CAMERA)
    LaunchedEffect(Unit) { if (!camPerm.status.isGranted) camPerm.launchPermissionRequest() }

    Box(Modifier.fillMaxSize().background(Black)) {
        if (camPerm.status.isGranted) {
            QrCamera { raw -> vm.importUris(raw); nav.popBackStack() }
        } else {
            Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
                Text("CAMERA PERMISSION REQUIRED",
                    style = MaterialTheme.typography.titleMedium, color = White)
                Spacer(Modifier.height(16.dp))
                Button(onClick = { camPerm.launchPermissionRequest() },
                    colors = ButtonDefaults.buttonColors(containerColor = GrayDark)) {
                    Text("GRANT PERMISSION")
                }
            }
        }
        Box(Modifier.fillMaxWidth().align(Alignment.TopStart).padding(16.dp)) {
            TextButton({ nav.popBackStack() }) {
                Text("← BACK", style = MaterialTheme.typography.labelSmall, color = White, letterSpacing = 2.sp)
            }
        }
        // Scan frame
        Box(Modifier.align(Alignment.Center)) {
            Canvas(Modifier.size(240.dp)) {
                val w=size.width; val h=size.height; val len=40.dp.toPx(); val sw=3f
                listOf(0f to 0f, w to 0f, 0f to h, w to h).forEach { (cx,cy) ->
                    val dx=if(cx==0f)1f else -1f; val dy=if(cy==0f)1f else -1f
                    drawLine(Color.White,Offset(cx,cy),Offset(cx+dx*len,cy),sw)
                    drawLine(Color.White,Offset(cx,cy),Offset(cx,cy+dy*len),sw)
                }
            }
        }
        Text("ALIGN QR CODE IN FRAME",
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom=80.dp),
            style = MaterialTheme.typography.labelMedium, color = GrayPale, letterSpacing = 2.sp)
    }
}

@Composable
private fun QrCamera(onDetected: (String) -> Unit) {
    val ctx   = LocalContext.current
    val owner = LocalLifecycleOwner.current
    var done  by remember { mutableStateOf(false) }
    val exec  = remember { Executors.newSingleThreadExecutor() }

    AndroidView(Modifier.fillMaxSize(), factory = { c ->
        PreviewView(c).also { pv ->
            ProcessCameraProvider.getInstance(c).addListener({
                val cp  = ProcessCameraProvider.getInstance(c).get()
                val pre = Preview.Builder().build().also { it.setSurfaceProvider(pv.surfaceProvider) }
                val opt = BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
                val scn = BarcodeScanning.getClient(opt)
                val ana = ImageAnalysis.Builder()
                    .setTargetResolution(Size(1280,720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                ana.setAnalyzer(exec) { proxy ->
                    if (!done) {
                        @androidx.camera.core.ExperimentalGetImage
                        val img = proxy.image
                        if (img != null) {
                            scn.process(InputImage.fromMediaImage(img, proxy.imageInfo.rotationDegrees))
                                .addOnSuccessListener { codes ->
                                    codes.firstOrNull()?.rawValue?.let { v ->
                                        if (!done) { done=true; onDetected(v) }
                                    }
                                }.addOnCompleteListener { proxy.close() }
                        } else proxy.close()
                    } else proxy.close()
                }
                try {
                    cp.unbindAll()
                    cp.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, pre, ana)
                } catch (e: Exception) { e.printStackTrace() }
            }, ContextCompat.getMainExecutor(c))
        }
    })
}
HEREDOC
  log "Add/QR screens done"
}

# ─────────────────────────────────────────────────────────────
# LOGS SCREEN
# ─────────────────────────────────────────────────────────────
write_logs_screen() {
  log "Writing LogsScreen..."
  local BS="$ROOT/app/src/main/kotlin/$PKGP/ui/screen"

  cat > "$BS/LogsScreen.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.screen

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.unit.*
import androidx.hilt.navigation.compose.hiltViewModel
import com.soreng.tunnel.ui.viewmodel.LogsViewModel
import com.soreng.tunnel.ui.theme.*

@Composable
fun LogsScreen(vm: LogsViewModel = hiltViewModel()) {
    val logs by vm.logs.collectAsState()
    val lsState = rememberLazyListState()

    LaunchedEffect(logs.size) {
        if (logs.isNotEmpty()) lsState.animateScrollToItem(logs.size - 1)
    }

    Column(Modifier.fillMaxSize().background(Black).padding(horizontal=16.dp, vertical=12.dp)) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text("LOGS", style = MaterialTheme.typography.headlineMedium,
                color = White, letterSpacing = 3.sp)
            TextButton(onClick = vm::clearLogs) {
                Text("CLEAR", style = MaterialTheme.typography.labelSmall,
                    color = GrayMid, letterSpacing = 2.sp)
            }
        }
        Spacer(Modifier.height(8.dp))
        if (logs.isEmpty()) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                Text("No logs", style = MaterialTheme.typography.bodySmall, color = GrayMid)
            }
        } else {
            LazyColumn(state = lsState, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(logs) { entry ->
                    Text(entry, style = MaterialTheme.typography.labelSmall,
                        color = when {
                            entry.contains("ERROR",true) -> RedAlert
                            entry.contains("WARN", true) -> YellowWarn
                            entry.contains("OK",   true) -> GreenOk
                            else -> GrayPale
                        },
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                        fontSize = 10.sp, lineHeight = 14.sp)
                }
                item { Spacer(Modifier.height(80.dp)) }
            }
        }
    }
}
HEREDOC

  local BV="$ROOT/app/src/main/kotlin/$PKGP/ui/viewmodel"
  cat > "$BV/LogsViewModel.kt" << 'HEREDOC'
package com.soreng.tunnel.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.soreng.tunnel.vpn.SorenVpnService
import com.soreng.tunnel.vpn.VpnConnectionState
import java.io.BufferedReader
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class LogsViewModel @Inject constructor() : ViewModel() {

    private val _logs = MutableStateFlow<List<String>>(emptyList())
    val logs: StateFlow<List<String>> = _logs.asStateFlow()
    private val fmt = SimpleDateFormat("HH:mm:ss", Locale.US)

    init {
        viewModelScope.launch {
            SorenVpnService.state.collect { state ->
                when (state) {
                    is VpnConnectionState.Connecting ->
                        addLog("Connecting...")
                    is VpnConnectionState.Connected ->
                        addLog("Connected — probe latency=${state.probeLatencyMs}ms")
                    is VpnConnectionState.Disconnected ->
                        addLog("Disconnected")
                    is VpnConnectionState.Error ->
                        addLog("ERROR: ${state.message}")
                    else -> {}
                }
            }
        }
    }

    private fun addLog(msg: String) {
        val entry = "[${fmt.format(Date())}] $msg"
        _logs.update { (it + entry).takeLast(200) }
    }

    fun clearLogs() { _logs.value = emptyList() }
}
HEREDOC
  log "Logs screen done"
}

# ─────────────────────────────────────────────────────────────
# PART 2 MAIN
# ─────────────────────────────────────────────────────────────
main_part2() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  SOREN NG TUNNEL — Project Generator  PART 2/3"
  echo "══════════════════════════════════════════════════"
  [ -d "$ROOT" ] || die "SorenNGTunnel not found — run part 1 first"
  write_home
  write_configs
  write_stats_screen
  write_settings
  write_add_qr_screens
  write_logs_screen
  echo ""
  echo "══════════════════════════════════════════════════"
  log "PART 2 complete. Run part 3 next: bash setup_soren_ng_part3.sh"
  echo "══════════════════════════════════════════════════"
}

main_part2 "$@"
