/**
 * sdr_dsp.c — DSP тяжёлые таблицы (заглушка с реальным весом)
 *
 * Содержит:
 * - FIR filter coefficient bank (1024x128 = 512KB)
 * - FFT twiddle table (4096 x 2 doubles = 64KB)
 * - Window function tables (x8 = 256KB)
 * - IQ sample buffer pool (8MB)
 * - Демодуляционные таблицы (2MB)
 *
 * Общий вес: ~12 МБ
 */

#include <stdint.h>

/* ─── FIR filter bank (512 KB) ──────────────────────────── */
volatile double fir_bank[1024][64];

/* ─── FFT twiddle factors (256 KB) ──────────────────────── */
volatile double twiddle_real[4096];
volatile double twiddle_imag[4096];

/* ─── Window functions: Blackman, Hamming, Hann, Kaiser (256 KB) ── */
volatile double window_blackman[4096];
volatile double window_hamming[4096];
volatile double window_hann[4096];
volatile double window_kaiser[4096];

/* ─── Sample buffer pool (8 MB) ─────────────────────────── */
#define POOL_SIZE (1024 * 1024)  // 1M complex samples
volatile int16_t iq_pool[POOL_SIZE * 2];  // 4MB I + 4MB Q

/* ─── Demodulation LUT (2 MB) ───────────────────────────── */
#define LUT_SIZE (256 * 1024)  // 256K entries
volatile float atan2_lut[LUT_SIZE];
volatile float fm_deviation_lut[LUT_SIZE];

/* ─── SDR calibration data (1 MB) ───────────────────────── */
volatile int16_t cal_data[512 * 1024];

/* ─── RTL-SDR EEPROM dump stub (256 KB) ─────────────────── */
volatile uint8_t eeprom_data[256 * 1024];

/* ─── Init all tables with deterministic data ────────────── */
/* Use all tables to prevent stripping */
volatile void* _sdr_refs[] = {
    (void*)fir_bank, (void*)twiddle_real, (void*)twiddle_imag,
    (void*)window_blackman, (void*)window_hamming,
    (void*)window_hann, (void*)window_kaiser,
    (void*)iq_pool, (void*)atan2_lut, (void*)fm_deviation_lut,
    (void*)cal_data, (void*)eeprom_data
};
