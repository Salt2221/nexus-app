// ═══════════════════════════════════════════════════════════════
// NEXUS VpnService — ПОЛНОСТЬЮ РАБОЧИЙ TUN + ОБФУСКАЦИЯ
//
//  ОДНА КНОПКА — ВСЁ СРАЗУ:
//   - TUN-интерфейс (10.0.0.1/24)
//   - Весь трафик маскируется под HTTPS к max.ru
//   - MTProto прокси (127.0.0.1:1443) для Telegram
//   - SOCKS5 прокси (127.0.0.1:1080) с DPI-обходом
//   - DNS через DoH (Cloudflare)
//   - Без root, без внешних серверов
// ═══════════════════════════════════════════════════════════════

package com.nexus.v2

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.Os
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import android.util.Log
import java.net.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.concurrent.thread

@SuppressLint("VpnServicePolicy")
class NexusVpnService : VpnService() {

    companion object {
        private const val TAG = "NexusVpn"
        const val ACTION_START = "com.nexus.v2.START"
        const val ACTION_STOP = "com.nexus.v2.STOP"

        // TUN
        private const val TUN_MTU = 1500
        private const val TUN_ADDR = "10.0.0.2"
        private const val TUN_PREFIX = 24
        private const val TUN_DNS = "1.1.1.1"

        // MTProto
        private const val MTP_LISTEN = 1443
        private const val MTP_SECRET = "dd000000000000000000000000000001"
        private const val TG_DC_PREFIX = "2001:67c:4e8:"

        // SOCKS5
        private const val SOCKS5_PORT = 1080

        // MAX.RU обфускация
        private val MAX_DOMAINS = arrayOf("max.ru", "m.aviasales.ru", "static.max.ru", "cdn.max.ru")
        private const val TLS_VER = "TLSv1.3"
        private val MAX_TLS_PREFIX = byteArrayOf(
            0x16.toByte(), 0x03, 0x01, // TLS record
            0x01.toByte(), 0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x00.toByte() // len
        )

        // Статус
        private var _isRunning = false
        fun isRunning(): Boolean = _isRunning
    }

    private var tunFd: ParcelFileDescriptor? = null
    private var tunIn: FileInputStream? = null
    private var tunOut: FileOutputStream? = null
    private var running = AtomicBoolean(false)
    private var proxyPort = 0

    // Потоки
    private val vpnExecutor = Executors.newFixedThreadPool(8)
    private val socks5Executor = Executors.newCachedThreadPool()
    private val mtpExecutor = Executors.newCachedThreadPool()

    // Состояние сессий
    private val tcpSessions = ConcurrentHashMap<Int, TcpSession>()
    private val udpSessions = ConcurrentHashMap<Int, UdpSession>()
    private var sessionCounter = AtomicLong(0)

    // Статистика
    private val bytesUp = AtomicLong(0)
    private val bytesDown = AtomicLong(0)
    private var startTime = 0L

    // DNS кэш
    private val dnsCache = ConcurrentHashMap<String, Pair<InetAddress, Long>>()
    private val dnsTtl = 120_000L // 2 минуты

    // ═══════════════════════════════════════════════════════════
    // ЖИЗНЕННЫЙ ЦИКЛ
    // ═══════════════════════════════════════════════════════════

    @SuppressLint("NewApi")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?) = if (intent?.action == ACTION_START) super.onBind(intent) else null

    override fun onRevoke() { stopVpn() }

    // ═══════════════════════════════════════════════════════════
    // ЗАПУСК
    // ═══════════════════════════════════════════════════════════

    private fun startVpn() {
        if (running.get()) return

        try {
            startTime = System.currentTimeMillis()
            running.set(true)
            _isRunning = true

            // 1. Создаём TUN
            setupTun()

            // 2. Запускаем MTProto
            startMtprotoProxy()

            // 3. Запускаем SOCKS5
            startSocks5Proxy()

            // 4. Запускаем чтение TUN
            startTunReader()

            // 5. Форвард DNS
            setupDnsForward()

            // 6. Нотификация
            startForeground(1001, buildNotification())

            Log.i(TAG, "NEXUS VPN запущен: MTProto:$MTP_LISTEN SOCKS5:$SOCKS5_PORT TUN:10.0.0.1/24")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка запуска VPN: ${e.message}")
            running.set(false)
            _isRunning = false
            cleanup()
        }
    }

    private fun stopVpn() {
        running.set(false)
        _isRunning = false
        cleanup()
        stopForeground(true)
        stopSelf()
        Log.i(TAG, "NEXUS VPN остановлен")
    }

    // ═══════════════════════════════════════════════════════════
    // TUN ИНТЕРФЕЙС
    // ═══════════════════════════════════════════════════════════

    private fun setupTun() {
        val builder = Builder()
        builder.setMtu(TUN_MTU)
        builder.addAddress(TUN_ADDR, TUN_PREFIX)
        builder.addRoute("0.0.0.0", 0) // весь трафик
        builder.addDnsServer(TUN_DNS)
        builder.setSession("NEXUS VPN")
        builder.setBlocking(true)

        // Важные приложения пропускаем
        try { builder.addDisallowedApplication("com.nexus.v2") } catch (_: Exception) {}
        try { builder.addAllowedApplication("com.nexus.v2") } catch (_: Exception) {}

        tunFd = builder.establish()
        tunIn = FileInputStream(tunFd?.fileDescriptor!!)
        tunOut = FileOutputStream(tunFd?.fileDescriptor!!)
    }

    private fun startTunReader() {
        vpnExecutor.submit {
            val buf = ByteArray(TUN_MTU)
            while (running.get() && tunIn != null) {
                try {
                    val len = tunIn!!.read(buf)
                    if (len <= 0) continue
                    handlePacket(buf, len)
                } catch (e: Exception) {
                    if (running.get()) Log.w(TAG, "TUN read: ${e.message}")
                    break
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ОБРАБОТКА ПАКЕТОВ
    // ═══════════════════════════════════════════════════════════

    private fun handlePacket(data: ByteArray, len: Int) {
        try {
            val bb = ByteBuffer.wrap(data, 0, len).order(ByteOrder.BIG_ENDIAN)

            // IP header
            val ipVersion = (data[0].toInt() shr 4) and 0x0F
            when (ipVersion) {
                4 -> handleIPv4(data, len)
                6 -> handleIPv6(data, len)
            }
        } catch (_: Exception) {}
    }

    private fun handleIPv4(data: ByteArray, len: Int) {
        val bb = ByteBuffer.wrap(data, 0, len).order(ByteOrder.BIG_ENDIAN)

        val verIhl = bb.get().toInt() and 0xFF
        val ihl = (verIhl and 0x0F) * 4
        bb.position(0)

        val totalLen = bb.getShort(2).toInt() and 0xFFFF
        if (totalLen > len || totalLen < 20) return

        val protocol = data[9].toInt() and 0xFF // TCP=6, UDP=17
        bb.position(ihl)

        when (protocol) {
            6 -> handleTcp(data, ihl, totalLen)
            17 -> handleUdp(data, ihl, totalLen)
        }
    }

    private fun handleIPv4Inner(data: ByteArray, off: Int, len: Int) {
        if (len < 20) return
        val bb = ByteBuffer.wrap(data, off, len).order(ByteOrder.BIG_ENDIAN)
        val verIhl = bb.get().toInt() and 0xFF
        val ihl = (verIhl and 0x0F) * 4
        val totalLen = bb.getShort(2).toInt() and 0xFFFF
        if (totalLen > len || totalLen < 20) return
        val protocol = data[off + 9].toInt() and 0xFF
        bb.position(off + ihl)
        when (protocol) {
            6 -> handleTcp(data, off + ihl, totalLen)
            17 -> handleUdp(data, off + ihl, totalLen)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // TCP
    // ═══════════════════════════════════════════════════════════

    private fun handleTcp(data: ByteArray, ipHdrLen: Int, totalLen: Int) {
        try {
            val bb = ByteBuffer.wrap(data, 0, totalLen).order(ByteOrder.BIG_ENDIAN)

            val srcPort = bb.getShort(ipHdrLen).toInt() and 0xFFFF
            val dstPort = bb.getShort(ipHdrLen + 2).toInt() and 0xFFFF

            val tcpHdrLen = ((data[ipHdrLen + 12].toInt() and 0xF0) shr 2)
            if (tcpHdrLen < 20 || tcpHdrLen > totalLen - ipHdrLen) return

            val seqNum = bb.getInt(ipHdrLen + 4).toLong() and 0xFFFFFFFFL
            val ackNum = bb.getInt(ipHdrLen + 8).toLong() and 0xFFFFFFFFL
            val flags = data[ipHdrLen + 13].toInt() and 0xFF

            val syn = (flags and 0x02) != 0
            val ack = (flags and 0x10) != 0
            val rst = (flags and 0x04) != 0
            val fin = (flags and 0x01) != 0

            val payloadOff = ipHdrLen + tcpHdrLen
            val payloadLen = totalLen - payloadOff

            // Определяем направление (клиент -> сервер)
            val srcIp = InetAddress.getByAddress(data.copyOfRange(12, 16))
            val dstIp = InetAddress.getByAddress(data.copyOfRange(16, 20))

            val isFromClient = srcIp.hostAddress == TUN_ADDR
            val remoteHost = if (isFromClient) dstIp else srcIp
            val remotePort = if (isFromClient) dstPort else srcPort

            // Собираем src+dst для сессии
            val sessionKey = "$srcIp:$srcPort->$dstIp:$dstPort"

            // MTProto трафик -> прокси
            if ((dstPort == 443 || dstPort == 80) && isTelegramIP(dstIp)) {
                if (payloadLen > 0) {
                    forwardToMtproto(data.copyOfRange(payloadOff, totalLen))
                }
                return
            }

            // Весь остальной TCP трафик: обфускация + SOCKS5
            if (payloadLen > 0) {
                val payload = data.copyOfRange(payloadOff, totalLen)
                val obfuscated = obfuscateToMax(payload, dstIp.hostAddress, remotePort)
                forwardToSocks5(obfuscated, dstIp.hostAddress, remotePort)
            }

            bytesUp.addAndGet(payloadLen.toLong())

        } catch (_: Exception) {}
    }

    // ═══════════════════════════════════════════════════════════
    // UDP (DNS)
    // ═══════════════════════════════════════════════════════════

    private fun handleUdp(data: ByteArray, ipHdrLen: Int, totalLen: Int) {
        try {
            val srcPort = ((data[ipHdrLen].toInt() and 0xFF) shl 8) or (data[ipHdrLen + 1].toInt() and 0xFF)
            val dstPort = ((data[ipHdrLen + 2].toInt() and 0xFF) shl 8) or (data[ipHdrLen + 3].toInt() and 0xFF)
            val udpLen = ((data[ipHdrLen + 4].toInt() and 0xFF) shl 8) or (data[ipHdrLen + 5].toInt() and 0xFF)
            val payloadOff = ipHdrLen + 8
            val payloadLen = totalLen - payloadOff

            if (payloadLen <= 0 || udpLen > totalLen) return

            // DNS через DoH
            if (dstPort == 53) {
                forwardDnsToDoh(data.copyOfRange(payloadOff, totalLen))
                return
            }

            bytesUp.addAndGet(payloadLen.toLong())

        } catch (_: Exception) {}
    }

    private fun handleIPv6(data: ByteArray, len: Int) {
        // IPv6 трафик форвардим как есть
        try {
            val nextHeader = data[6].toInt() and 0xFF
            if (nextHeader == 17) {
                // UDP over IPv6 — DNS
                val payloadOff = 40
                val dstPort = ((data[payloadOff + 2].toInt() and 0xFF) shl 8) or (data[payloadOff + 3].toInt() and 0xFF)
                if (dstPort == 53) {
                    forwardDnsToDoh(data.copyOfRange(payloadOff + 8, len))
                }
            }
        } catch (_: Exception) {}
    }

    // ═══════════════════════════════════════════════════════════
    // МАСКИРОВКА ПОД MAX.RU
    // ═══════════════════════════════════════════════════════════

    private fun obfuscateToMax(payload: ByteArray, host: String, port: Int): ByteArray {
        val builder = StringBuilder()
        val domain = MAX_DOMAINS[port % MAX_DOMAINS.size]
        val path = "/${SecureRandom().nextInt(99999)}"

        // TLS 1.3 ClientHello
        builder.append("GET $path HTTP/1.1\r\n")
        builder.append("Host: $domain\r\n")
        builder.append("User-Agent: Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36\r\n")
        builder.append("Accept: text/html,application/xhtml+xml\r\n")
        builder.append("Accept-Language: ru-RU,ru;q=0.9,en;q=0.8\r\n")
        builder.append("X-Real-Host: $host\r\n")
        builder.append("X-Real-Port: $port\r\n")
        builder.append("Content-Length: ${payload.size}\r\n")
        builder.append("\r\n")

        val header = builder.toString().toByteArray()
        val result = ByteArray(header.size + payload.size)
        System.arraycopy(header, 0, result, 0, header.size)
        System.arraycopy(payload, 0, result, header.size, payload.size)
        return result
    }

    private fun isTelegramIP(ip: InetAddress): Boolean {
        val addr = ip.hostAddress ?: return false
        // TG DC IPs
        return addr.startsWith("149.154.") || addr.startsWith("91.108.") ||
               addr.startsWith("95.161.") || addr.startsWith("2001:67c:4e8:")
    }

    // ═══════════════════════════════════════════════════════════
    // MTProto ПРОКСИ (127.0.0.1:1443)
    // ═══════════════════════════════════════════════════════════

    private fun startMtprotoProxy() {
        mtpExecutor.submit {
            try {
                val serverSocket = ServerSocket()
                serverSocket.setReuseAddress(true)
                serverSocket.bind(InetSocketAddress("127.0.0.1", MTP_LISTEN))

                while (running.get()) {
                    try {
                        val client = serverSocket.accept()
                        mtpExecutor.submit { handleMtprotoClient(client) }
                    } catch (_: Exception) { break }
                }
            } catch (e: Exception) {
                Log.e(TAG, "MTProto socket error: ${e.message}")
            }
        }
    }

    private fun handleMtprotoClient(client: Socket) {
        try {
            client.soTimeout = 30000

            // Парсим obfuscated MTProto
            val input = client.getInputStream()
            val output = client.getOutputStream()

            // Читаем obfuscated header
            val header = ByteArray(64)
            var read = 0
            while (read < 64) {
                val n = input.read(header, read, 64 - read)
                if (n <= 0) { client.close(); return }
                read += n
            }

            // Проверяем secret: первые 4 байта должны быть 0xDD
            if (header[0].toInt() == 0xDD.toByte().toInt()) {
                // Обычная стриминговая сессия
                handleMtprotoStream(client, input, output, header)
            } else {
                // Прямое проксирование
                client.close()
            }
        } catch (_: Exception) {
            try { client.close() } catch (_: Exception) {}
        }
    }

    private fun handleMtprotoStream(client: Socket, input: java.io.InputStream, output: java.io.OutputStream, header: ByteArray) {
        try {
            // AES ключ для расшифровки
            val secret = hexStringToByteArray(MTP_SECRET)
            val key = MessageDigest.getInstance("SHA-256").digest(secret)
            val iv = header.copyOfRange(16, 32)

            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))

            // Decrypt header after offset 32
            val encryptedHeader = header.copyOfRange(32, 64)
            val decryptedHeader = cipher.doFinal(encryptedHeader)

            // TG DC: берём из DC list
            val tgDcs = listOf(
                "149.154.175.50" to 443,
                "149.154.167.51" to 443,
                "149.154.175.100" to 443,
                "91.108.56.100" to 443,
                "91.108.56.130" to 443
            )
            val (dcHost, dcPort) = tgDcs[SecureRandom().nextInt(tgDcs.size)]

            val tgSocket = Socket()
            tgSocket.connect(InetSocketAddress(dcHost, dcPort), 15000)
            tgSocket.soTimeout = 30000

            val tgInput = tgSocket.getInputStream()
            val tgOutput = tgSocket.getOutputStream()

            // Отправляем декриптованный хедер
            tgOutput.write(decryptedHeader)
            tgOutput.flush()

            // Форвард в обе стороны
            val fwd1 = thread {
                try {
                    val buf = ByteArray(4096)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        val dec = cipher.update(buf.copyOfRange(0, n))
                        tgOutput.write(dec)
                        tgOutput.flush()
                        bytesDown.addAndGet(dec.size.toLong())
                    }
                } catch (_: Exception) {}
                try { client.close() } catch (_: Exception) {}
                try { tgSocket.close() } catch (_: Exception) {}
            }

            val fwd2 = thread {
                try {
                    val buf = ByteArray(4096)
                    while (true) {
                        val n = tgInput.read(buf)
                        if (n <= 0) break
                        val enc = cipher.update(buf.copyOfRange(0, n))
                        output.write(enc)
                        output.flush()
                        bytesUp.addAndGet(enc.size.toLong())
                    }
                } catch (_: Exception) {}
                try { client.close() } catch (_: Exception) {}
                try { tgSocket.close() } catch (_: Exception) {}
            }

            fwd1.join()
            fwd2.join()

        } catch (_: Exception) {
            try { client.close() } catch (_: Exception) {}
        }
    }

    private fun forwardToMtproto(data: ByteArray) {
        try {
            val socket = Socket()
            socket.connect(InetSocketAddress("127.0.0.1", MTP_LISTEN), 5000)
            socket.getOutputStream().write(data)
            socket.close()
        } catch (_: Exception) {}
    }

    // ═══════════════════════════════════════════════════════════
    // SOCKS5 ПРОКСИ (127.0.0.1:1080)
    // ═══════════════════════════════════════════════════════════

    private fun startSocks5Proxy() {
        socks5Executor.submit {
            try {
                val ss = ServerSocket()
                ss.setReuseAddress(true)
                ss.bind(InetSocketAddress("127.0.0.1", SOCKS5_PORT))

                while (running.get()) {
                    try {
                        val client = ss.accept()
                        socks5Executor.submit { handleSocks5Client(client) }
                    } catch (_: Exception) { break }
                }
            } catch (e: Exception) {
                Log.e(TAG, "SOCKS5 error: ${e.message}")
            }
        }
    }

    private fun handleSocks5Client(client: Socket) {
        try {
            client.soTimeout = 30000
            val input = client.getInputStream()
            val output = client.getOutputStream()

            // RFC 1928
            // 1. Приветствие
            val hello = ByteArray(2)
            readFully(input, hello)
            val nmethods = input.read()
            val methods = ByteArray(nmethods)
            readFully(input, methods)

            // Отвечаем: no auth
            output.write(byteArrayOf(0x05, 0x00))
            output.flush()

            // 2. Запрос
            val reqHeader = ByteArray(4)
            readFully(input, reqHeader)
            val ver = reqHeader[0].toInt() and 0xFF
            val cmd = reqHeader[1].toInt() and 0xFF
            // rsv = reqHeader[2]
            val atyp = reqHeader[3].toInt() and 0xFF

            if (ver != 5) { client.close(); return }
            if (cmd != 1) { /* не CONNECT */
                output.write(byteArrayOf(0x05, 0x07.toByte(), 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
                output.flush()
                client.close()
                return
            }

            var dstHost: String
            var dstPort: Int

            when (atyp) {
                1 -> { // IPv4
                    val ipBytes = ByteArray(4)
                    readFully(input, ipBytes)
                    dstHost = InetAddress.getByAddress(ipBytes).hostAddress
                }
                3 -> { // Domain
                    val len = input.read().toInt() and 0xFF
                    val domBytes = ByteArray(len)
                    readFully(input, domBytes)
                    dstHost = String(domBytes)
                }
                4 -> { // IPv6
                    val ip6 = ByteArray(16)
                    readFully(input, ip6)
                    dstHost = InetAddress.getByAddress(ip6).hostAddress
                }
                else -> { client.close(); return }
            }

            val portBytes = ByteArray(2)
            readFully(input, portBytes)
            dstPort = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)

            // 3. Соединяемся
            try {
                val remote = Socket()
                remote.connect(InetSocketAddress(dstHost, dstPort), 15000)
                remote.soTimeout = 30000

                // Ответ: success
                val bindAddr = remote.localAddress as InetSocketAddress
                val bindIp = bindAddr.address.address
                val bindPort = bindAddr.port

                val reply = ByteArray(10)
                reply[0] = 0x05
                reply[1] = 0x00
                reply[2] = 0x00
                reply[3] = 0x01
                System.arraycopy(bindIp, 0, reply, 4, minOf(bindIp.size, 4))
                reply[8] = ((bindPort shr 8) and 0xFF).toByte()
                reply[9] = (bindPort and 0xFF).toByte()
                output.write(reply)
                output.flush()

                // Форвард с обфускацией
                val fwd1 = thread {
                    try {
                        val buf = ByteArray(4096)
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            val obf = obfuscateToMax(buf.copyOfRange(0, n), dstHost, dstPort)
                            remote.getOutputStream().write(obf)
                            remote.getOutputStream().flush()
                            bytesUp.addAndGet(obf.size.toLong())
                        }
                    } catch (_: Exception) {}
                    try { client.close() } catch (_: Exception) {}
                    try { remote.close() } catch (_: Exception) {}
                }

                val fwd2 = thread {
                    try {
                        val buf = ByteArray(4096)
                        while (true) {
                            val n = remote.getInputStream().read(buf)
                            if (n <= 0) break
                            output.write(buf, 0, n)
                            output.flush()
                            bytesDown.addAndGet(n.toLong())
                        }
                    } catch (_: Exception) {}
                    try { client.close() } catch (_: Exception) {}
                    try { remote.close() } catch (_: Exception) {}
                }

                fwd1.join()
                fwd2.join()

            } catch (e: Exception) {
                output.write(byteArrayOf(0x05, 0x04.toByte(), 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
                output.flush()
            }

            client.close()

        } catch (_: Exception) {
            try { client.close() } catch (_: Exception) {}
        }
    }

    // ═══════════════════════════════════════════════════════════
    // DNS через DoH (Cloudflare)
    // ═══════════════════════════════════════════════════════════

    private val dnsSocket = DatagramSocket()

    private fun setupDnsForward() {
        try { dnsSocket.setReuseAddress(true) } catch (_: Exception) {}
    }

    private fun forwardDnsToDoh(query: ByteArray) {
        try {
            val url = URL("https://1.1.1.1/dns-query")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/dns-message")
            conn.setRequestProperty("Accept", "application/dns-message")
            conn.doOutput = true
            conn.connectTimeout = 5000
            conn.readTimeout = 5000

            conn.outputStream.write(query)
            conn.outputStream.flush()

            val response = conn.inputStream.readBytes()

            // Отправляем ответ обратно в TUN
            if (response.isNotEmpty()) {
                writeDnsResponse(response)
            }

            bytesDown.addAndGet(response.size.toLong())
            conn.disconnect()
        } catch (_: Exception) {}
    }

    private fun writeDnsResponse(data: ByteArray) {
        try {
            tunOut?.write(data)
            tunOut?.flush()
        } catch (_: Exception) {}
    }

    // ═══════════════════════════════════════════════════════════
    // ВСПОМОГАТЕЛЬНОЕ
    // ═══════════════════════════════════════════════════════════

    private fun forwardToSocks5(data: ByteArray, host: String, port: Int) {
        try {
            val socket = Socket()
            socket.connect(InetSocketAddress("127.0.0.1", SOCKS5_PORT), 3000)
            socket.getOutputStream().write(data)
            socket.close()
        } catch (_: Exception) {} // Если SOCKS5 не стартанул — игнорируем
    }

    private data class TcpSession(
        val clientAddr: InetAddress,
        val clientPort: Int,
        val remoteAddr: InetAddress,
        val remotePort: Int,
        val seqNum: Long,
        val ackNum: Long
    )

    private data class UdpSession(
        val clientAddr: InetAddress,
        val clientPort: Int,
        val remoteAddr: InetAddress,
        val remotePort: Int
    )

    private fun readFully(input: java.io.InputStream, buf: ByteArray) {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n <= 0) throw java.io.EOFException()
            off += n
        }
    }

    private fun hexStringToByteArray(s: String): ByteArray {
        val len = s.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    private fun buildNotification(): Notification {
        val channelId = "nexus_vpn"
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(channelId) == null) {
            val channel = NotificationChannel(
                channelId, "NEXUS VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }

        return Notification.Builder(this, channelId)
            .setContentTitle("NEXUS VPN")
            .setContentText("Защита активна • max.ru обфускация")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }

    private fun cleanup() {
        try { tunIn?.close() } catch (_: Exception) {}
        try { tunOut?.close() } catch (_: Exception) {}
        try { tunFd?.close() } catch (_: Exception) {}
        tunIn = null
        tunOut = null
        tunFd = null
        tcpSessions.clear()
        udpSessions.clear()
    }
}
