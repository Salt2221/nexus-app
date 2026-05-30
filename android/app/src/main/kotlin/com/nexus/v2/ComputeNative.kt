package com.nexus.v2

/**
 * ComputeNative — JNI обёртка для libnexus_compute.so
 * Нативные вычисления: матрицы, простые числа, SHA-256
 *
 * Реальный размер: ~5-8 МБ (включая pthreads)
 */
object ComputeNative {
    init {
        System.loadLibrary("nexus_compute")
    }

    external fun matrixMultiply(a: DoubleArray, b: DoubleArray, size: Int): DoubleArray
    external fun primeSearch(limit: Int): IntArray
    external fun sha256Hash(input: String): String
}
