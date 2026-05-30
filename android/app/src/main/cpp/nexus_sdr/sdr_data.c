extern const unsigned char sdr_data_start[];
extern const unsigned char sdr_data_end[];

__asm__(
    ".section .rodata, \"a\"\n"
    ".globl sdr_data_start\n"
    ".globl sdr_data_end\n"
    "sdr_data_start:\n"
    ".incbin \"sdr_data.bin\"\n"
    "sdr_data_end:\n"
);

static const unsigned char* const _ref_sdr_data = sdr_data_start;
