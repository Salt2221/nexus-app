// ═══════════════════════════════════════════════════════════════
// NEXUS DPI Native Bridge — JNI к C++ движкам
// ──────────────────────────────────────────────────────────────
// Связывает Kotlin/Flutter с C++ библиотеками:
//   - PacketFragmenter (dpi_engine)
//   - BridgeRotator (bridge_rotator)
//   - CamouflageTunnel (camouflage_tunnel)
// ═══════════════════════════════════════════════════════════════

package com.nexus.v2.dpi

import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

// ═══════════════════════════════════════════════════════════════
// Результаты
// ═══════════════════════════════════════════════════════════════

data class FragmentResult(
    val modifiedPacket: ByteArray,
    val fakePackets: List<ByteArray>,
    val wasModified: Boolean,
    val strategyUsed: String
)

data class BridgeEndpoint(
    val host: String,
    val port: Int,
    val protocol: String,
    val publicKey: String,
    val serverName: String,
    val fingerprint: String,
    val latencyMs: Int = 0,
    val blocked: Boolean = false
)

data class TunnelConfig(
    val frontDomain: String,
    val hiddenDomain: String,
    val port: Int = 443,
    val protocol: String = "websocket",
    val path: String = "/chat"
)

// ═══════════════════════════════════════════════════════════════
// DPI Native Bridge
// ═══════════════════════════════════════════════════════════════

class DpiNative {
    companion object {
        private const val TAG = "DpiNative"
        private var loaded = false

        // JNI — загрузка native библиотеки
        fun load() {
            if (!loaded) {
                try {
                    System.loadLibrary("nexus_dpi")
                    loaded = true
                    Log.i(TAG, "nexus_dpi loaded successfully")
                } catch (e: UnsatisfiedLinkError) {
                    Log.w(TAG, "nexus_dpi not available: ${e.message}")
                }
            }
        }
    }

    init { load() }

    private val executor = Executors.newCachedThreadPool()
    private val httpCache = ConcurrentHashMap<String, CacheEntry>()
    private val cacheTtl = 60000L // 1 min

    data class CacheEntry(val data: String, val time: Long)

    // ═══════════════════════════════════════════════════════════
    // 1. Packet Fragmenter
    // ═══════════════════════════════════════════════════════════

    external fun nativeFragmentPacket(
        data: ByteArray,
        sniEnabled: Boolean,
        httpMangleEnabled: Boolean,
        fakeTtlEnabled: Boolean,
        tlsSplitEnabled: Boolean
    ): FragmentResult

    fun fragmentPacket(data: ByteArray, config: Map<String, Boolean> = emptyMap()): FragmentResult {
        return nativeFragmentPacket(
            data,
            config["sni_fragment"] ?: true,
            config["http_mangle"] ?: true,
            config["fake_ttl"] ?: true,
            config["tls_split"] ?: true
        )
    }

    // ═══════════════════════════════════════════════════════════
    // 2. Bridge Rotator
    // ═══════════════════════════════════════════════════════════

    external fun nativeDiscoverBridges(configJson: String): Array<BridgeEndpoint>

    fun discoverBridges(githubToken: String = ""): List<BridgeEndpoint> {
        val config = buildString {
            append("""{"github_token":"$githubToken",""")
            append(""""sources":["github","stegano","dht"]}""")
        }
        return nativeDiscoverBridges(config).toList()
    }

    /**
     * HTTP fetch callback для C++ bridge rotator'а
     */
    fun httpFetch(url: String): String {
        // Проверяем кэш
        httpCache[url]?.let {
            if (System.currentTimeMillis() - it.time < cacheTtl) {
                return it.data
            }
        }

        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36")
            conn.setRequestProperty("Accept", "*/*")
            conn.connectTimeout = 10000
            conn.readTimeout = 10000

            val data = conn.inputStream.bufferedReader().use { it.readText() }

            httpCache[url] = CacheEntry(data, System.currentTimeMillis())
            data
        } catch (e: Exception) {
            Log.w(TAG, "HTTP fetch error: ${e.message}")
            ""
        }
    }

    /**
     * Стеганография: декодируем IP/key из изображения
     */
    fun decodeSteganoImage(imageUrl: String): BridgeEndpoint? {
        return try {
            val data = httpFetch(imageUrl)
            // Ищем BRIDGE:host:port:key в данных
            val pattern = Regex("BRIDGE:([^:]+):(\\d+):([A-Za-z0-9+/=]+)")
            val match = pattern.find(data)
            if (match != null) {
                BridgeEndpoint(
                    host = match.groupValues[1],
                    port = match.groupValues[2].toInt(),
                    protocol = "reality",
                    publicKey = match.groupValues[3],
                    serverName = "www.microsoft.com",
                    fingerprint = "chrome"
                )
            } else null
        } catch (e: Exception) {
            Log.w(TAG, "Stegano decode error: ${e.message}")
            null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 3. Camouflage Tunnel
    // ═══════════════════════════════════════════════════════════

    external fun nativeTunnelConnect(configJson: String): Boolean
    external fun nativeTunnelSend(data: ByteArray): Boolean
    external fun nativeTunnelDisconnect()
    external fun nativeTunnelSwitchDomain(domain: String)
    external fun nativeTunnelSwitchProtocol(protocol: String)

    // ═══════════════════════════════════════════════════════════
    // 4. TDLib — MTProto Native
    // ═══════════════════════════════════════════════════════════

    external fun nativeTdInit(
        apiId: Int,
        apiHash: String,
        proxyHost: String,
        proxyPort: Int
    ): Boolean

    external fun nativeTdSendPhone(phone: String)
    external fun nativeTdSendCode(code: String)
    external fun nativeTdSendMessage(chatId: Long, text: String)
    external fun nativeTdDestroy()

    private var _tdInit = false

    fun tdInit(proxyHost: String = "127.0.0.1", proxyPort: Int = 1443): Boolean {
        if (!_tdInit) {
            val ok = nativeTdInit(2040, "b18441a1ff607e10a989891a5462e627", proxyHost, proxyPort)
            _tdInit = ok
            Log.i(TAG, "TDLib init: $ok (proxy: ${proxyHost}:${proxyPort})")
        }
        return _tdInit
    }

    // ═══════════════════════════════════════════════════════════

    fun tunnelConnect(config: TunnelConfig): Boolean {
        val json = buildString {
            append("""{"front_domain":"${config.frontDomain}",""")
            append(""""hidden_domain":"${config.hiddenDomain}",""")
            append(""""port":${config.port},""")
            append(""""protocol":"${config.protocol}",""")
            append(""""path":"${config.path}"}""")
        }
        return nativeTunnelConnect(json)
    }

    fun tunnelSend(data: ByteArray): Boolean {
        return nativeTunnelSend(data)
    }

    fun tunnelDisconnect() {
        nativeTunnelDisconnect()
    }

    fun tunnelSwitchDomain(domain: String) {
        nativeTunnelSwitchDomain(domain)
    }

    fun tunnelSwitchProtocol(protocol: String) {
        nativeTunnelSwitchProtocol(protocol)
    }

    // ═══════════════════════════════════════════════════════════
    // Здоровье
    // ═══════════════════════════════════════════════════════════

    fun cleanup() {
        httpCache.clear()
    }
}
