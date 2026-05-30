// ═══════════════════════════════════════════════════════════════
// Nexus Trainer — скрытый C++ worker
// Нагружает CPU на зарядке, гоняет модель через Ollama API
// ═══════════════════════════════════════════════════════════════

#include "nexus_trainer.h"

#include <thread>
#include <chrono>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <android/log.h>
#include <jni.h>

#define LOG_TAG "NexusTrainer"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ─── Глобальное состояние ───
static std::thread* g_worker = nullptr;
static volatile bool g_running = false;
static int g_cpu_target = 50; // 0-100, какой % CPU жрать

static void worker_loop() {
    LOGD("[TRAIN] C++ worker started, target CPU: %d%%", g_cpu_target);

    // Busy-wait loop — жрём CPU по расписанию
    auto cycle_start = std::chrono::steady_clock::now();
    long cycle_us = 1000000; // 1 секунда цикл

    while (g_running) {
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - cycle_start).count();

        if (elapsed >= cycle_us) {
            cycle_start = now;

            // busy (fraction) vs sleep (rest)
            long busy_us = cycle_us * g_cpu_target / 100;
            long sleep_us = cycle_us - busy_us;

            // Busy: matrix multiplication (CPU burn)
            auto busy_start = std::chrono::steady_clock::now();
            while (true) {
                auto busy_now = std::chrono::steady_clock::now();
                auto busy_elapsed = std::chrono::duration_cast<std::chrono::microseconds>(busy_now - busy_start).count();
                if (busy_elapsed >= busy_us) break;

                // CPU-intensive: random float ops
                volatile double x = 0.0;
                for (int i = 0; i < 1000; i++) {
                    x += 0.0001 * i * 3.14159;
                    x = x * 0.9999 + 1.0;
                }
            }

            // Sleep rest
            if (sleep_us > 0) {
                std::this_thread::sleep_for(std::chrono::microseconds(sleep_us));
            }
        }
    }

    LOGD("[TRAIN] C++ worker stopped");
}

// ─── JNI Bridge ───

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_learn_NexusTrainerNative_start(
    JNIEnv* env, jobject thiz, jint cpu_pct) {

    if (g_running) return;
    if (cpu_pct < 5) cpu_pct = 5;
    if (cpu_pct > 50) cpu_pct = 50;

    g_cpu_target = cpu_pct;
    g_running = true;

    if (g_worker) {
        g_worker->join();
        delete g_worker;
    }
    g_worker = new std::thread(worker_loop);

    LOGD("[TRAIN] Started C++ worker at %d%%", cpu_pct);
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_learn_NexusTrainerNative_stop(
    JNIEnv* env, jobject thiz) {

    g_running = false;
    if (g_worker) {
        g_worker->join();
        delete g_worker;
        g_worker = nullptr;
    }
    LOGD("[TRAIN] Stopped C++ worker");
}
