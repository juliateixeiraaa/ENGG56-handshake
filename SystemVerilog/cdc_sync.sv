// =============================================================================
// cdc_sync.sv
// Sincronizador de 1 bit para cruzamento de domínio de clock (CDC).
//
// Cadeia de STAGES flip-flops (padrão: 2). O primeiro flip-flop pode entrar
// em metaestabilidade ao amostrar um sinal vindo de outro domínio; o segundo
// dá um ciclo inteiro de clock para que ele se resolva.
//
// IMPORTANTE: só deve ser usado para sinais de CONTROLE de 1 bit que vêm
// direto de um flip-flop do outro domínio (sem lógica combinacional no meio),
// como REQ e ACK. Barramentos de dados NÃO passam por aqui (ver bundled-data).
// =============================================================================
`timescale 1ns/1ps

module cdc_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,     // clock do domínio de DESTINO
    input  logic rst_n,   // reset do domínio de destino (ativo em nível baixo)
    input  logic d,       // sinal assíncrono vindo do outro domínio
    output logic q        // sinal sincronizado
);

    logic [STAGES-1:0] sync_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_ff <= '0;
        else
            sync_ff <= {sync_ff[STAGES-2:0], d};
    end

    assign q = sync_ff[STAGES-1];

endmodule
