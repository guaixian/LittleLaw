package dev.littlelaw.littlelaw

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // 部分 Android 设备/ROM 默认过滤组播报文,必须持有 MulticastLock
    // 才能收到局域网组播发现包。锁在进程生命周期内持有。
    private var multicastLock: WifiManager.MulticastLock? = null

    // ---- 热点直传 ----
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    companion object {
        const val HOTSPOT_CHANNEL = "dev.littlelaw/hotspot"
        const val SHARE_CHANNEL = "dev.littlelaw/share"

        /// NFC HCE 当前广播的 NDEF 文本载荷(由 Dart 侧设置,2 分钟配对窗口)。
        @Volatile
        var nfcPayloadText: String = ""

        /// 冷启动收到的分享内容(Dart 侧取走后清空)。
        @Volatile
        var initialShare: Map<String, Any?>? = null

        /// 分享事件转发(Dart 侧 MethodChannel 监听 onShare)。
        var shareChannel: MethodChannel? = null
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
        // 分享面板通道:Dart 取冷启动分享 + 监听热启动分享。
        val sc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel = sc
        sc.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(initialShare)
                    initialShare = null
                }
                // ---- 对外分享:拉起系统分享面板(微信/QQ/飞书等) ----
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (text.isEmpty()) {
                        result.error("ARG", "text required", null)
                    } else {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(send, "分享到"))
                        result.success(true)
                    }
                }
                "shareFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file)
                        val ext = file.extension.lowercase()
                        val mime =
                            MimeTypeMap.getSingleton()
                                .getMimeTypeFromExtension(ext) ?: "*/*"
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = mime
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(
                            Intent.createChooser(send, "分享到"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE", e.message, null)
                    }
                }
                // ---- 用其他应用打开(系统"打开方式"选择器) ----
                // 注意:此方法必须在 share 通道(Dart 侧 ShareOut 走
                // dev.littlelaw/share);旧版误挂在 hotspot 通道上,
                // Dart 调用落到 notImplemented,选择器永远不弹。
                "openFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file)
                        val ext = file.extension.lowercase()
                        val mime =
                            MimeTypeMap.getSingleton()
                                .getMimeTypeFromExtension(ext) ?: "*/*"
                        val view = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(view, "打开方式"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN", e.message, null)
                    }
                }
                // ---- 打开数据目录(文件管理器定位) ----
                "openDirectory" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        openDirectory(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DIR", e.message, null)
                    }
                }
                // ---- 应用内更新:下载完成后拉起系统安装器 ----
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file)
                        val i = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    // ------------------------------------------------------------ 分享面板

    /// 打开数据目录:优先用系统文件应用定位(externalstorage documents);
    /// 应用私有内部目录(/data/user/0/…)文件管理器无法访问,直接报错,
    /// Dart 侧会回退为复制路径。
    private fun openDirectory(path: String) {
        val dir = File(path)
        if (!dir.isDirectory) throw IllegalArgumentException("not a directory: $path")
        // 外部可见目录(/storage/emulated/0/...)可经 documents UI 定位。
        if (dir.absolutePath.startsWith("/storage/") &&
            !dir.absolutePath.contains("/Android/data")
        ) {
            val rel = dir.absolutePath.removePrefix("/storage/emulated/0/")
                .removePrefix("/sdcard/")
            val docId = if (rel.isEmpty() || rel == ".") "primary:" else "primary:$rel"
            val uri = DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents", docId)
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "vnd.android.document/directory")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(view)
            return
        }
        throw IllegalArgumentException("应用私有目录无法被文件管理器访问")
    }

    private fun handleShareIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text/") == true) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (!text.isNullOrEmpty()) {
                        emitShare(mapOf("type" to "text", "text" to text))
                    }
                } else {
                    val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    val path = uri?.let { copyToCache(it) }
                    if (path != null) {
                        emitShare(mapOf("type" to "file", "path" to path))
                    }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                val paths = uris?.mapNotNull { copyToCache(it) } ?: emptyList()
                if (paths.isNotEmpty()) {
                    emitShare(mapOf("type" to "files", "paths" to paths))
                }
            }
        }
    }

    private fun emitShare(payload: Map<String, Any?>) {
        val sc = shareChannel
        if (sc != null) {
            sc.invokeMethod("onShare", payload)
        } else {
            initialShare = payload
        }
    }

    /// content:// → 复制到应用缓存,换成 file 路径交给引擎发送。
    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = queryDisplayName(uri) ?: "shared_${System.currentTimeMillis()}"
            val dir = File(cacheDir, "share_inbox")
            dir.mkdirs()
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (e: Exception) {
            null
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
        // 组播锁:进程生命周期内持续持有(发现层跨前后台保活;
        // 重复 onStart 只补拿,不重复创建)。
        if (multicastLock == null) {
            try {
                val wifi =
                    applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicastLock = wifi.createMulticastLock("littlelaw_discovery").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } catch (_: Exception) {
                // 拿不到锁不致命:发现层还有广播 + 子网扫描兜底。
            }
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
