# =============================================================================
# io_constraints.tcl — posicionamento dos pinos no floorplan
#
# Sem nomes de camadas metálicas, para funcionar em qualquer plataforma:
#   esquerda : domínio A (CLK_A, DATA_IN, IN_VALID, IN_READY)
#   direita  : domínio B (CLK_B, DATA_OUT, OUT_*, RX_DONE)
#   inferior : RESET_N (compartilhado)
# =============================================================================

set_io_pin_constraint -region left:* -pin_names {
    CLK_A IN_VALID IN_READY
    DATA_IN[0]  DATA_IN[1]  DATA_IN[2]  DATA_IN[3]
    DATA_IN[4]  DATA_IN[5]  DATA_IN[6]  DATA_IN[7]
    DATA_IN[8]  DATA_IN[9]  DATA_IN[10] DATA_IN[11]
    DATA_IN[12] DATA_IN[13] DATA_IN[14] DATA_IN[15]
}

set_io_pin_constraint -region right:* -pin_names {
    CLK_B OUT_READY OUT_VALID OUT_DONE RX_DONE
    DATA_OUT[0]  DATA_OUT[1]  DATA_OUT[2]  DATA_OUT[3]
    DATA_OUT[4]  DATA_OUT[5]  DATA_OUT[6]  DATA_OUT[7]
    DATA_OUT[8]  DATA_OUT[9]  DATA_OUT[10] DATA_OUT[11]
    DATA_OUT[12] DATA_OUT[13] DATA_OUT[14] DATA_OUT[15]
}

set_io_pin_constraint -region bottom:* -pin_names {RESET_N}
