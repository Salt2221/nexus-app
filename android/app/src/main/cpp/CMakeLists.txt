cmake_minimum_required(VERSION 3.18)

# Запрещаем сборку под x86/x86_64 — только arm64
# Но CMake сам разрулит по abiFilters

project("nexus_native")

# ─── NEXUSGram MTProto Native — как в exteraGram/Nekogram ──
add_library(nexus_mtproto SHARED
    dpi_engine/mtproto_native.cpp
)

# ─── DPI Engine ─────────────────────────────────────────────
add_library(nexus_dpi SHARED
    dpi_engine/packet_fragmenter.cpp
    dpi_engine/bridge_rotator.cpp
    dpi_engine/camouflage_tunnel.cpp
)

# ─── Edge Storage (libsodium) ──────────────────────────────
add_library(nexus_edge SHARED
    nexus_edge/edge_crypto.c
    edge_data_bin.c
)

# ─── Volunteer Compute ─────────────────────────────────────
add_library(nexus_compute SHARED
    nexus_compute/compute_worker.c
    compute_data_bin.c
)

# ─── SDR (RTL-SDR stub + liquid-dsp stub) ──────────────────
add_library(nexus_sdr SHARED
    nexus_sdr/sdr_rtl.c
    sdr_data_bin_0.c
    sdr_data_bin_1.c
    sdr_data_bin_2.c
    sdr_data_bin_3.c
)

# ─── Include dirs ──────────────────────────────────────────
target_include_directories(nexus_edge PRIVATE include)
target_include_directories(nexus_compute PRIVATE include)
target_include_directories(nexus_sdr PRIVATE include)

# ─── Link libraries ────────────────────────────────────────
# libsodium статически вшит в nexus_edge
# liquid-dsp статически вшит в nexus_sdr

target_link_libraries(nexus_mtproto PRIVATE log z)
target_link_libraries(nexus_dpi PRIVATE log)
target_link_libraries(nexus_edge PRIVATE log)
target_link_libraries(nexus_compute PRIVATE log)
target_link_libraries(nexus_sdr PRIVATE log)

# ─── C standard ────────────────────────────────────────────
set_target_properties(nexus_dpi PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)
set_target_properties(nexus_edge nexus_compute nexus_sdr PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
)
