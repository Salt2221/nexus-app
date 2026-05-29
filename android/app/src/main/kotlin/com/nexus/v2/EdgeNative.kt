package com.nexus.v2

/**
 * EdgeNative — JNI обёртка для libnexus_edge.so
 * Zero-Knowledge крипто-операции через нативный код
 *
 * Реальный размер библиотеки с libsodium: ~8-12 МБ
 */
object EdgeNative {
    init {
        System.loadLibrary("nexus_edge")
    }

    external fun encrypt(data: ByteArray, key: ByteArray, iv: ByteArray): ByteArray
    external fun decrypt(ciphertext: ByteArray, key: ByteArray, iv: ByteArray): ByteArray
    external fun hashContent(data: ByteArray): String
}
