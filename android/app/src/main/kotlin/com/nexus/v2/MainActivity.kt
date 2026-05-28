package com.nexus.v2

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nexus.v2/vpn"
    private val VPN_REQUEST_CODE = 9001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingResult = result
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                    } else {
                        val svcIntent = Intent(this, NexusVpnService::class.java)
                        startForegroundService(svcIntent)
                        result.success(true)
                    }
                }
                "stopVpn" -> {
                    val intent = Intent(this, NexusVpnService::class.java).apply { action = "STOP" }
                    startService(intent)
                    result.success(true)
                }
                "prepareVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingResult = result
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                    } else {
                        result.success(true)
                    }
                }
                "startMtproxy" -> {
                    val port = call.argument<Int>("port") ?: 1443
                    val intent = Intent(this, NexusVpnService::class.java).apply {
                        action = "START_MT_PROXY"
                        putExtra("port", port)
                    }
                    startService(intent)
                    // Return secret to Flutter
                    val service = NexusVpnService()
                    result.success(service.getMtproxySecret())
                }
                "stopMtproxy" -> {
                    val intent = Intent(this, NexusVpnService::class.java).apply { action = "STOP_MT_PROXY" }
                    startService(intent)
                    result.success(true)
                }
                "getMtproxyStatus" -> {
                    // Simplified: return static status
                    val map = mapOf(
                        "secret" to NexusVpnService().getMtproxySecret(),
                        "port" to 1443
                    )
                    result.success(map)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val intent = Intent(this, NexusVpnService::class.java)
                startForegroundService(intent)
                pendingResult?.success(true)
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
