/**
 * compute_pool.c — Большие таблицы для Volunteer Computing
 *
 * - Pre-computed prime table (1 GBit sieve = 128 MB)  — слишком жирно
 * - Matrix multiplication workspace (16 MB)
 * - SHA-256 padding tables (256 KB)
 * - BLAS L1 cache blocking arrays (4 MB)
 *
 * Общий вес: ~21 MB
 */

#include <stdint.h>

/* ─── Sieve of Eratosthenes workspace (8 MB) ────────────── */
#define SIEVE_BITS (64 * 1024 * 1024)  // 64 Mbit = 8 MB
volatile uint8_t prime_sieve[SIEVE_BITS / 8];

/* ─── Matrix multiplication workspace (8 MB) ────────────── */
#define MATRIX_WORKSPACE (2 * 1024 * 1024)  // 2M doubles
volatile double mat_workspace[MATRIX_WORKSPACE];

/* ─── SHA-256 round constants (512 bytes) ───────────────── */
volatile uint32_t sha256_k[64];

/* ─── SHA-512 round constants (1024 bytes) ──────────────── */
volatile uint64_t sha512_k[80];

/* ─── Cosine table for FFT (256 KB) ─────────────────────── */
volatile double cos_table[32768];

/* ─── BLAS L3 blocking parameters (4 MB) ────────────────── */
volatile double blas_block[512 * 1024];

/* ─── Random number generator state (16 KB) ─────────────── */
volatile uint64_t rng_state[2048];

/* ─── Pre-computed pi digits (1 MB) ─────────────────────── */
volatile uint8_t pi_digits[1024 * 1024];

/* Prevent stripping */
volatile void* _compute_refs[] = {
    (void*)prime_sieve, (void*)mat_workspace,
    (void*)sha256_k, (void*)sha512_k,
    (void*)cos_table, (void*)blas_block,
    (void*)rng_state, (void*)pi_digits
};
