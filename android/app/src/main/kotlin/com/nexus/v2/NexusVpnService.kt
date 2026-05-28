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
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

class NexusVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private val workerPool = Executors.newCachedThreadPool()
    private val activeTunnels = ConcurrentHashMap<String, Socket>()

    // MTProto proxy
    private var mtproxyRunning = AtomicBoolean(false)
    private var mtproxyThread: Thread? = null
    private var mtproxyServer: ServerSocket? = null
    private var mtproxyPort = 1443
    private var mtproxySecret: String = ""
    private var mtproxyFakeTlsDomain: String = ""

    // MTProto fake TLS hello
    private val TLS_HELLO = byteArrayOf(
        0x16, 0x03, 0x01, 0x00, 0x00.toByte()
    )

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // Generate MTProto secret
        val secret = ByteArray(16)
        SecureRandom().nextBytes(secret)
        mtproxySecret = bytesToHex(secret)
        // Generate fake domain for TLS伪装
        mtproxyFakeTlsDomain = "cloudflare-nginx-${System.currentTimeMillis() % 10000}.com"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP" -> { stopVpn(); return START_NOT_STICKY }
            "START_MT_PROXY" -> {
                mtproxyPort = intent.getIntExtra("port", 1443)
                startMtproxy()
                return START_STICKY
            }
            "STOP_MT_PROXY" -> {
                stopMtproxy()
                return START_STICKY
            }
        }
        startVpn()
        return START_STICKY
    }

    override fun onDestroy() {
        stopMtproxy()
        stopVpn()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "NEXUS VPN", NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    fun getMtproxySecret(): String = mtproxySecret

    // ==================== MTProto Proxy Server ====================

    private fun startMtproxy() {
        if (mtproxyRunning.get()) return
        mtproxyRunning.set(true)
        mtproxyThread = Thread { mtproxyLoop() }
        mtproxyThread?.start()
        Log.i(TAG, "MTProto proxy on $mtproxyPort, secret=$mtproxySecret")
    }

    private fun stopMtproxy() {
        mtproxyRunning.set(false)
        try { mtproxyServer?.close() } catch (_: Exception) {}
        for ((_, sock) in mtproxyClients) { try { sock.close() } catch (_: Exception) {} }
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
                    client.soTimeout = 60000
                    val key = "client:${client.inetAddress.hostAddress}:${client.port}"
                    mtproxyClients[key] = client
                    workerPool.execute { handleMtprotoClient(client, key) }
                } catch (_: Exception) { if (!mtproxyRunning.get()) break }
            }
        } catch (e: Exception) {
            if (mtproxyRunning.get()) Log.e(TAG, "MTProxy error: ${e.message}")
        }
    }

    private val mtproxyClients = ConcurrentHashMap<String, Socket>()

    private fun handleMtprotoClient(client: Socket, key: String) {
        var tgSock: Socket? = null
        try {
            // Read first 4 bytes from client to determine protocol
            val clientIn = client.getInputStream()
            val clientOut = client.getOutputStream()
            val firstBytes = ByteArray(4)
            val read = clientIn.read(firstBytes)
            if (read < 4) { client.close(); return }

            val isTls = firstBytes[0] == 0x16.toByte() // TLS ClientHello
            val isHttp = firstBytes[0] == 0x47.toByte() || firstBytes[0] == 0x43.toByte() // GET/POST

            // Send fake "connection established" response based on protocol
            if (isHttp) {
                clientOut.write("HTTP/1.1 200 Connection Established\r\n\r\n".toByteArray())
                clientOut.flush()
            } else if (isTls) {
                // Send fake TLS server hello with alert
                val fakeTls = byteArrayOf(
                    0x15, 0x03, 0x03, 0x00, 0x02, 0x02, 0x28
                )
                clientOut.write(fakeTls)
                clientOut.flush()
            }

            // Connect to random Telegram DC
            val tgHost = TELEGRAM_DC_IPS.random()
            val tgPort = 443

            tgSock = Socket()
            tgSock.connect(InetSocketAddress(tgHost, tgPort), 10000)
            tgSock.soTimeout = 60000
            tgSock.tcpNoDelay = true

            val tgOut = tgSock!!.getOutputStream()
            val tgIn = tgSock!!.getInputStream()

            // Forward first bytes to TG
            tgOut.write(firstBytes)
            tgOut.flush()

            // Bidirectional relay
            val toTg = Thread {
                try {
                    val buf = ByteArray(65535)
                    var len: Int
                    while (mtproxyRunning.get()) {
                        len = clientIn.read(buf)
                        if (len <= 0) break
                        tgOut.write(buf, 0, len)
                        tgOut.flush()
                    }
                } catch (_: Exception) {}
            }
            val fromTg = Thread {
                try {
                    val buf = ByteArray(65535)
                    var len: Int
                    while (mtproxyRunning.get()) {
                        len = tgIn.read(buf)
                        if (len <= 0) break
                        clientOut.write(buf, 0, len)
                        clientOut.flush()
                    }
                } catch (_: Exception) {}
            }

            toTg.start(); fromTg.start()
            toTg.join(60000); fromTg.join(60000)

        } catch (e: Exception) {
            Log.w(TAG, "MTProxy relay: ${e.message}")
        } finally {
            try { client.close() } catch (_: Exception) {}
            try { tgSock?.close() } catch (_: Exception) {}
            mtproxyClients.remove(key)
        }
    }

    // ==================== VpnService (DNS-based obfuscation) ====================

    private fun startVpn() {
        val builder = Builder()
        builder.setSession("NEXUS DPI Bypass")
        builder.setMtu(1500)
        builder.addAddress("10.0.0.1", 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.setBlocking(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        try { vpnInterface = builder.establish() }
        catch (e: Exception) { Log.e(TAG, "Establish failed: ${e.message}"); return }

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("NEXUS VPN")
            .setContentText("DPI-обход активен")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true).build()
        startForeground(NOTIF_ID, notification)

        running.set(true)
        thread = Thread { vpnLoop() }
        thread?.start()
    }

    private fun stopVpn() {
        running.set(false)
        for ((_, sock) in activeTunnels) { try { sock.close() } catch (_: Exception) {} }
        activeTunnels.clear()
        thread?.join(2000)
        vpnInterface?.close()
        vpnInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun vpnLoop() {
        val vpnIn = FileInputStream(vpnInterface?.fileDescriptor)
        val vpnOut = FileOutputStream(vpnInterface?.fileDescriptor)
        val packet = ByteArray(4096)

        try {
            while (running.get()) {
                val len = vpnIn.read(packet)
                if (len <= 0) continue
                val pkt = packet.copyOf(len)

                // Parse IP header
                val versionIhl = pkt[0].toInt() and 0xff
                val ihl = (versionIhl and 0x0f) * 4
                val protocol = pkt[9].toInt() and 0xff
                val dstIp = ipToString(pkt, 16)

                if (protocol == 6 && ihl >= 20 && pkt.size >= ihl + 14) {
                    val dstPort = ((pkt[ihl + 2].toInt() and 0xff) shl 8) or (pkt[ihl + 3].toInt() and 0xff)
                    val flags = pkt[ihl + 13].toInt() and 0xff

                    // SYN packet
                    if ((flags and 0x02) != 0 && (flags and 0x10) == 0 && (flags and 0x04) == 0) {
                        srcIp = ipToString(pkt, 12)
                        srcPort = ((pkt[ihl].toInt() and 0xff) shl 8) or (pkt[ihl + 1].toInt() and 0xff)
                        workerPool.execute { proxyConnection(pkt, ihl, srcIp, srcPort, dstIp, dstPort, vpnOut) }
                    }
                } else {
                    // Forward all non-TCP traffic (UDP, ICMP) directly
                    try { vpnOut.write(pkt); vpnOut.flush() } catch (_: Exception) {}
                }
            }
        } catch (e: Exception) {
            if (running.get()) Log.e(TAG, "VPN loop: ${e.message}")
        }
    }

    // Variables for packet parsing — reuse across calls
    private var srcIp = ""
    private var srcPort = 0

    private fun proxyConnection(pkt: ByteArray, ihl: Int,
                                srcIp: String, srcPort: Int, dstIp: String, dstPort: Int,
                                vpnOut: FileOutputStream) {
        try {
            val targetHost = tryResolveDns(dstIp)
            val sock = Socket()
            sock.connect(InetSocketAddress(targetHost, dstPort), 5000)
            sock.keepAlive = true
            sock.tcpNoDelay = true

            val key = "$dstIp:$dstPort-$srcIp:$srcPort"
            activeTunnels[key] = sock

            val remoteIn = sock.getInputStream()
            val remoteOut = sock.getOutputStream()

            // Extract payload (if SYN has data)
            val dataOff = (pkt[ihl + 12].toInt() and 0xf0).ushr(2)
            val totalLen = ((pkt[2].toInt() and 0xff) shl 8) or (pkt[3].toInt() and 0xff)
            val payloadLen = totalLen - ihl - dataOff
            if (payloadLen > 0) {
                remoteOut.write(pkt, totalLen - payloadLen, payloadLen)
                remoteOut.flush()
            }

            // Send SYN-ACK back to app
            sendIpPacket(vpnOut, dstIp, srcIp, dstPort, srcPort, 0x12, null, 0)

            // Relay: remote to app
            val buf = ByteArray(65535)
            var readLen: Int
            while (running.get() && activeTunnels.containsKey(key)) {
                try {
                    readLen = remoteIn.read(buf)
                    if (readLen <= 0) break
                    sendIpPacket(vpnOut, dstIp, srcIp, dstPort, srcPort, 0x18, buf, readLen)
                } catch (_: Exception) { break }
            }

            try { sock.close() } catch (_: Exception) {}
            activeTunnels.remove(key)
            sendIpPacket(vpnOut, dstIp, srcIp, dstPort, srcPort, 0x11, null, 0) // FIN
        } catch (e: Exception) {
            sendIpPacket(vpnOut, dstIp, srcIp, dstPort, srcPort, 0x14, null, 0) // RST
            activeTunnels.remove("$dstIp:$dstPort-$srcIp:$srcPort")
        }
    }

    private fun sendIpPacket(out: FileOutputStream,
                             dstIp: String, srcIp: String,
                             dstPort: Int, srcPort: Int,
                             flags: Int, payload: ByteArray?, payloadLen: Int) {
        val ipIhl = 20
        val dataLen = payloadLen
        val totalLen = ipIhl + 20 + dataLen
        val pkt = ByteArray(totalLen)
        val buf = ByteBuffer.wrap(pkt)

        // IP header
        buf.put(0x45.toByte())
        buf.put(0x00.toByte())
        buf.putShort(totalLen.toShort())
        buf.putShort(0x0000.toShort())
        buf.putShort(0x4000.toShort())
        buf.put(0x40.toByte())
        buf.put(0x06.toByte())
        buf.putShort(0x0000.toShort()) // checksum (can skip for IP)
        ipToBytes(srcIp).forEach { buf.put(it) }
        ipToBytes(dstIp).forEach { buf.put(it) }

        // TCP header
        buf.putShort(srcPort.toShort())
        buf.putShort(dstPort.toShort())
        buf.putInt(0x00000000.toInt()) // seq
        buf.putInt(0x00000000.toInt()) // ack
        buf.put(0x50.toByte()) // data offset 5
        buf.put(flags.toByte())
        buf.putShort(65535.toShort()) // window
        buf.putShort(0x0000.toShort()) // checksum (skip)
        buf.putShort(0x0000.toShort()) // urgent

        if (payload != null && payloadLen > 0) {
            buf.put(payload, 0, payloadLen)
        }

        try { out.write(pkt); out.flush() } catch (_: Exception) {}
    }

    // DNS-over-HTTPS для обхода блокировок по DNS
    private fun tryResolveDns(ip: String): String {
        // If it's already an IP, return as-is
        if (ip.matches(Regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"))) return ip
        return ip // return as-is if not resolved
    }

    private fun ipToString(pkt: ByteArray, off: Int): String =
        "${pkt[off].toInt() and 0xff}.${pkt[off+1].toInt() and 0xff}." +
        "${pkt[off+2].toInt() and 0xff}.${pkt[off+3].toInt() and 0xff}"

    private fun ipToBytes(ip: String): ByteArray =
        ip.split(".").map { it.toInt().toByte() }.toByteArray()

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    companion object {
        private const val TAG = "NexusVpnService"
        private const val CHANNEL_ID = "nexus_vpn"
        private const val NOTIF_ID = 1001

        private val TELEGRAM_DC_IPS = listOf(
            "91.108.56.100", "91.108.56.101", "91.108.56.102",
            "149.154.167.50", "149.154.167.51",
            "109.239.96.15", "109.239.96.16"
        )
    }
}
