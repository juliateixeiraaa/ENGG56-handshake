// =============================================================================
// handshake_top.sv  —  Módulo de topo
// ENGG56 2026.2 — Sistema de comunicação com handshake assíncrono (UFBA)
//
//            CLK_A domain                         CLK_B domain
//   +--------------------------+         +-----------------------------+
//   |          sender          |  req -->|[2FF]      receiver           |
//   | DATA_IN/IN_VALID/IN_READY|  tx_data======>   (bundled-data)       |
//   |                          |[2FF]<-- ack                            |
//   +--------------------------+         | RX_DONE / DATA_OUT / ...    |
//        ^ reset_sender_n                +-----------------------------+
//        |                                     ^ reset_receiver_n
//   [reset_sync A] <---- RESET_N ----> [reset_sync B]
//
// Reset: RESET_N, ATIVO EM NÍVEL BAIXO. Assertion assíncrona, deassertion
// síncrona e independente em cada domínio.
// =============================================================================
`timescale 1ns/1ps

module handshake_top #(
    parameter int WIDTH       = 16,   // largura da palavra
    parameter int DEPTH       = 16,   // número de palavras do bloco
    parameter int SYNC_STAGES = 2     // flip-flops dos sincronizadores
) (
    // Clocks e reset
    input  logic             CLK_A,
    input  logic             CLK_B,
    input  logic             RESET_N,

    // Interface de captura (domínio CLK_A)
    input  logic [WIDTH-1:0] DATA_IN,
    input  logic             IN_VALID,
    output logic             IN_READY,

    // Interface de saída (domínio CLK_B)
    output logic             RX_DONE,
    input  logic             OUT_READY,
    output logic [WIDTH-1:0] DATA_OUT,
    output logic             OUT_VALID,
    output logic             OUT_DONE
);

    // ------------------------------------------------------------------
    // Resets internos sincronizados (reset_sender / reset_receiver)
    // ------------------------------------------------------------------
    logic reset_sender_n;
    logic reset_receiver_n;

    reset_sync #(.STAGES(SYNC_STAGES)) u_rst_sync_a (
        .clk         (CLK_A),
        .rst_n_async (RESET_N),
        .rst_n_sync  (reset_sender_n)
    );

    reset_sync #(.STAGES(SYNC_STAGES)) u_rst_sync_b (
        .clk         (CLK_B),
        .rst_n_async (RESET_N),
        .rst_n_sync  (reset_receiver_n)
    );

    // ------------------------------------------------------------------
    // Canal interno entre os domínios
    // ------------------------------------------------------------------
    logic             req;      // CLK_A -> CLK_B (sincronizado no Receiver)
    logic             ack;      // CLK_B -> CLK_A (sincronizado no Sender)
    logic [WIDTH-1:0] tx_data;  // CLK_A -> CLK_B (bundled-data, sem sincronizador)

    sender #(
        .WIDTH       (WIDTH),
        .DEPTH       (DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_sender (
        .clk      (CLK_A),
        .rst_n    (reset_sender_n),
        .data_in  (DATA_IN),
        .in_valid (IN_VALID),
        .in_ready (IN_READY),
        .req      (req),
        .ack      (ack),
        .tx_data  (tx_data)
    );

    receiver #(
        .WIDTH       (WIDTH),
        .DEPTH       (DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_receiver (
        .clk       (CLK_B),
        .rst_n     (reset_receiver_n),
        .req       (req),
        .ack       (ack),
        .rx_data   (tx_data),
        .rx_done   (RX_DONE),
        .out_ready (OUT_READY),
        .data_out  (DATA_OUT),
        .out_valid (OUT_VALID),
        .out_done  (OUT_DONE)
    );

endmodule
