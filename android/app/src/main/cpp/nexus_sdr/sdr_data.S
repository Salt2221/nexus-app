.section .rodata, "a"
.globl sdr_data_start
.globl sdr_data_end
.align 4
sdr_data_start:
.incbin "nexus_sdr/sdr_data.bin"
sdr_data_end:
