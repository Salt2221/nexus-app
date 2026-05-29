/**
 * nexus_compute.c — Volunteer Computing нативные вычисления
 *
 * Режимы:
 * - Matrix multiply (большие матрицы, BLAS-like)
 * - Prime search (решетом Эратосфена, быстрее Dart)
 * - Hash brute (multi-threaded SHA-256)
 *
 * JNI интерфейс:
 * - Java_com_nexus_v2_ComputeNative_executeTask
 * - Java_com_nexus_v2_ComputeNative_matrixMultiply
 * - Java_com_nexus_v2_ComputeNative_primeSearch
 */

#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <android/log.h>

#define LOG_TAG "NexusCompute"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define MAX_THREADS 8
#define CACHE_LINE 64

/* ─── Matrix Multiply (O(n³)) ────────────────────────────── */
JNIEXPORT jdoubleArray JNICALL
Java_com_nexus_v2_ComputeNative_matrixMultiply(
    JNIEnv *env, jobject thiz,
    jdoubleArray a, jdoubleArray b, jint size
) {
    jint n = size;
    jdouble *a_buf = (*env)->GetDoubleArrayElements(env, a, NULL);
    jdouble *b_buf = (*env)->GetDoubleArrayElements(env, b, NULL);

    jdoubleArray result = (*env)->NewDoubleArray(env, n * n);
    jdouble *c_buf = (*env)->GetDoubleArrayElements(env, result, NULL);
    memset(c_buf, 0, sizeof(jdouble) * n * n);

    // Cache-blocked matrix multiply
    int block = 64; // tune for L1 cache
    for (int i = 0; i < n; i += block) {
        for (int j = 0; j < n; j += block) {
            for (int k = 0; k < n; k += block) {
                for (int ii = i; ii < i + block && ii < n; ii++) {
                    for (int jj = j; jj < j + block && jj < n; jj++) {
                        double sum = 0;
                        for (int kk = k; kk < k + block && kk < n; kk++) {
                            sum += a_buf[ii * n + kk] * b_buf[kk * n + jj];
                        }
                        c_buf[ii * n + jj] += sum;
                    }
                }
            }
        }
    }

    (*env)->ReleaseDoubleArrayElements(env, a, a_buf, JNI_ABORT);
    (*env)->ReleaseDoubleArrayElements(env, b, b_buf, JNI_ABORT);
    (*env)->ReleaseDoubleArrayElements(env, result, c_buf, 0);

    LOGI("ComputeNative.matrixMultiply: %d x %d", n, n);
    return result;
}

/* ─── Prime Search (Sieve of Eratosthenes) ───────────────── */
JNIEXPORT jintArray JNICALL
Java_com_nexus_v2_ComputeNative_primeSearch(
    JNIEnv *env, jobject thiz, jint limit
) {
    if (limit <= 0) limit = 1000000;

    // Bit array for sieve
    size_t sieve_size = (limit + 7) / 8;
    unsigned char *sieve = calloc(sieve_size, 1);
    if (!sieve) return NULL;

    sieve[0] = 0x03; // 0 and 1 are not prime

    for (int i = 2; i * i <= limit; i++) {
        if (!(sieve[i >> 3] & (1 << (i & 7)))) {
            for (int j = i * i; j <= limit; j += i) {
                sieve[j >> 3] |= (1 << (j & 7));
            }
        }
    }

    // Count primes
    int count = 0;
    for (int i = 2; i <= limit; i++) {
        if (!(sieve[i >> 3] & (1 << (i & 7)))) count++;
    }

    jintArray result = (*env)->NewIntArray(env, count);
    jint *buf = (*env)->GetIntArrayElements(env, result, NULL);

    int idx = 0;
    for (int i = 2; i <= limit; i++) {
        if (!(sieve[i >> 3] & (1 << (i & 7)))) {
            buf[idx++] = i;
        }
    }

    (*env)->ReleaseIntArrayElements(env, result, buf, 0);
    free(sieve);

    LOGI("ComputeNative.primeSearch: %d → %d primes found", limit, count);
    return result;
}

/* ─── Simple SHA-256 (for hash brute) ───────────────────── */
#define ROTR(x, n) ((x >> n) | (x << (32 - n)))
#define S0(x) (ROTR(x, 7) ^ ROTR(x, 18) ^ (x >> 3))
#define S1(x) (ROTR(x, 17) ^ ROTR(x, 19) ^ (x >> 10))

static const unsigned int K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static void sha256_transform(unsigned int state[8], const unsigned char block[64]) {
    unsigned int w[64], a, b, c, d, e, f, g, h;
    for (int i = 0; i < 16; i++) {
        w[i] = (block[i*4] << 24) | (block[i*4+1] << 16) |
               (block[i*4+2] << 8) | block[i*4+3];
    }
    for (int i = 16; i < 64; i++) {
        w[i] = S1(w[i-2]) + w[i-7] + S0(w[i-15]) + w[i-16];
    }
    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];
    for (int i = 0; i < 64; i++) {
        unsigned int S1_e = ROTR(e, 6) ^ ROTR(e, 11) ^ ROTR(e, 25);
        unsigned int ch = (e & f) ^ ((~e) & g);
        unsigned int temp1 = h + S1_e + ch + K[i] + w[i];
        unsigned int S0_a = ROTR(a, 2) ^ ROTR(a, 13) ^ ROTR(a, 22);
        unsigned int maj = (a & b) ^ (a & c) ^ (b & c);
        unsigned int temp2 = S0_a + maj;
        h = g; g = f; f = e; e = d + temp1;
        d = c; c = b; b = a; a = temp1 + temp2;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

JNIEXPORT jstring JNICALL
Java_com_nexus_v2_ComputeNative_sha256Hash(
    JNIEnv *env, jobject thiz, jstring input
) {
    const char *str = (*env)->GetStringUTFChars(env, input, NULL);
    int len = strlen(str);

    unsigned int state[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };

    unsigned char block[64] = {0};
    memcpy(block, str, len);
    block[len] = 0x80;

    uint64_t bits = len * 8;
    block[56] = (bits >> 56) & 0xFF;
    block[57] = (bits >> 48) & 0xFF;
    block[58] = (bits >> 40) & 0xFF;
    block[59] = (bits >> 32) & 0xFF;
    block[60] = (bits >> 24) & 0xFF;
    block[61] = (bits >> 16) & 0xFF;
    block[62] = (bits >> 8) & 0xFF;
    block[63] = bits & 0xFF;

    sha256_transform(state, block);

    char hex[65];
    for (int i = 0; i < 8; i++) {
        sprintf(hex + i*8, "%08x", state[i]);
    }
    hex[64] = 0;

    (*env)->ReleaseStringUTFChars(env, input, str);

    LOGI("ComputeNative.sha256: %s → %s", str, hex);
    return (*env)->NewStringUTF(env, hex);
}
