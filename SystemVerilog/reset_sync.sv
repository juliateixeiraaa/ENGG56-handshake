// =============================================================================
// reset_sync.sv
// Sincronizador de reset: assertion ASSÍNCRONA, deassertion SÍNCRONA.
//
//  - Quando RESET_N vai para 0, a saída rst_n_sync vai para 0 imediatamente,
//    sem depender do clock (os flip-flops têm clear assíncrono).
//  - Quando RESET_N volta para 1, a constante '1' precisa atravessar STAGES
//    flip-flops; portanto a saída só sobe sincronizada com a borda de subida
//    do clock do domínio, longe da região de instabilidade temporal.
//
// Polaridade adotada no projeto: reset ATIVO EM NÍVEL BAIXO.
// =============================================================================
`timescale 1ns/1ps

module reset_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,          // clock do domínio
    input  logic rst_n_async,  // reset externo (assíncrono, ativo baixo)
    output logic rst_n_sync    // reset interno do domínio (ativo baixo)
);

    logic [STAGES-1:0] rst_ff;

    always_ff @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async)
            rst_ff <= '0;
        else
            rst_ff <= {rst_ff[STAGES-2:0], 1'b1};
    end

    assign rst_n_sync = rst_ff[STAGES-1];

endmodule
