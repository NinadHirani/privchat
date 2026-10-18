package app.privchat

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Wi-Fi Direct: two Android phones form their own Wi-Fi network (no router, no hotspot,
 * no internet). Once a group forms, both phones get IPs (group owner is 192.168.49.1) and
 * PrivChat's normal mDNS/UDP discovery + TCP + WebRTC work over it unchanged.
 */
@SuppressLint("MissingPermission")
class WifiDirectPlugin(private val ctx: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val method = MethodChannel(messenger, "privchat/wifidirect")
    private val events = EventChannel(messenger, "privchat/wifidirect/events")
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val manager: WifiP2pManager? =
        if (ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT))
            ctx.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager else null
    private val channel: WifiP2pManager.Channel? = manager?.initialize(ctx, Looper.getMainLooper(), null)
    private var peers: List<WifiP2pDevice> = emptyList()
    private var lastInfo: WifiP2pInfo? = null
    private var registered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> manager?.requestPeers(channel) { list ->
                    peers = list.deviceList.toList()
                    emit(mapOf("type" to "peers", "count" to peers.size))
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> manager?.requestConnectionInfo(channel) { info ->
                    lastInfo = info
                    if (info != null && info.groupFormed) {
                        emit(mapOf("type" to "connected", "isGroupOwner" to info.isGroupOwner,
                            "groupOwnerAddress" to info.groupOwnerAddress?.hostAddress))
                    } else {
                        emit(mapOf("type" to "disconnected"))
                    }
                }
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val enabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    emit(mapOf("type" to "state", "enabled" to enabled))
                }
            }
        }
    }

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(this)
        register()
    }

    private fun register() {
        if (manager == null || registered) return
        val f = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) ctx.registerReceiver(receiver, f, Context.RECEIVER_NOT_EXPORTED)
        else ctx.registerReceiver(receiver, f)
        registered = true
    }

    fun dispose() {
        if (registered) try { ctx.unregisterReceiver(receiver) } catch (_: Exception) {}
        registered = false
        method.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    private fun emit(m: Map<String, Any?>) = main.post { sink?.success(m) }

    private fun listener(result: MethodChannel.Result) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() = result.success(true)
        override fun onFailure(reason: Int) = result.error("P2P_$reason", reasonText(reason), null)
    }

    private fun reasonText(r: Int) = when (r) {
        WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct not supported"
        WifiP2pManager.BUSY -> "Wi-Fi Direct busy, try again"
        else -> "Wi-Fi Direct error (turn Wi-Fi and Location on)"
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val m = manager
        val ch = channel
        if (call.method == "isSupported") { result.success(m != null && ch != null); return }
        if (m == null || ch == null) { result.error("UNSUPPORTED", "Wi-Fi Direct unavailable", null); return }
        try {
            when (call.method) {
                "discover" -> m.discoverPeers(ch, listener(result))
                "stopDiscovery" -> m.stopPeerDiscovery(ch, listener(result))
                "peers" -> result.success(peers.map {
                    mapOf("name" to it.deviceName, "address" to it.deviceAddress, "status" to it.status)
                })
                "connect" -> {
                    val cfg = WifiP2pConfig().apply {
                        deviceAddress = call.argument<String>("address")
                        groupOwnerIntent = 7
                    }
                    m.connect(ch, cfg, listener(result))
                }
                "createGroup" -> m.createGroup(ch, listener(result))
                "disconnect" -> m.removeGroup(ch, listener(result))
                "connectionInfo" -> {
                    val i = lastInfo
                    if (i == null || !i.groupFormed) result.success(null)
                    else result.success(mapOf("isGroupOwner" to i.isGroupOwner, "groupOwnerAddress" to i.groupOwnerAddress?.hostAddress))
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Nearby devices / location permission required", null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
}
