/**
 * nexus_sdr.c — SDR нативные операции
 *
 * Два слоя:
 * 1. RTL-SDR драйвер (через USB bulk transfer)
 * 2. DSP pipeline (FIR, FFT, AM/FM демодуляция)
 *
 * В реальном APK здесь librtlsdr + liquid-dsp.
 * Пока — заглушка с тем же API и тяжёлой FFT.
 */

#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <android/log.h>

#define LOG_TAG "NexusSDR"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define FFT_SIZE 1024
#define SAMPLE_RATE 2400000  // 2.4 MSPS

/* ─── Complex FFT (radix-2, in-place) ───────────────────── */
typedef struct {
    float re;
    float im;
} complex_t;

static void fft(complex_t *buf, int n) {
    // Bit-reversal permutation
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            complex_t t = buf[i]; buf[i] = buf[j]; buf[j] = t;
        }
    }

    for (int len = 2; len <= n; len <<= 1) {
        float ang = -2.0f * M_PI / len;
        complex_t wlen = {cosf(ang), sinf(ang)};
        for (int i = 0; i < n; i += len) {
            complex_t w = {1.0f, 0.0f};
            for (int j = 0; j < len / 2; j++) {
                complex_t u = buf[i + j];
                complex_t v = {
                    buf[i + j + len / 2].re * w.re - buf[i + j + len / 2].im * w.im,
                    buf[i + j + len / 2].re * w.im + buf[i + j + len / 2].im * w.re
                };
                buf[i + j] = (complex_t){u.re + v.re, u.im + v.im};
                buf[i + j + len / 2] = (complex_t){u.re - v.re, u.im - v.im};
                complex_t w_new = {
                    w.re * wlen.re - w.im * wlen.im,
                    w.re * wlen.im + w.im * wlen.re
                };
                w = w_new;
            }
        }
    }
}

/* ─── FIR Low-pass filter (windowed sinc) ────────────────── */
#define FIR_TAPS 128

static float fir_coeffs[FIR_TAPS];
static int fir_initialized = 0;

static void init_fir(float cutoff, float sample_rate) {
    float fc = cutoff / sample_rate;
    for (int i = 0; i < FIR_TAPS; i++) {
        int m = i - FIR_TAPS / 2;
        if (m == 0) {
            fir_coeffs[i] = 2.0f * fc;
        } else {
            fir_coeffs[i] = sinf(2.0f * M_PI * fc * m) / (M_PI * m);
        }
        // Blackman-Harris window
        float window = 0.35875f - 0.48829f * cosf(2.0f * M_PI * i / FIR_TAPS)
                     + 0.14128f * cosf(4.0f * M_PI * i / FIR_TAPS)
                     - 0.01168f * cosf(6.0f * M_PI * i / FIR_TAPS);
        fir_coeffs[i] *= window;
    }
    fir_initialized = 1;
    LOGI("SDR FIR: initialized %d taps, fc=%.2f/%.1f", FIR_TAPS, cutoff, sample_rate);
}

/* ─── JNI: Compute FFT from IQ samples ──────────────────── */
JNIEXPORT jfloatArray JNICALL
Java_com_nexus_v2_SdrNative_computeFFT(
    JNIEnv *env, jobject thiz,
    jbyteArray iq_samples
) {
    jsize len = (*env)->GetArrayLength(env, iq_samples);
    jbyte *buf = (*env)->GetByteArrayElements(env, iq_samples, NULL);

    int n = len / 2; // I + Q
    if (n > FFT_SIZE) n = FFT_SIZE;

    // Window function (Blackman-Harris)
    complex_t fft_buf[FFT_SIZE] = {0};
    for (int i = 0; i < n; i++) {
        float window = 0.35875f - 0.48829f * cosf(2.0f * M_PI * i / FFT_SIZE)
                     + 0.14128f * cosf(4.0f * M_PI * i / FFT_SIZE)
                     - 0.01168f * cosf(6.0f * M_PI * i / FFT_SIZE);
        fft_buf[i].re = buf[i * 2] * window;
        fft_buf[i].im = buf[i * 2 + 1] * window;
    }

    fft(fft_buf, FFT_SIZE);

    // Power spectrum (dB)
    jfloatArray result = (*env)->NewFloatArray(env, FFT_SIZE / 2);
    jfloat *spec = (*env)->GetFloatArrayElements(env, result, NULL);

    for (int i = 0; i < FFT_SIZE / 2; i++) {
        float mag = sqrtf(fft_buf[i].re * fft_buf[i].re + fft_buf[i].im * fft_buf[i].im);
        spec[i] = 20.0f * log10f(mag + 1e-10f);
    }

    (*env)->ReleaseByteArrayElements(env, iq_samples, buf, JNI_ABORT);
    (*env)->ReleaseFloatArrayElements(env, result, spec, 0);

    LOGI("SDRNative.computeFFT: %d IQ → %d FFT bins", len, FFT_SIZE / 2);
    return result;
}

/* ─── JNI: FM Demodulator ───────────────────────────────── */
JNIEXPORT jfloatArray JNICALL
Java_com_nexus_v2_SdrNative_fmDemodulate(
    JNIEnv *env, jobject thiz,
    jbyteArray iq_samples
) {
    jsize len = (*env)->GetArrayLength(env, iq_samples);
    jbyte *buf = (*env)->GetByteArrayElements(env, iq_samples, NULL);

    int n = len / 2;
    jfloatArray result = (*env)->NewFloatArray(env, n);
    jfloat *audio = (*env)->GetFloatArrayElements(env, result, NULL);

    // FM demod: atan2(Q, I) — phase difference
    float prev_phase = 0;
    for (int i = 1; i < n; i++) {
        float re = buf[i * 2];
        float im = buf[i * 2 + 1];
        float prev_re = buf[(i - 1) * 2];
        float prev_im = buf[(i - 1) * 2 + 1];

        float phase = atan2f(im, re);
        float diff = phase - prev_phase;
        if (diff > M_PI) diff -= 2.0f * M_PI;
        if (diff < -M_PI) diff += 2.0f * M_PI;
        audio[i - 1] = diff;
        prev_phase = phase;
    }

    (*env)->ReleaseByteArrayElements(env, iq_samples, buf, JNI_ABORT);
    (*env)->ReleaseFloatArrayElements(env, result, audio, 0);

    LOGI("SDRNative.fmDemodulate: %d samples", n);
    return result;
}

/* ─── JNI: Apply FIR filter ──────────────────────────────── */
JNIEXPORT jfloatArray JNICALL
Java_com_nexus_v2_SdrNative_applyFIR(
    JNIEnv *env, jobject thiz,
    jfloatArray samples, jfloat cutoff, jfloat sample_rate
) {
    if (!fir_initialized) init_fir(cutoff, sample_rate);

    jsize len = (*env)->GetArrayLength(env, samples);
    jfloat *buf = (*env)->GetFloatArrayElements(env, samples, NULL);

    jfloatArray result = (*env)->NewFloatArray(env, len);
    jfloat *out = (*env)->GetFloatArrayElements(env, result, NULL);

    for (int i = 0; i < len; i++) {
        float sum = 0;
        for (int j = 0; j < FIR_TAPS && j <= i; j++) {
            sum += fir_coeffs[j] * buf[i - j];
        }
        out[i] = sum;
    }

    (*env)->ReleaseFloatArrayElements(env, samples, buf, JNI_ABORT);
    (*env)->ReleaseFloatArrayElements(env, result, out, 0);

    LOGI("SDRNative.applyFIR: %d samples filtered", len);
    return result;
}
