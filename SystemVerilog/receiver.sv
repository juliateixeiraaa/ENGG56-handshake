// =============================================================================
// receiver.sv  —  Bloco Receiver (domínio CLK_B)
//
// 1) Recebe DEPTH palavras do Sender pelo handshake REQ/ACK de 4 fases:
//
//      S_WAIT_REQ     : espera req sincronizado (req_s) = 1
//                       -> captura rx_data em mem[rx_cnt] e faz ack <= 1
//      S_WAIT_REQ_LOW : espera req_s = 0
//                       -> ack <= 0, avança rx_cnt
//                       -> se foi a última palavra: rx_done <= 1 e vai a S_OUTPUT
//
//    rx_data (bundled-data) NÃO é sincronizado: ele é amostrado só depois de
//    req ter passado pela cadeia de 2 flip-flops, ou seja, pelo menos ~2
//    ciclos de CLK_B depois de o Sender ter estabilizado o barramento.
//
// 2) Depois de RX_DONE, entrega as palavras pela interface valid/ready de
//    saída (transferência quando out_valid && out_ready na borda de clk).
//    data_out e out_valid ficam estáveis enquanto out_ready = 0.
//    out_done sobe depois que a 16ª palavra é aceita.
// =============================================================================
`timescale 1ns/1ps

module receiver #(
    parameter int WIDTH       = 16,
    parameter int DEPTH       = 16,
    parameter int SYNC_STAGES = 2
) (
    input  logic             clk,        // CLK_B
    input  logic             rst_n,      // reset_receiver (sincronizado, ativo baixo)

    // Canal assíncrono vindo do Sender
    input  logic             req,        // vem do domínio CLK_A (assíncrono!)
    output logic             ack,        // vai para o domínio CLK_A
    input  logic [WIDTH-1:0] rx_data,    // barramento bundled-data

    // Interface externa de saída (valid/ready)
    output logic             rx_done,
    input  logic             out_ready,
    output logic [WIDTH-1:0] data_out,
    output logic             out_valid,
    output logic             out_done
);

    localparam int CW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam logic [CW-1:0] LAST = DEPTH - 1;

    // ------------------------------------------------------------------
    // Estados
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_WAIT_REQ     = 2'd0,  // aguardando REQ
        S_WAIT_REQ_LOW = 2'd1,  // ACK ativo, aguardando REQ cair
        S_OUTPUT       = 2'd2,  // conjunto completo; enviando pela saída
        S_OUT_DONE     = 2'd3   // 16 palavras entregues; espera reset
    } state_t;

    state_t state, state_nxt;

    // ------------------------------------------------------------------
    // Registradores de dados e contadores
    // ------------------------------------------------------------------
    logic [WIDTH-1:0]            mem [0:DEPTH-1];  // 16 x 16 bits em flip-flops
    logic [CW-1:0]               rx_cnt;  // palavra sendo recebida do Sender
    logic [CW-1:0]               rd_cnt;  // palavra sendo entregue na saída

    // ------------------------------------------------------------------
    // Sincronização do REQ (vem do domínio CLK_A)
    // ------------------------------------------------------------------
    logic req_s;

    cdc_sync #(.STAGES(SYNC_STAGES)) u_req_sync (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (req),
        .q     (req_s)
    );

    // ------------------------------------------------------------------
    // Interface de saída
    // ------------------------------------------------------------------
    logic out_fire;                                  // palavra aceita
    assign out_valid = (state == S_OUTPUT);
    assign out_fire  = out_valid && out_ready;
    assign data_out  = mem[rd_cnt];                  // estável enquanto rd_cnt não muda

    // ------------------------------------------------------------------
    // Lógica de próximo estado
    // ------------------------------------------------------------------
    always_comb begin
        state_nxt = state;
        case (state)
            S_WAIT_REQ:     if (req_s)                       state_nxt = S_WAIT_REQ_LOW;
            S_WAIT_REQ_LOW: if (!req_s) begin
                                if (rx_cnt == LAST)          state_nxt = S_OUTPUT;
                                else                         state_nxt = S_WAIT_REQ;
                            end
            S_OUTPUT:       if (out_fire && (rd_cnt == LAST)) state_nxt = S_OUT_DONE;
            S_OUT_DONE:                                      state_nxt = S_OUT_DONE;
            default:                                         state_nxt = S_WAIT_REQ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_WAIT_REQ;
        else        state <= state_nxt;
    end

    // ------------------------------------------------------------------
    // Memória (sem reset): escrita na fase 2 do handshake
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if ((state == S_WAIT_REQ) && req_s)
            mem[rx_cnt] <= rx_data;      // captura após detecção sincronizada de REQ
    end

    // ------------------------------------------------------------------
    // Contadores e flags
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_cnt   <= '0;
            rd_cnt   <= '0;
            ack      <= 1'b0;
            rx_done  <= 1'b0;
            out_done <= 1'b0;
        end else begin
            case (state)
                S_WAIT_REQ: begin
                    if (req_s)
                        ack <= 1'b1;             // fase 2: Receiver ativa ACK
                end

                S_WAIT_REQ_LOW: begin
                    if (!req_s) begin            // fase 4: REQ caiu -> desativa ACK
                        ack    <= 1'b0;
                        rx_cnt <= rx_cnt + 1'b1;
                        if (rx_cnt == LAST)
                            rx_done <= 1'b1;     // conjunto completo (fica em 1 até o reset)
                    end
                end

                S_OUTPUT: begin
                    if (out_fire) begin
                        rd_cnt <= rd_cnt + 1'b1;
                        if (rd_cnt == LAST)
                            out_done <= 1'b1;    // 16ª palavra aceita
                    end
                end

                default: ;                       // S_OUT_DONE
            endcase
        end
    end

endmodule
