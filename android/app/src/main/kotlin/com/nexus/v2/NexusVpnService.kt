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

        try {
            while (running.get()) {
                val len = input.read(buf)
                if (len <= 0) continue
                val pkt = buf.copyOf(len)

                // Forward all packets to the output (simple pass-through)
                // In a full implementation, we'd intercept DNS and route through MTProto
                try { output.write(pkt); output.flush() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            if (running.get()) Log.e(TAG, "VPN loop: ${e.message}")
        }
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
