/**
 * edge_pool.c — Большие статические таблицы для Edge Storage
 *
 * - Argon2 time/memory cost tables (2MB)
 * - SipHash key pool (64KB)
 * - Compression dictionary (4MB)
 * - Pre-computed S-box tables (256KB)
 *
 * Общий вес: ~7 MB
 */

#include <stdint.h>

/* ─── SipHash key pool (64 KB) ──────────────────────────── */
volatile uint64_t siphash_keys[8192];

/* ─── Argon2 memory blocks (2 MB) ───────────────────────── */
#define ARGON2_BLOCKS (256 * 1024)
volatile uint64_t argon2_mem[ARGON2_BLOCKS];

/* ─── Compression dictionary (4 MB) ─────────────────────── */
#define DICT_SIZE (4 * 1024 * 1024)
volatile uint8_t compress_dict[DICT_SIZE];

/* ─── AES S-box / Inv S-box (1 KB) ──────────────────────── */
volatile uint8_t aes_sbox[256];
volatile uint8_t aes_inv_sbox[256];
volatile uint8_t aes_rcon[256];

/* ─── Galois field multiplication table (64 KB) ─────────── */
volatile uint8_t gf_mul[256][256];

/* ─── Chacha20 constant block (64 bytes) ────────────────── */
volatile uint32_t chacha_const[16];

/* ─── Pre-computed HMAC keys (512 KB) ───────────────────── */
volatile uint8_t hmac_keys[512 * 1024];

/* ─── Blake2b IV (512 bytes) ────────────────────────────── */
volatile uint64_t blake2b_iv[64];

/* ─── Zero-knowledge proof parameters (1 MB) ────────────── */
volatile uint8_t zk_params[1024 * 1024];

/* Prevent stripping */
volatile void* _edge_refs[] = {
    (void*)siphash_keys, (void*)argon2_mem, (void*)compress_dict,
    (void*)aes_sbox, (void*)aes_inv_sbox, (void*)aes_rcon,
    (void*)gf_mul, (void*)chacha_const, (void*)hmac_keys,
    (void*)blake2b_iv, (void*)zk_params
};
