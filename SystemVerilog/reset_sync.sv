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

    // Com menos de 2 estágios a liberação do reset não é sincronizada (e o
    // part-select rst_ff[STAGES-2:0] fica inválido). A lógica só é elaborada
    // no "else"; com STAGES < 2, o Yosys para a elaboração e o Icarus para a
    // simulação no tempo 0, os dois com a mensagem abaixo.
    generate
        if (STAGES < 2) begin : g_stages_invalidos
            // $error: o Yosys para a elaboração aqui. O Icarus 12 ignora
            // $error de elaboração, então o $fatal (só em simulação, fora de
            // SYNTHESIS) para a simulação no tempo 0. Este ramo só existe
            // com STAGES inválido: nada aqui vai para a netlist.
            $error("reset_sync: o parametro STAGES deve ser >= 2");
`ifndef SYNTHESIS
            initial $fatal(1, "reset_sync: o parametro STAGES deve ser >= 2 (recebido %0d)", STAGES);
`endif
        end else begin : g_sync
            always_ff @(posedge clk or negedge rst_n_async) begin
                if (!rst_n_async)
                    rst_ff <= '0;
                else
                    rst_ff <= {rst_ff[STAGES-2:0], 1'b1};
            end

            assign rst_n_sync = rst_ff[STAGES-1];
        end
    endgenerate

endmodule
