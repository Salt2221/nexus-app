.section .rodata, "a"
.globl compute_data_start
.globl compute_data_end
.align 4
compute_data_start:
.incbin "nexus_compute/compute_data.bin"
compute_data_end:
