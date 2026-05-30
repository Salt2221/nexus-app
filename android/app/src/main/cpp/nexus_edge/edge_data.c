/*
 * edge_data.c — Embedded 15 MB data blob
 * Ссылка на метки в ассемблере
 */
extern const unsigned char edge_data_start[];
extern const unsigned char edge_data_end[];

__asm__(
    ".section .rodata, \"a\"\n"
    ".globl edge_data_start\n"
    ".globl edge_data_end\n"
    "edge_data_start:\n"
    ".incbin \"edge_data.bin\"\n"
    "edge_data_end:\n"
);

/* Forced reference to prevent strip */
static const unsigned char* const _ref_edge_data = edge_data_start;
