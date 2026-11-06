set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
add_design {rtl/ALU.v}
add_design {rtl/BPU.v}
add_design {rtl/JFIX_BPU_PAIR.sv}
add_design {rtl/CPU_top.sv}
add_design {rtl/CLMUL_UNIT.sv}
add_design {rtl/CSR.v}
add_design {rtl/DCACHE.v}
add_design {rtl/DECODER.v}
add_design {rtl/DIV_UNIT.v}
add_design {rtl/ICACHE_PAIR.sv}
add_design {rtl/JFIX_FETCH_PAIR.sv}
add_design {rtl/JFIX_OOO_CORE.sv}
add_design {rtl/JFIX_OOO_DECODE.sv}
add_design {rtl/JFIX_SERIAL_EXEC.sv}
add_design {rtl/MMIO_PERIPH.v}
add_design {rtl/MUL_UNIT.v}
add_design {rtl/PDS_DATA_MEM.v}
add_design {rtl/PDS_INST_MEM.v}
add_design {rtl/TRAP_DECODE.v}
add_design {rtl/UART_RX_ASYNC_FIFO.v}
add_design {rtl/counter_pds.v}
add_design {rtl/pango_cpu_board_top.v}
add_design {rtl/pds_twin_controller.v}
add_design {rtl/uart.sv}
add_design {ipcore/PANGO_REF_PLL/PANGO_REF_PLL.v}
add_design {ipcore/PANGO_CPU_PLL/PANGO_CPU_PLL.v}
add_design {rtl/R2_PMU.sv}
add_design {rtl/R2_ILA.sv}
add_constraint {Pango_Cpu_board.fdc}
compile -top_module pango_cpu_board_top -system_verilog
synthesize -ads -selected_syn_tool_opt 2


