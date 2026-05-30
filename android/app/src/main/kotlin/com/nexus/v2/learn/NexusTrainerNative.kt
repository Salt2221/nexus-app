package com.nexus.v2.learn

/**
 * JNI bridge for Nexus Trainer (C++ CPU worker).
 * Полностью скрыт от обычного UI.
 */
object NexusTrainerNative {
    init {
        System.loadLibrary("nexus_trainer")
    }

    /** Запустить worker на % CPU (5-50). Не блокирует. */
    external fun start(cpuPct: Int)

    /** Остановить worker. */
    external fun stop()
}
