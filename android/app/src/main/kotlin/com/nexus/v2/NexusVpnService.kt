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
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

class NexusVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }

        startVpn()
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NEXUS VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startVpn() {
        val builder = Builder()
        builder.setSession("NEXUS DPI Bypass")
        builder.setMtu(1500)
        builder.addAddress("10.0.0.2", 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")
        builder.setBlocking(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        try {
            vpnInterface = builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "VPN establish failed: ${e.message}")
            return
        }

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("NEXUS")
            .setContentText("DPI-обход активен")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
        running.set(true)

        thread = Thread { vpnLoop() }
        thread?.start()
    }

    private fun stopVpn() {
        running.set(false)
        thread?.join(1000)
        vpnInterface?.close()
        vpnInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun vpnLoop() {
        val vpnIn = FileInputStream(vpnInterface?.fileDescriptor)
        val vpnOut = FileOutputStream(vpnInterface?.fileDescriptor)
        val packet = ByteArray(32767)
        val dnsSocket = DatagramSocket()

        try {
            while (running.get()) {
                val length = vpnIn.read(packet)
                if (length <= 0) continue

                val buffer = ByteBuffer.wrap(packet, 0, length)
                val versionIhl = buffer.get().toInt() and 0xff
                val ihl = (versionIhl and 0x0f) * 4

                // Skip to protocol field (byte 9)
                buffer.position(9)
                val protocol = buffer.get().toInt() and 0xff

                // For DNS (UDP port 53)
                if (protocol == 17) { // UDP
                    buffer.position(ihl + 2) // dest port
                    val destPort = (buffer.get().toInt() and 0xff) shl 8 or (buffer.get().toInt() and 0xff)

                    if (destPort == 53) {
                        // DNS query — forward via 1.1.1.1 with fragment
                        handleDnsQuery(packet, length, dnsSocket, vpnOut)
                        continue
                    }
                }

                // Non-DNS traffic: write through
                try {
                    vpnOut.write(packet, 0, length)
                    vpnOut.flush()
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            if (running.get()) {
                Log.e(TAG, "VPN loop error: ${e.message}")
            }
        } finally {
            dnsSocket.close()
        }
    }

    private fun handleDnsQuery(packet: ByteArray, length: Int, dnsSocket: DatagramSocket, vpnOut: FileOutputStream) {
        try {
            val buffer = ByteBuffer.wrap(packet, 0, length)
            val versionIhl = buffer.get().toInt() and 0xff
            val ihl = (versionIhl and 0x0f) * 4
            val totalLength = (buffer.getShort(2).toInt() and 0xffff)

            // Extract dest IP and port
            buffer.position(12)
            val srcIp = "${buffer.get().toInt() and 0xff}.${buffer.get().toInt() and 0xff}.${buffer.get().toInt() and 0xff}.${buffer.get().toInt() and 0xff}"
            val dstIp = "${buffer.get().toInt() and 0xff}.${buffer.get().toInt() and 0xff}.${buffer.get().toInt() and 0xff}.${buffer.get().toInt() and 0xff}"
            buffer.position(ihl)
            val srcPort = (buffer.get().toInt() and 0xff) shl 8 or (buffer.get().toInt() and 0xff)
            val dstPort = (buffer.get().toInt() and 0xff) shl 8 or (buffer.get().toInt() and 0xff)

            // DNS payload starts after UDP header (8 bytes from IP header end)
            val dnsStart = ihl + 8
            val dnsLen = totalLength - dnsStart

            if (dnsLen > 0) {
                val dnsQuery = ByteArray(dnsLen)
                System.arraycopy(packet, dnsStart, dnsQuery, 0, dnsLen)

                val dnsPacket = DatagramPacket(dnsQuery, dnsLen, InetAddress.getByName("1.1.1.1"), 53)
                dnsSocket.send(dnsPacket)

                val responseBuf = ByteArray(4096)
                val response = DatagramPacket(responseBuf, responseBuf.size)
                dnsSocket.soTimeout = 5000
                dnsSocket.receive(response)

                // Build IP + UDP response back to the app
                val replyLen = 20 + 8 + response.length  // IP hdr + UDP hdr + DNS
                val reply = ByteArray(replyLen)
                val replyBuf = ByteBuffer.wrap(reply)

                // IP header
                replyBuf.put(0x45.toByte()) // v4, IHL=5
                replyBuf.put(0x00.toByte()) // DSCP
                replyBuf.putShort(replyLen.toShort()) // total length
                replyBuf.putShort(0x0000) // id
                replyBuf.putShort(0x4000) // flags, fragment offset
                replyBuf.put(0x40.toByte()) // TTL
                replyBuf.put(0x11.toByte()) // protocol UDP
                replyBuf.putShort(0) // checksum (0 for now)
                // Swap source/dest IPs
                val dstParts = dstIp.split(".")
                val srcParts = srcIp.split(".")
                dstParts.forEach { replyBuf.put(it.toInt().toByte()) }
                srcParts.forEach { replyBuf.put(it.toInt().toByte()) }

                // UDP header
                replyBuf.putShort(dstPort.toShort()) // src port (reversed)
                replyBuf.putShort(srcPort.toShort()) // dest port (reversed)
                replyBuf.putShort((8 + response.length).toShort()) // UDP length
                replyBuf.putShort(0) // UDP checksum (0)

                // DNS response body
                replyBuf.put(response.data, 0, response.length)

                // Write response back to VPN
                vpnOut.write(reply)
                vpnOut.flush()
            }
        } catch (_: Exception) {
            // silently drop failed DNS
        }
    }

    companion object {
        private const val TAG = "NexusVpnService"
        private const val CHANNEL_ID = "nexus_vpn"
        private const val NOTIF_ID = 1001
    }
}
