// =============================================================================
// sender.sv  —  Bloco Sender (domínio CLK_A)
//
// 1) Captura DEPTH palavras de WIDTH bits pela interface valid/ready de
//    entrada (captura quando in_valid && in_ready na borda de clk).
// 2) Depois da última palavra, transfere uma palavra por vez para o Receiver
//    usando handshake REQ/ACK de 4 fases + bundled-data:
//
//      S_LOAD          : copia mem[tx_cnt] para o registrador tx_data
//      S_REQ           : req <= 1 (um ciclo DEPOIS de tx_data estar estável)
//                        espera ack sincronizado (ack_s) = 1
//      S_WAIT_ACK_LOW  : req <= 0; espera ack_s = 0  -> fim do handshake
//                        avança tx_cnt; volta a S_LOAD ou vai a S_DONE
//
//    tx_data só muda em S_LOAD, ou seja, com req = 0 e ack = 0. Assim o
//    barramento fica estável durante toda a janela do handshake.
//
// Todos os sinais que saem para o outro domínio (req e tx_data) vêm direto
// de flip-flops (sem lógica combinacional), evitando glitches no CDC.
// =============================================================================
`timescale 1ns/1ps

module sender #(
    parameter int WIDTH       = 16,
    parameter int DEPTH       = 16,
    parameter int SYNC_STAGES = 2
) (
    input  logic             clk,       // CLK_A
    input  logic             rst_n,     // reset_sender (sincronizado, ativo baixo)

    // Interface externa de entrada (valid/ready)
    input  logic [WIDTH-1:0] data_in,
    input  logic             in_valid,
    output logic             in_ready,

    // Canal assíncrono para o Receiver
    output logic             req,       // vai para o domínio CLK_B
    input  logic             ack,       // vem do domínio CLK_B (assíncrono!)
    output logic [WIDTH-1:0] tx_data    // barramento bundled-data
);

    localparam int CW = (DEPTH > 1) ? $clog2(DEPTH) : 1;   // largura dos contadores
    localparam logic [CW-1:0] LAST = CW'(DEPTH - 1);

    // ------------------------------------------------------------------
    // Estados
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_CAPTURE      = 3'd0,  // recebendo palavras da interface externa
        S_LOAD         = 3'd1,  // carrega a palavra a enviar em tx_data
        S_REQ          = 3'd2,  // REQ ativo, aguardando ACK
        S_WAIT_ACK_LOW = 3'd3,  // REQ desativado, aguardando ACK cair
        S_DONE         = 3'd4   // bloco enviado; espera reset
    } state_t;

    state_t state, state_nxt;

    // ------------------------------------------------------------------
    // Registradores de dados e contadores
    // ------------------------------------------------------------------
    logic [WIDTH-1:0]            mem [0:DEPTH-1];  // 16 x 16 bits em flip-flops
    logic [CW-1:0]               wr_cnt;  // quantas palavras já capturadas
    logic [CW-1:0]               tx_cnt;  // qual palavra está sendo enviada

    // ------------------------------------------------------------------
    // Sincronização do ACK (vem do domínio CLK_B)
    // ------------------------------------------------------------------
    logic ack_s;

    cdc_sync #(.STAGES(SYNC_STAGES)) u_ack_sync (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (ack),
        .q     (ack_s)
    );

    // ------------------------------------------------------------------
    // Interface de entrada
    // ------------------------------------------------------------------
    // Pronto apenas fora do reset e no estado de captura.
    assign in_ready = rst_n && (state == S_CAPTURE);

    logic capture;
    assign capture = in_valid && in_ready;

    // ------------------------------------------------------------------
    // Lógica de próximo estado (combinacional)
    // ------------------------------------------------------------------
    always_comb begin
        state_nxt = state;
        case (state)
            S_CAPTURE:      if (capture && (wr_cnt == LAST)) state_nxt = S_LOAD;
            S_LOAD:                                          state_nxt = S_REQ;
            S_REQ:          if (ack_s)                       state_nxt = S_WAIT_ACK_LOW;
            S_WAIT_ACK_LOW: if (!ack_s) begin
                                if (tx_cnt == LAST)          state_nxt = S_DONE;
                                else                         state_nxt = S_LOAD;
                            end
            S_DONE:                                          state_nxt = S_DONE;
            default:                                         state_nxt = S_CAPTURE;
        endcase
    end

    // ------------------------------------------------------------------
    // Registrador de estado
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_CAPTURE;
        else        state <= state_nxt;
    end

    // ------------------------------------------------------------------
    // Caminho de dados: memória, contadores, tx_data e req
    // ------------------------------------------------------------------
    // A memória não precisa de reset (economiza área); só é lida depois
    // de ter sido completamente escrita.
    always_ff @(posedge clk) begin
        if (capture)
            mem[wr_cnt] <= data_in;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_cnt  <= '0;
            tx_cnt  <= '0;
            tx_data <= '0;
            req     <= 1'b0;
        end else begin
            case (state)
                S_CAPTURE: begin
                    if (capture)
                        wr_cnt <= wr_cnt + 1'b1;  // 15 -> 0 ao terminar (não importa)
                end

                S_LOAD: begin
                    tx_data <= mem[tx_cnt];       // dado estável ANTES de req subir
                end

                S_REQ: begin
                    req <= 1'b1;                  // fase 1: Sender ativa REQ
                end

                S_WAIT_ACK_LOW: begin
                    req <= 1'b0;                  // fase 3: ACK visto -> desativa REQ
                    if (!ack_s)                   // fase 4 concluída (ACK caiu)
                        tx_cnt <= tx_cnt + 1'b1;
                end

                default: ;                        // S_DONE: nada muda
            endcase
        end
    end

endmodule
