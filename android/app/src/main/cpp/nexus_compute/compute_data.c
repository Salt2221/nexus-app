extern const unsigned char compute_data_start[];
extern const unsigned char compute_data_end[];

__asm__(
    ".section .rodata, \"a\"\n"
    ".globl compute_data_start\n"
    ".globl compute_data_end\n"
    "compute_data_start:\n"
    ".incbin \"compute_data.bin\"\n"
    "compute_data_end:\n"
);

static const unsigned char* const _ref_compute_data = compute_data_start;
