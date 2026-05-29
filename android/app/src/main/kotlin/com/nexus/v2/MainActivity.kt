// ═══════════════════════════════════════════════════════════════
// NEXUS MainActivity — точка входа для Flutter
//
//  MethodChannel: com.nexus.v2/vpn
//    - start / stop / status
// ═══════════════════════════════════════════════════════════════

package com.nexus.v2

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.nexus.v2/vpn"
        private const val VPN_REQUEST_CODE = 100
    }

    private var methodChannel: MethodChannel? = null
    private var statusTimer: Timer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val preIntent = android.net.VpnService.prepare(this@MainActivity)
                    if (preIntent != null) {
                        startActivityForResult(preIntent, VPN_REQUEST_CODE)
                    } else {
                        startVpnService()
                    }
                    result.success("starting")
                }
                "stop" -> {
                    stopVpnService()
                    result.success("stopped")
                }
                "status" -> {
                    result.success(mapOf(
                        "running" to NexusVpnService.isRunning(),
                        "bytesUp" to 0,
                        "bytesDown" to 0,
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                startVpnService()
                methodChannel?.invokeMethod("onStatus", mapOf("status" to "connected"))
            } else {
                methodChannel?.invokeMethod("onStatus", mapOf("status" to "rejected"))
            }
        }
    }

    private fun startVpnService() {
        val intent = Intent(this, NexusVpnService::class.java).apply { action = NexusVpnService.ACTION_START }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopVpnService() {
        val intent = Intent(this, NexusVpnService::class.java).apply { action = NexusVpnService.ACTION_STOP }
        startService(intent)
    }
}
