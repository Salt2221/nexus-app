.section .rodata, "a"
.globl edge_data_start
.globl edge_data_end
.align 4
edge_data_start:
.incbin "nexus_edge/edge_data.bin"
edge_data_end:
