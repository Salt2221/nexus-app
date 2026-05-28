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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

class NexusVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private val workerPool = Executors.newCachedThreadPool()
    private val activeTunnels = ConcurrentHashMap<String, Socket>()

    // ===== MTProto Proxy (встроенный) =====
    private var mtproxyRunning = AtomicBoolean(false)
    private var mtproxyThread: Thread? = null
    private var mtproxyServer: ServerSocket? = null
    private val mtproxyClients = ConcurrentHashMap<String, Socket>()
    private var mtproxyPort = 1443

    // ===== Telegram DC IPs для прямого подключения =====
    private val TELEGRAM_DC_IPS = listOf(
        "91.108.56.100", "91.108.56.101", "91.108.56.102", "91.108.56.103",
        "91.108.56.110", "91.108.56.120", "91.108.56.130", "91.108.56.150",
        "91.108.56.170", "91.108.56.180", "91.108.56.200",
        "149.154.167.50", "149.154.167.51", "149.154.167.91", "149.154.175.50",
        "109.239.96.15", "109.239.96.16", "109.239.96.17", "109.239.96.18"
    )

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
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
            val channel = NotificationChannel(CHANNEL_ID, "NEXUS VPN", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    // ==================== MTProto Proxy Server (встроенный) ====================

    private fun startMtproxy() {
        if (mtproxyRunning.get()) return
        mtproxyRunning.set(true)
        mtproxyThread = Thread { mtproxyLoop() }
        mtproxyThread?.start()
        Log.i(TAG, "MTProto proxy запущен на порту $mtproxyPort")
    }

    private fun stopMtproxy() {
        mtproxyRunning.set(false)
        try { mtproxyServer?.close() } catch (_: Exception) {}
        for ((_, sock) in mtproxyClients) {
            try { sock.close() } catch (_: Exception) {}
        }
        mtproxyClients.clear()
        mtproxyThread?.join(1000)
        mtproxyServer = null
        Log.i(TAG, "MTProto proxy остановлен")
    }

    private fun mtproxyLoop() {
        try {
            mtproxyServer = ServerSocket(mtproxyPort, 50, InetAddress.getByName("127.0.0.1"))
            while (mtproxyRunning.get()) {
                try {
                    val client = mtproxyServer!!.accept()
                    client.soTimeout = 30000
                    val addr = client.inetAddress.hostAddress ?: "unknown"
                    val clientKey = "$addr:${client.port}"
                    mtproxyClients[clientKey] = client

                    // Telegram DC to connect to
                    val tgHost = TELEGRAM_DC_IPS.random()
                    val tgPort = 443

                    workerPool.execute { relayClientToTelegram(client, tgHost, tgPort, clientKey) }
                } catch (_: Exception) { if (!mtproxyRunning.get()) break }
            }
        } catch (e: Exception) {
            if (mtproxyRunning.get()) Log.e(TAG, "MTProxy server error: ${e.message}")
        }
    }

    private fun relayClientToTelegram(client: Socket, tgHost: String, tgPort: Int, clientKey: String) {
        var tgSock: Socket? = null
        try {
            // Connect to Telegram directly (bypassing DPI via raw TCP)
            tgSock = Socket()
            tgSock.connect(InetSocketAddress(tgHost, tgPort), 10000)
            tgSock.soTimeout = 30000
            tgSock.tcpNoDelay = true

            val clientIn = client.getInputStream()
            val clientOut = client.getOutputStream()
            val tgOut = tgSock!!.getOutputStream()
            val tgIn = tgSock!!.getInputStream()

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
            Log.w(TAG, "MTProxy relay failed: ${e.message}")
        } finally {
            try { client.close() } catch (_: Exception) {}
            try { tgSock?.close() } catch (_: Exception) {}
            mtproxyClients.remove(clientKey)
        }
    }

    // ==================== VpnService ====================

    private fun startVpn() {
        val builder = Builder()
        builder.setSession("NEXUS DPI Bypass")
        builder.setMtu(1500)
        builder.addAddress("10.0.0.2", 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.setBlocking(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        try { vpnInterface = builder.establish() }
        catch (e: Exception) { Log.e(TAG, "Establish failed: ${e.message}"); return }

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("NEXUS")
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
        thread?.join(1000)
        vpnInterface?.close()
        vpnInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun vpnLoop() {
        val vpnIn = FileInputStream(vpnInterface?.fileDescriptor)
        val vpnOut = FileOutputStream(vpnInterface?.fileDescriptor)
        val packet = ByteArray(65535)

        try {
            while (running.get()) {
                val len = vpnIn.read(packet)
                if (len <= 0) continue
                val pkt = packet.copyOf(len)
                workerPool.execute { processPacket(pkt, vpnOut) }
            }
        } catch (e: Exception) {
            if (running.get()) Log.e(TAG, "VPN loop error: ${e.message}")
        }
    }

    private fun processPacket(packet: ByteArray, vpnOut: FileOutputStream) {
        try {
            val versionIhl = packet[0].toInt() and 0xff
            val ihl = (versionIhl and 0x0f) * 4
            val totalLen = ((packet[2].toInt() and 0xff) shl 8) or (packet[3].toInt() and 0xff)
            val protocol = packet[9].toInt() and 0xff

            val srcIp = ipToString(packet, 12)
            val dstIp = ipToString(packet, 16)

            if (protocol == 6) { // TCP
                val srcPort = ((packet[ihl].toInt() and 0xff) shl 8) or (packet[ihl + 1].toInt() and 0xff)
                val dstPort = ((packet[ihl + 2].toInt() and 0xff) shl 8) or (packet[ihl + 3].toInt() and 0xff)
                val flags = packet[ihl + 13].toInt() and 0xff
                val isSyn = flags and 0x02 != 0
                val isFin = flags and 0x01 != 0
                val isRst = flags and 0x04 != 0

                if (isSyn && !isFin && !isRst) {
                    handleTcpProxy(packet, totalLen, ihl, srcIp, srcPort, dstIp, dstPort, vpnOut)
                } else if (isFin || isRst) {
                    val key = "$dstIp:$dstPort-$srcIp:$srcPort"
                    val sock = activeTunnels.remove(key)
                    try { sock?.close() } catch (_: Exception) {}
                    sendRst(packet, ihl, srcIp, dstIp, srcPort, dstPort, vpnOut)
                }
            } else {
                vpnOut.write(packet)
                vpnOut.flush()
            }
        } catch (_: Exception) {}
    }

    private fun handleTcpProxy(packet: ByteArray, totalLen: Int, ihl: Int,
                               srcIp: String, srcPort: Int, dstIp: String, dstPort: Int,
                               vpnOut: FileOutputStream) {
        workerPool.execute {
            var targetHost = dstIp
            var targetPort = dstPort

            // Если это Telegram — подключаемся напрямую через MTProto DC
            if (isTelegramIp(dstIp)) {
                targetHost = TELEGRAM_DC_IPS.random()
                targetPort = 443
            }

            try {
                val sock = Socket()
                sock.connect(InetSocketAddress(targetHost, targetPort), 5000)
                sock.keepAlive = true
                sock.tcpNoDelay = true

                val key = "$dstIp:$dstPort-$srcIp:$srcPort"
                activeTunnels[key] = sock

                val remoteOut = sock.getOutputStream()
                val remoteIn = sock.getInputStream()

                // Forward SYN payload if present
                val dataOff = (packet[ihl + 12].toInt() and 0xf0).ushr(2)
                val payloadLen = totalLen - ihl - dataOff
                if (payloadLen > 0) {
                    remoteOut.write(packet, totalLen - payloadLen, payloadLen)
                    remoteOut.flush()
                }

                // SYN-ACK back
                sendSynAck(packet, ihl, srcIp, dstIp, srcPort, dstPort, vpnOut)

                // Relay loop: remote -> app
                val buf = ByteArray(65535)
                var readLen: Int
                while (running.get()) {
                    try {
                        readLen = remoteIn.read(buf)
                        if (readLen <= 0) break
                        sendData(buf, readLen, srcIp, dstIp, srcPort, dstPort, vpnOut)
                    } catch (_: Exception) { break }
                }

                try { sock.close() } catch (_: Exception) {}
                activeTunnels.remove(key)
                sendFin(packet, ihl, srcIp, dstIp, srcPort, dstPort, vpnOut)
            } catch (e: Exception) {
                sendRst(packet, ihl, srcIp, dstIp, srcPort, dstPort, vpnOut)
            }
        }
    }

    // ===== Packet builders =====

    private fun sendSynAck(packet: ByteArray, ihl: Int,
                           srcIp: String, dstIp: String, srcPort: Int, dstPort: Int,
                           out: FileOutputStream) {
        val pkt = buildTcpPacket(ihl, srcIp, dstIp, srcPort, dstPort, 0x12, null, 0)
        try { out.write(pkt); out.flush() } catch (_: Exception) {}
    }

    private fun sendData(data: ByteArray, dataLen: Int,
                         srcIp: String, dstIp: String, srcPort: Int, dstPort: Int,
                         out: FileOutputStream) {
        val pkt = buildTcpPacket(20, srcIp, dstIp, srcPort, dstPort, 0x18, data, dataLen)
        try { out.write(pkt); out.flush() } catch (_: Exception) {}
    }

    private fun sendFin(packet: ByteArray, ihl: Int,
                        srcIp: String, dstIp: String, srcPort: Int, dstPort: Int,
                        out: FileOutputStream) {
        val pkt = buildTcpPacket(ihl, srcIp, dstIp, srcPort, dstPort, 0x11, null, 0)
        try { out.write(pkt); out.flush() } catch (_: Exception) {}
    }

    private fun sendRst(packet: ByteArray, ihl: Int,
                        srcIp: String, dstIp: String, srcPort: Int, dstPort: Int,
                        out: FileOutputStream) {
        val pkt = buildTcpPacket(ihl, srcIp, dstIp, srcPort, dstPort, 0x14, null, 0)
        try { out.write(pkt); out.flush() } catch (_: Exception) {}
    }

    private fun buildTcpPacket(ihl: Int, srcIp: String, dstIp: String,
                               srcPort: Int, dstPort: Int, flags: Int,
                               payload: ByteArray?, payloadLen: Int): ByteArray {
        val tcpHdrLen = 20
        val dataLen = payloadLen
        val totalIpLen = ihl + tcpHdrLen + dataLen
        val pkt = ByteArray(totalIpLen)
        val buf = ByteBuffer.wrap(pkt)

        // IP header
        buf.put((0x45).toByte())        // v4, IHL=5
        buf.put(0x00.toByte())          // DSCP
        buf.putShort(totalIpLen.toShort())
        buf.putShort(0x0000.toShort())  // id
        buf.putShort(0x4000.toShort())  // flags
        buf.put(0x40.toByte())          // TTL
        buf.put(0x06.toByte())          // TCP
        buf.putShort(0.toShort())       // checksum
        // Reverse IPs
        ipToBytes(dstIp).forEach { buf.put(it) }
        ipToBytes(srcIp).forEach { buf.put(it) }

        // TCP header
        buf.putShort(dstPort.toShort())
        buf.putShort(srcPort.toShort())
        buf.putInt(0)   // seq
        buf.putInt(0)   // ack
        buf.put(((5 shl 4) or 0).toByte()) // data offset
        buf.put(flags.toByte())
        buf.putShort(65535.toShort()) // window
        buf.putShort(0)  // checksum
        buf.putShort(0)  // urgent

        if (payload != null && payloadLen > 0) {
            buf.put(payload, 0, payloadLen)
        }
        return pkt
    }

    // ===== Helpers =====

    private fun ipToString(packet: ByteArray, off: Int): String {
        return "${packet[off].toInt() and 0xff}.${packet[off+1].toInt() and 0xff}." +
               "${packet[off+2].toInt() and 0xff}.${packet[off+3].toInt() and 0xff}"
    }

    private fun ipToBytes(ip: String): ByteArray {
        return ip.split(".").map { it.toInt().toByte() }.toByteArray()
    }

    private fun isTelegramIp(ip: String): Boolean {
        val parts = ip.split(".").map { it.toInt() }
        if (parts.size != 4) return false
        return parts[0] == 91 || parts[0] == 149 || parts[0] == 109
    }

    companion object {
        private const val TAG = "NexusVpnService"
        private const val CHANNEL_ID = "nexus_vpn"
        private const val NOTIF_ID = 1001
    }
}
