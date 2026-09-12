package dev.littlelaw.littlelaw

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 部分 Android 设备/ROM 默认过滤组播报文,必须持有 MulticastLock
    // 才能收到局域网组播发现包。锁在进程生命周期内持有。
    private var multicastLock: WifiManager.MulticastLock? = null

    // ---- 热点直传 ----
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    companion object {
        const val HOTSPOT_CHANNEL = "dev.littlelaw/hotspot"

        /// NFC HCE 当前广播的 NDEF 文本载荷(由 Dart 侧设置,2 分钟配对窗口)。
        @Volatile
        var nfcPayloadText: String = ""
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOTSPOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startHotspot" -> startHotspot(result)
                    "stopHotspot" -> stopHotspot(result)
                    "joinHotspot" -> {
                        val ssid = call.argument<String>("ssid")
                        val password = call.argument<String>("password") ?: ""
                        if (ssid.isNullOrEmpty()) {
                            result.error("ARG", "ssid required", null)
                        } else {
                            joinHotspot(ssid, password, result)
                        }
                    }
                    "leaveHotspot" -> leaveHotspot(result)
                    "setNfcPayload" -> {
                        nfcPayloadText = call.argument<String>("payload") ?: ""
                        result.success(true)
                    }
                    "clearNfcPayload" -> {
                        nfcPayloadText = ""
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------ 热点

    private fun startHotspot(result: MethodChannel.Result) {
        val wifi =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspotReservation = reservation
                    val ssid: String?
                    val pass: String?
                    if (Build.VERSION.SDK_INT >= 30) {
                        val config = reservation.softApConfiguration
                        ssid = config?.ssid
                        pass = config?.passphrase
                    } else {
                        @Suppress("DEPRECATION")
                        val legacy = reservation.wifiConfiguration
                        ssid = legacy?.SSID
                        pass = legacy?.preSharedKey
                    }
                    result.success(mapOf("ssid" to ssid, "password" to pass))
                }

                override fun onStopped() {
                    hotspotReservation = null
                }

                override fun onFailed(reason: Int) {
                    result.error("HOTSPOT", "start failed: $reason", null)
                }
            }, null)
        } catch (e: Exception) {
            result.error("HOTSPOT", e.message, null)
        }
    }

    private fun stopHotspot(result: MethodChannel.Result) {
        try {
            hotspotReservation?.close()
        } catch (_: Exception) {
        }
        hotspotReservation = null
        result.success(true)
    }

    private fun joinHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) {
            result.error("UNSUPPORTED", "加入热点需要 Android 10+", null)
            return
        }
        try {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(password)
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            val cm = applicationContext
                .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            var reported = false
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // 关键:把引擎流量绑定到热点网络(该网络无互联网)。
                    cm.bindProcessToNetwork(network)
                    if (!reported) {
                        reported = true
                        result.success(true)
                    }
                }

                override fun onUnavailable() {
                    if (!reported) {
                        reported = true
                        result.error("JOIN", "network unavailable", null)
                    }
                }
            }
            joinCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
            joinCallback = callback
            cm.requestNetwork(request, callback)
        } catch (e: Exception) {
            result.error("JOIN", e.message, null)
        }
    }

    private fun leaveHotspot(result: MethodChannel.Result) {
        val cm = applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        joinCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        joinCallback = null
        cm.bindProcessToNetwork(null)
        result.success(true)
    }

    // ------------------------------------------------------------ 组播锁

    override fun onStart() {
        super.onStart()
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("littlelaw_discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            // 拿不到锁不致命:发现层还有广播 + 子网扫描兜底。
        }
    }

    override fun onStop() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        multicastLock = null
        super.onStop()
    }

    override fun onDestroy() {
        try {
            hotspotReservation?.close()
            joinCallback?.let {
                val cm = applicationContext
                    .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                runCatching { cm.unregisterNetworkCallback(it) }
            }
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
