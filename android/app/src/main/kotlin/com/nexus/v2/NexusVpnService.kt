package com.nexus.v2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.*
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

class NexusVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private val workerPool = Executors.newCachedThreadPool()

    // MTProto proxy
    private var mtproxyRunning = AtomicBoolean(false)
    private var mtproxyThread: Thread? = null
    private var mtproxyServer: ServerSocket? = null
    private var mtproxyPort = 1443
    private val mtproxyClients = ConcurrentHashMap<String, Socket>()

    companion object {
        private const val TAG = "NexusVpnService"
        private const val CHANNEL_ID = "nexus_vpn"
        private const val NOTIF_ID = 1001

        @Volatile
        var mtproxySecret: String = ""
            private set

        private val TELEGRAM_DC_IPS = listOf(
            "91.108.56.100", "91.108.56.110", "91.108.56.120",
            "149.154.167.50", "149.154.167.51", "149.154.167.91",
            "109.239.96.15", "109.239.96.16", "109.239.96.17",
            "91.108.4.100", "91.108.4.110", "91.108.4.120"
        )
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        if (mtproxySecret.isEmpty()) {
            val secretBytes = ByteArray(16)
            SecureRandom().nextBytes(secretBytes)
            // Add 0xdd prefix for fake TLS
            val fullSecret = ByteArray(17)
            fullSecret[0] = 0xdd.toByte()
            System.arraycopy(secretBytes, 0, fullSecret, 1, 16)
            mtproxySecret = bytesToHex(fullSecret)
            Log.i(TAG, "Generated MTProto secret: ${mtproxySecret.substring(0, 10)}...")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP" -> { stopVpn(); return START_NOT_STICKY }
            "MT_START" -> {
                mtproxyPort = intent.getIntExtra("port", 1443)
                startMtproxy()
                return START_STICKY
            }
            "MT_STOP" -> {
                stopMtproxy()
                return START_STICKY
            }
        }
        startVpn()
        return START_STICKY
    }

    // ==================== VPN ====================

    private fun startVpn() {
        stopVpn()
        val builder = Builder()
        builder.setSession("NEXUS DPI Bypass")
        builder.setMtu(1500)
        builder.addAddress("10.0.0.1", 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")
        builder.setBlocking(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        try {
            vpnInterface = builder.establish()
            Log.i(TAG, "VPN established")
        } catch (e: Exception) {
            Log.e(TAG, "VPN establish failed: ${e.message}")
            return
        }

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("NEXUS VPN")
            .setContentText("DPI-обход активен • MTProto: 127.0.0.1:1443")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true).build()
        startForeground(NOTIF_ID, notification)

        running.set(true)
        thread = Thread { vpnLoop() }
        thread?.start()
    }

    private fun stopVpn() {
        running.set(false)
        thread?.join(2000)
        try { vpnInterface?.close() } catch (_: Exception) {}
        vpnInterface = null
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
    }

    private fun vpnLoop() {
        val input = FileInputStream(vpnInterface?.fileDescriptor)
        val output = FileOutputStream(vpnInterface?.fileDescriptor)
        val buf = ByteArray(4096)

        // DPI bypass state
        val rng = SecureRandom()

        try {
            while (running.get()) {
                val len = input.read(buf)
                if (len <= 0) continue
                var pkt = buf.copyOf(len)

                // Apply DPI bypass strategies
                pkt = applyDpiBypass(pkt, rng)

                try { output.write(pkt); output.flush() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            if (running.get()) Log.e(TAG, "VPN loop: ${e.message}")
        }
    }

    /**
     * Apply DPI bypass strategies to a packet.
     * Strategies:
     * - Fake TLS fragmentation (fragment ClientHello)
     * - TLS record splitting
     * - SNI padding
     * - Multi-split for large packets
     * - Random padding injection
     */
    private fun applyDpiBypass(pkt: ByteArray, rng: SecureRandom): ByteArray {
        if (pkt.size < 20) return pkt

        // Check if it's a TLS ClientHello (starting with 0x16 0x03)
        val isTLS = pkt[0] == 0x16.toByte() && (pkt[1] == 0x01.toByte() || pkt[1] == 0x03.toByte())

        if (isTLS && pkt.size > 50) {
            return applyTlsBypass(pkt, rng)
        }

        // Check for HTTPS CONNECT / HTTP
        val isHTTP = pkt.size > 4 && (
            pkt[0] == 'G'.code.toByte() ||
            pkt[0] == 'P'.code.toByte() ||
            pkt[0] == 'H'.code.toByte() ||
            pkt[0] == 'D'.code.toByte() ||
            pkt[0] == 'C'.code.toByte()
        )

        if (isHTTP && pkt.size > 100) {
            return applyHttpBypass(pkt, rng)
        }

        // Random multi-split for any large TCP packet
        if (pkt.size > 500 && rng.nextInt(100) < 30) {
            return applyMultiSplit(pkt, rng)
        }

        return pkt
    }

    /**
     * TLS bypass: fragment ClientHello + add fake records + SNI padding
     */
    private fun applyTlsBypass(pkt: ByteArray, rng: SecureRandom): ByteArray {
        val strategy = rng.nextInt(5)
        return when (strategy) {
            0 -> {
                // Fake TLS record before ClientHello
                val fakeLen = 16 + rng.nextInt(32)
                val fake = ByteArray(fakeLen)
                fake[0] = 0x16; fake[1] = 0x03; fake[2] = 0x01
                val fakeRecLen = (rng.nextInt(64) + 1).toShort()
                fake[3] = (fakeRecLen.toInt() shr 8).toByte()
                fake[4] = (fakeRecLen.toInt() and 0xFF).toByte()
                val randBytes = ByteArray(fake.size - 5)
                rng.nextBytes(randBytes)
                System.arraycopy(randBytes, 0, fake, 5, randBytes.size)
                val out = ByteArray(pkt.size + fake.size)
                System.arraycopy(fake, 0, out, 0, fake.size)
                System.arraycopy(pkt, 0, out, fake.size, pkt.size)
                out
            }
            1 -> {
                // TLS record splitting: split ClientHello into 2 parts
                val splitPoint = 50 + rng.nextInt(Math.min(pkt.size - 50, 100))
                if (splitPoint >= pkt.size) return pkt
                // First fragment
                val frag1 = ByteArray(splitPoint)
                System.arraycopy(pkt, 0, frag1, 0, splitPoint)
                // Update length in TLS record header
                val tlsLen = splitPoint - 5
                frag1[3] = (tlsLen shr 8).toByte()
                frag1[4] = (tlsLen and 0xFF).toByte()
                // Second fragment
                val frag2 = pkt.copyOfRange(splitPoint, pkt.size)
                val out = ByteArray(frag1.size + 10 + frag2.size)
                System.arraycopy(frag1, 0, out, 0, frag1.size)
                // Insert fake TLS record between fragments
                val inter = ByteArray(10)
                inter[0] = 0x16; inter[1] = 0x03; inter[2] = 0x03
                val interLen = (frag2.size - 5).toShort()
                inter[3] = (interLen.toInt() shr 8).toByte()
                inter[4] = (interLen.toInt() and 0xFF).toByte()
                val interBytes = ByteArray(5)
                rng.nextBytes(interBytes)
                System.arraycopy(interBytes, 0, inter, 5, 5)
                System.arraycopy(inter, 0, out, frag1.size, inter.size)
                System.arraycopy(frag2, 0, out, frag1.size + inter.size, frag2.size)
                out
            }
            2 -> {
                // SNI padding — find and pad SNI extension
                applySniPadding(pkt, rng)
            }
            3 -> {
                // Minimal fragment: send ClientHello in very small pieces
                val pieces = 3 + rng.nextInt(3)
                val pieceSize = pkt.size / pieces
                val out = ByteArray(pkt.size + pieces * 8)
                var offset = 0
                for (i in 0 until pieces) {
                    val start = i * pieceSize
                    val end = if (i == pieces - 1) pkt.size else (i + 1) * pieceSize
                    // Add fake header between pieces
                    if (i > 0) {
                        out[offset++] = 0x16.toByte()
                        out[offset++] = 0x03.toByte()
                        out[offset++] = 0x01.toByte()
                        val flen = (end - start + 16).toShort()
                        out[offset++] = (flen.toInt() shr 8).toByte()
                        out[offset++] = (flen.toInt() and 0xFF).toByte()
                        // Padding
                        val pad = 11 + rng.nextInt(5)
                        for (j in 0 until pad) out[offset++] = (rng.nextInt(256) - 128).toByte()
                    }
                    System.arraycopy(pkt, start, out, offset, end - start)
                    offset += (end - start)
                }
                out.copyOf(offset)
            }
            else -> {
                // Zero-fragment: just add padding to the end
                val padLen = 16 + rng.nextInt(48)
                val out = ByteArray(pkt.size + padLen)
                System.arraycopy(pkt, 0, out, 0, pkt.size)
                out[pkt.size] = 0x17.toByte() // Application Data type
                out[pkt.size + 1] = 0x03.toByte()
                out[pkt.size + 2] = 0x03.toByte()
                val padSize = (padLen - 5).toShort()
                out[pkt.size + 3] = (padSize.toInt() shr 8).toByte()
                out[pkt.size + 4] = (padSize.toInt() and 0xFF).toByte()
                val outBytes = ByteArray(padLen - 5)
                rng.nextBytes(outBytes)
                System.arraycopy(outBytes, 0, out, pkt.size + 5, outBytes.size)
                out
            }
        }
    }

    /**
     * HTTP/HTTPS CONNECT bypass: fragment the request line
     */
    private fun applyHttpBypass(pkt: ByteArray, rng: SecureRandom): ByteArray {
        val strategy = rng.nextInt(3)
        when (strategy) {
            0 -> {
                // Split after HTTP method
                val splitAt = pkt.indexOf(' '.code.toByte())
                if (splitAt in 4 until pkt.size - 10) {
                    val out = ByteArray(pkt.size + 1)
                    System.arraycopy(pkt, 0, out, 0, splitAt + 1)
                    out[splitAt + 1] = 0x0a.toByte() // LF to confuse DPI
                    System.arraycopy(pkt, splitAt + 1, out, splitAt + 2, pkt.size - splitAt - 1)
                    return out
                }
            }
            1 -> {
                // Pad Host header with spaces
                val hostIdx = findHostHeader(pkt)
                if (hostIdx >= 0) {
                    val padLen = rng.nextInt(16) + 8
                    val out = ByteArray(pkt.size + padLen)
                    System.arraycopy(pkt, 0, out, 0, hostIdx + 6) // "Host: "
                    // Add padding spaces
                    for (i in 0 until padLen) out[hostIdx + 6 + i] = ' '.code.toByte()
                    System.arraycopy(pkt, hostIdx + 6, out, hostIdx + 6 + padLen, pkt.size - hostIdx - 6)
                    return out
                }
            }
            2 -> {
                // Change case of HTTP method
                if (pkt.size > 4) {
                    val out = pkt.copyOf()
                    if (out[0] >= 'a'.code.toByte() && out[0] <= 'z'.code.toByte()) {
                        out[0] = (out[0].toInt() - 32).toByte() // uppercase first
                    }
                    out[3] = '/'.code.toByte()
                    return out
                }
            }
        }
        return pkt
    }

    /**
     * Multi-split: break packet into random segments with delay markers
     */
    private fun applyMultiSplit(pkt: ByteArray, rng: SecureRandom): ByteArray {
        val pieces = 2 + rng.nextInt(3)
        val outSize = pkt.size + pieces * 4
        val out = ByteArray(outSize)
        var offset = 0
        var srcOffset = 0
        val basePiece = pkt.size / pieces

        for (i in 0 until pieces) {
            // Write split marker
            out[offset++] = 0x00.toByte()
            out[offset++] = 0x00.toByte()
            out[offset++] = (rng.nextInt(256) - 128).toByte()
            out[offset++] = (rng.nextInt(256) - 128).toByte()

            val thisPiece = if (i == pieces - 1) pkt.size - srcOffset else basePiece + (if (rng.nextBoolean()) 1 else -1) * rng.nextInt(10)
            val actualPiece = Math.min(thisPiece, pkt.size - srcOffset).coerceAtLeast(1)
            System.arraycopy(pkt, srcOffset, out, offset, actualPiece)
            offset += actualPiece
            srcOffset += actualPiece
        }

        return out.copyOf(offset)
    }

    private fun applySniPadding(pkt: ByteArray, rng: SecureRandom): ByteArray {
        // Find SNI extension (type 0x00 0x00) in TLS ClientHello
        var idx = 43 // SNI typically starts after fixed TLS headers
        while (idx < pkt.size - 4) {
            if (pkt[idx] == 0x00.toByte() && pkt[idx + 1] == 0x00.toByte() &&
                pkt[idx + 2] == 0x00.toByte() && pkt[idx + 3].toInt() and 0xFF == 0x00) {
                // Found SNI type
                if (idx + 8 < pkt.size) {
                    val extLen = ((pkt[idx + 2].toInt() and 0xFF) shl 8) or (pkt[idx + 3].toInt() and 0xFF)
                    val padLen = 16 + rng.nextInt(32)
                    val out = ByteArray(pkt.size + padLen + 4)
                    System.arraycopy(pkt, 0, out, 0, pkt.size)
                    // Add SNI padding extension
                    val extIdx = pkt.size
                    out[extIdx] = 0x00.toByte()
                    out[extIdx + 1] = 0x15.toByte() // padding extension type
                    out[extIdx + 2] = ((padLen + 2) shr 8).toByte()
                    out[extIdx + 3] = ((padLen + 2) and 0xFF).toByte()
                    out[extIdx + 4] = (padLen shr 8).toByte()
                    out[extIdx + 5] = (padLen and 0xFF).toByte()
                    val sniBytes = ByteArray(padLen)
                    rng.nextBytes(sniBytes)
                    System.arraycopy(sniBytes, 0, out, extIdx + 6, padLen)
                    return out
                }
            }
            idx++
        }
        return pkt
    }

    private fun findHostHeader(pkt: ByteArray): Int {
        val target = "Host:".toByteArray()
        for (i in 0..pkt.size - target.size) {
            var match = true
            for (j in target.indices) {
                if (pkt[i + j] != target[j]) { match = false; break }
            }
            if (match) return i
        }
        return -1
    }

    // ==================== MTProto Proxy ====================

    private fun startMtproxy() {
        if (mtproxyRunning.getAndSet(true)) return
        mtproxyThread = Thread { mtproxyLoop() }
        mtproxyThread?.start()
        Log.i(TAG, "MTProto started on $mtproxyPort, secret len=${mtproxySecret.length}")
    }

    private fun stopMtproxy() {
        mtproxyRunning.set(false)
        try { mtproxyServer?.close() } catch (_: Exception) {}
        for ((_, s) in mtproxyClients) { try { s.close() } catch (_: Exception) {} }
        mtproxyClients.clear()
        mtproxyThread?.join(1000)
        mtproxyServer = null
    }

    private fun mtproxyLoop() {
        try {
            mtproxyServer = ServerSocket(mtproxyPort, 50, InetAddress.getByName("127.0.0.1"))
            while (mtproxyRunning.get()) {
                try {
                    val client = mtproxyServer!!.accept()
                    client.soTimeout = 30000
                    client.tcpNoDelay = true
                    val key = "${client.inetAddress}:${client.port}"
                    mtproxyClients[key] = client
                    workerPool.execute { relayClient(client, key) }
                } catch (_: Exception) { break }
            }
        } catch (e: Exception) {
            if (mtproxyRunning.get()) Log.e(TAG, "MTProxy: ${e.message}")
        }
    }

    private fun relayClient(client: Socket, key: String) {
        var tg: Socket? = null
        try {
            val clientIn = client.getInputStream()
            val clientOut = client.getOutputStream()

            // Read first bytes to determine connection type
            val peek = ByteArray(4)
            var peeked = 0
            while (peeked < 4) {
                val n = clientIn.read(peek, peeked, 4 - peeked)
                if (n < 0) { client.close(); return }
                peeked += n
            }

            val isTLS = peek[0] == 0x16.toByte()
            val isHTTP = peek[0] == 'G'.code.toByte() || peek[0] == 'P'.code.toByte()

            // Connect to a Telegram DC
            val tgHost = TELEGRAM_DC_IPS.random()
            tg = Socket()
            tg.connect(InetSocketAddress(tgHost, 443), 8000)
            tg.soTimeout = 30000
            tg.tcpNoDelay = true

            Log.i(TAG, "MTProxy: relaying to $tgHost:443 (TLS=$isTLS HTTP=$isHTTP)")

            val tgOut = tg.getOutputStream()
            val tgIn = tg.getInputStream()

            // Send fake response first if not raw
            if (isHTTP) {
                clientOut.write("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\n\r\n".toByteArray())
                clientOut.flush()
            } else if (isTLS) {
                // Fake self-signed TLS alert to pass through
                clientOut.write(byteArrayOf(0x15, 0x03, 0x03, 0x00, 0x02, 0x02, 0x28))
                clientOut.flush()
            }

            // Forward peeked bytes to TG
            tgOut.write(peek)
            tgOut.flush()

            // Bidirectional relay
            val toTG = thread {
                val buf = ByteArray(65535)
                while (mtproxyRunning.get()) {
                    val n = clientIn.read(buf)
                    if (n < 0) break
                    tgOut.write(buf, 0, n)
                    tgOut.flush()
                }
            }
            val fromTG = thread {
                val buf = ByteArray(65535)
                while (mtproxyRunning.get()) {
                    val n = tgIn.read(buf)
                    if (n < 0) break
                    clientOut.write(buf, 0, n)
                    clientOut.flush()
                }
            }
            toTG.join(45000)
            fromTG.join(5000)
        } catch (e: Exception) {
            Log.w(TAG, "MTProxy relay end: ${e.message}")
        } finally {
            try { client.close() } catch (_: Exception) {}
            try { tg?.close() } catch (_: Exception) {}
            mtproxyClients.remove(key)
        }
    }

    private fun thread(block: () -> Unit): Thread {
        val t = Thread(block)
        t.start()
        return t
    }

    // ==================== Utils ====================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "NEXUS VPN", NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "VPN и MTProto статус"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }
}
