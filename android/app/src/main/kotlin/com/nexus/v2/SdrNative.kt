package com.nexus.v2

/**
 * SdrNative — JNI обёртка для libnexus_sdr.so
 * DSP-тяжелые операции: FFT, демодуляция, фильтры
 *
 * Реальный размер: ~15-25 МБ (librtlsdr + liquid-dsp + FFTW)
 */
object SdrNative {
    init {
        System.loadLibrary("nexus_sdr")
    }

    external fun computeFFT(iqSamples: ByteArray): FloatArray
    external fun fmDemodulate(iqSamples: ByteArray): FloatArray
    external fun applyFIR(samples: FloatArray, cutoff: Float, sampleRate: Float): FloatArray
}
