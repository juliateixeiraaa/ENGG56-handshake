// =============================================================================
// tb_receiver.sv  —  Testbench unitário do Receiver
//
// O DUT é só o receiver.sv. O lado do Sender é um modelo comportamental no
// domínio CLK_A: sincroniza ACK com 2 flip-flops e faz o handshake de 4 fases
// com bundled-data (coloca a palavra em tx_data, sobe REQ 1 ciclo depois,
// espera ACK, desce REQ, espera ACK cair). Fora da janela do handshake o
// modelo deixa lixo aleatório no barramento, para garantir que o Receiver só
// amostra tx_data quando o protocolo permite. Os atrasos do modelo e o
// OUT_READY do circuito externo são aleatórios.
//
// Cenários:
//   R1  Reset inicial: valores de reset e estado após a liberação
//   R2  Fluxo sem esperas com OUT_READY = 1 desde o início; depois de
//       OUT_DONE, um REQ extra é ignorado e o Receiver fica em S_FIM
//   R3  Reset assíncrono no meio do 6º handshake e recomeço do zero
//   R4  Reset assíncrono durante a leitura (após RX_DONE) e recomeço
//   R5  Esperas aleatórias no Sender e no OUT_READY (CLK_A lento, CLK_B rápido)
//   R6  Clocks quase iguais (10,0 / 10,1 ns) com OUT_READY raro
//
// Verificações automáticas (monitores sempre ligados):
//   - ACK só sobe com REQ ativo, depois do sincronizador (>= 2 ciclos de
//     CLK_B após REQ), e só cai depois de REQ cair; no máximo 16 ACKs
//   - RX_DONE só depois do 16º handshake e ativo até o reset
//   - OUT_VALID nunca antes de RX_DONE e sobe na mesma borda que ele
//   - DATA_OUT/OUT_VALID estáveis enquanto OUT_VALID = 1 e OUT_READY = 0
//   - as 16 palavras saem na ordem e com o conteúdo certo
//   - OUT_DONE só depois da 16ª palavra aceita; com OUT_DONE, OUT_VALID = 0
//   - ao final: estado S_FIM e as 16 posições de mem corretas
// =============================================================================
`timescale 1ns/1ps

module tb_receiver;

    localparam int W = 16;
    localparam int N = 16;

    // ------------------------------------------------------------------
    // Clocks independentes (mesmos pares do tb_handshake_top)
    // ------------------------------------------------------------------
    real half_a = 2.0;     // CLK_A = 4.0 ns
    real half_b = 2.85;    // CLK_B = 5.7 ns

    logic CLK_A = 1'b0;
    logic CLK_B = 1'b0;

    initial begin #1.3; forever #(half_a) CLK_A = ~CLK_A; end
    initial begin #3.7; forever #(half_b) CLK_B = ~CLK_B; end

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    // O reset do Receiver no topo vem de um reset_sync (liberação síncrona a
    // CLK_B). Aqui o testbench solta rst_n logo depois de uma borda de
    // subida de CLK_B, que é o que o reset_sync garante.
    logic         rst_n     = 1'b1;
    logic         req       = 1'b0;
    logic         ack;
    logic [W-1:0] tx_data   = '0;
    logic         rx_done;
    logic         out_ready = 1'b0;
    logic [W-1:0] data_out;
    logic         out_valid;
    logic         out_done;

    receiver #(.WIDTH(W), .DEPTH(N)) dut (
        .clk       (CLK_B),
        .rst_n     (rst_n),
        .req       (req),
        .ack       (ack),
        .rx_data   (tx_data),
        .rx_done   (rx_done),
        .out_ready (out_ready),
        .data_out  (data_out),
        .out_valid (out_valid),
        .out_done  (out_done)
    );

    // ------------------------------------------------------------------
    // Estado do testbench
    // ------------------------------------------------------------------
    logic [W-1:0] words [0:N-1];
    int errors    = 0;
    int rx_count  = 0;     // subidas de ACK (palavras aceitas pelo Receiver)
    int hs_count  = 0;     // handshakes completos (descidas de ACK)
    int out_count = 0;     // palavras entregues na saída
    string test_name = "";

    int req_gap_max = 0;   // atraso máximo do modelo do Sender (ciclos de CLK_A)
    bit send_en     = 1'b0;
    int tx_idx      = 0;   // próxima palavra que o modelo do Sender envia
    int rst_gen     = 0;   // incrementa a cada reset (aborta o handshake em curso)

    task automatic fail(input string msg);
        errors++;
        $display("[%0t] ERRO (%s): %s", $time, test_name, msg);
    endtask

    // ------------------------------------------------------------------
    // Modelo do Sender (domínio CLK_A)
    // ------------------------------------------------------------------
    logic [1:0] ack_sync = '0;
    wire        ack_s    = ack_sync[1];

    always @(posedge CLK_A or negedge rst_n)
        if (!rst_n) ack_sync <= '0;
        else        ack_sync <= {ack_sync[0], ack};

    // Cada handshake roda no bloco "hs"; um reset no meio (rst_gen muda)
    // encerra o bloco com disable e o modelo recomeça da 1ª palavra.
    initial begin : sender_model
        int g;
        forever begin
            @(posedge CLK_A);
            if (rst_n && send_en && tx_idx < N) begin : hs
                g = rst_gen;
                repeat ($urandom_range(req_gap_max, 0)) @(posedge CLK_A);
                if (g != rst_gen || !rst_n) disable hs;
                tx_data <= words[tx_idx];           // dado estável ANTES de REQ
                @(posedge CLK_A);
                if (g != rst_gen || !rst_n) disable hs;
                req <= 1'b1;                        // fase 1
                do @(posedge CLK_A); while (g == rst_gen && rst_n && !ack_s);
                if (g != rst_gen || !rst_n) disable hs;
                repeat ($urandom_range(req_gap_max, 0)) @(posedge CLK_A);
                if (g != rst_gen || !rst_n) disable hs;
                req <= 1'b0;                        // fase 3
                do @(posedge CLK_A); while (g == rst_gen && rst_n && ack_s);
                if (g != rst_gen || !rst_n) disable hs;
                tx_data <= $urandom;                // lixo fora da janela (req = ack = 0)
                tx_idx++;
            end
        end
    end

    // Reset assíncrono: o modelo solta REQ e volta para a 1ª palavra
    always @(negedge rst_n) begin
        rst_gen++;
        req     <= 1'b0;
        tx_data <= $urandom;
        tx_idx   = 0;
    end

    // ------------------------------------------------------------------
    // Monitores — handshake de 4 fases (lado do Receiver)
    // ------------------------------------------------------------------
    realtime t_req_rise = 0;
    realtime t_pos_b    = 0;
    realtime period_b   = 5.7;

    always @(posedge CLK_B) begin
        if (t_pos_b > 0) period_b = $realtime - t_pos_b;
        t_pos_b = $realtime;
    end

    always @(posedge req) t_req_rise = $realtime;

    always @(posedge ack) begin
        if (!req)           fail("ACK subiu sem REQ");
        if (rx_count >= N)  fail("ACK extra depois da 16a palavra");
        // REQ passa por 2 FFs antes de a FSM ver req_s: pelo menos 2 ciclos
        if ($realtime - t_req_rise < 2.0 * period_b - 0.001)
            fail($sformatf("ACK subiu só %0.3f ns depois de REQ (sem sincronizador?)",
                           $realtime - t_req_rise));
        rx_count++;
    end

    always @(negedge ack) begin
        if (rst_n) begin
            if (req) fail("ACK caiu com REQ ainda ativo");
            hs_count++;
        end
    end

    // ------------------------------------------------------------------
    // Monitores — interface de saída (CLK_B)
    // ------------------------------------------------------------------
    logic         prev_valid  = 1'b0;
    logic         prev_ready  = 1'b0;
    logic [W-1:0] prev_data   = '0;
    logic         prev_rxdone = 1'b0;

    always @(posedge CLK_B) begin
        if (!rst_n) begin
            prev_valid  <= 1'b0;
            prev_ready  <= 1'b0;
            prev_rxdone <= 1'b0;
        end else begin
            if (out_valid && out_ready) begin
                if (out_count >= N)
                    fail("palavra extra entregue na saída");
                else if (data_out !== words[out_count])
                    fail($sformatf("saída %0d: esperado %h, recebido %h",
                                   out_count, words[out_count], data_out));
                else
                    $display("[%0t] (%s) saída %2d OK: %h", $time, test_name, out_count, data_out);
                out_count++;
            end

            if (prev_valid && !prev_ready) begin
                if (!out_valid)            fail("OUT_VALID caiu sem a palavra ter sido aceita");
                if (data_out !== prev_data) fail("DATA_OUT mudou enquanto OUT_READY estava inativo");
            end

            if (out_valid && !rx_done)         fail("OUT_VALID ativo antes de RX_DONE");
            if (rx_done && !prev_rxdone && !out_valid)
                                               fail("OUT_VALID não subiu junto com RX_DONE");
            if (rx_done && hs_count < N)       fail($sformatf("RX_DONE ativo com só %0d handshakes", hs_count));
            if (prev_rxdone && !rx_done)       fail("RX_DONE caiu sem reset");
            if (out_done && out_count < N)     fail("OUT_DONE ativo antes da 16a palavra");
            if (out_done && out_valid)         fail("OUT_VALID ativo junto com OUT_DONE");

            prev_valid  <= out_valid;
            prev_ready  <= out_ready;
            prev_data   <= data_out;
            prev_rxdone <= rx_done;
        end
    end

    // ------------------------------------------------------------------
    // Tarefas auxiliares
    // ------------------------------------------------------------------
    task automatic new_test(input string name);
        test_name = name;
        rx_count  = 0;
        hs_count  = 0;
        out_count = 0;
        $display("\n==== %s ====", name);
    endtask

    task automatic gen_words(input int mode);
        for (int i = 0; i < N; i++)
            case (mode)
                0:       words[i] = 16'hA500 + i;
                1:       words[i] = 16'h1 << i;
                default: words[i] = $urandom;
            endcase
    endtask

    task automatic check_reset_values;
        if (ack       !== 1'b0) fail("ACK deveria ser 0 em reset");
        if (rx_done   !== 1'b0) fail("RX_DONE deveria ser 0 em reset");
        if (out_valid !== 1'b0) fail("OUT_VALID deveria ser 0 em reset");
        if (out_done  !== 1'b0) fail("OUT_DONE deveria ser 0 em reset");
        if (dut.state !== dut.S_WAIT_REQ) fail("estado deveria ser S_WAIT_REQ em reset");
    endtask

    // Solta o reset logo após uma borda de CLK_B (como o reset_sync)
    task automatic release_reset;
        @(posedge CLK_B);
        #0.1;
        rst_n = 1'b1;
        @(posedge CLK_B);
        #0.1;
        check_reset_values();   // continua em WAIT_REQ, sem REQ
    endtask

    // Ativa o reset (fora das bordas), confere os valores e solta
    task automatic apply_reset(input real hold_ns);
        rst_n     = 1'b0;
        send_en   = 1'b0;
        out_ready = 1'b0;
        #0.01;
        check_reset_values();
        #(hold_ns);
        release_reset();
    endtask

    // Circuito externo: OUT_READY ativo com probabilidade ready_pct (%).
    // Para sozinho quando as N palavras saem ou quando o reset é ativado.
    task automatic consume_outputs(input int ready_pct);
        while (out_count < N && rst_n) begin
            out_ready <= ($urandom_range(99, 0) < ready_pct);
            @(posedge CLK_B);
        end
        out_ready <= 1'b0;
    endtask

    // Espera OUT_DONE e confere o estado final
    task automatic wait_done;
        wait (out_done === 1'b1);
        repeat (6) @(posedge CLK_B);
        if (dut.state !== dut.S_FIM) fail("Receiver não chegou a S_FIM");
        if (rx_done   !== 1'b1)      fail("RX_DONE deveria continuar ativo em S_FIM");
        if (out_valid !== 1'b0)      fail("OUT_VALID ativo em S_FIM");
        if (ack       !== 1'b0)      fail("ACK ativo em S_FIM");
        for (int i = 0; i < N; i++)
            if (dut.mem[i] !== words[i])
                fail($sformatf("mem[%0d]: esperado %h, gravado %h", i, words[i], dut.mem[i]));
    endtask

    task automatic check_counts;
        if (rx_count  != N) fail($sformatf("%0d ACKs (esperado %0d)", rx_count, N));
        if (hs_count  != N) fail($sformatf("%0d handshakes (esperado %0d)", hs_count, N));
        if (out_count != N) fail($sformatf("%0d palavras na saída (esperado %0d)", out_count, N));
    endtask

    // Transferência completa: Sender envia, circuito externo lê
    task automatic run_transfer(input int gap, input int ready_pct);
        req_gap_max = gap;
        send_en     = 1'b1;
        fork
            consume_outputs(ready_pct);
            wait_done();
        join
        send_en = 1'b0;
        check_counts();
    endtask

    // ------------------------------------------------------------------
    // Sequência de testes
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_receiver.vcd");
        $dumpvars(0, tb_receiver);

        // ---------------- R1 ----------------
        new_test("R1 reset inicial");
        gen_words(0);
        #0.5;
        apply_reset(23.4);

        // ---------------- R2 ----------------
        new_test("R2 fluxo sem esperas");
        out_ready = 1'b1;                     // pronto desde antes de RX_DONE
        run_transfer(0, 100);
        // REQ extra depois de OUT_DONE: o Receiver ignora
        out_ready <= 1'b1;
        tx_data   <= 16'hDEAD;
        @(posedge CLK_A);
        req <= 1'b1;
        repeat (20) @(posedge CLK_B);
        if (ack       !== 1'b0)      fail("ACK respondeu a um REQ depois de OUT_DONE");
        if (out_valid !== 1'b0)      fail("OUT_VALID ativo depois de OUT_DONE");
        if (dut.state !== dut.S_FIM) fail("Receiver saiu de S_FIM sem reset");
        req       <= 1'b0;
        out_ready <= 1'b0;
        repeat (4) @(posedge CLK_B);

        // ---------------- R3 ----------------
        new_test("R3 reset no meio do handshake");
        gen_words(1);
        apply_reset(17.0);
        req_gap_max = 1;
        send_en     = 1'b1;
        wait (rx_count == 6 && req === 1'b1 && ack === 1'b1);
        #3.141;                               // instante não alinhado aos clocks
        rst_n = 1'b0;
        #0.01;
        check_reset_values();
        send_en = 1'b0;
        #40;
        new_test("R3 recomeço após o reset");
        gen_words(2);
        release_reset();
        run_transfer(1, 70);

        // ---------------- R4 ----------------
        new_test("R4 reset durante a leitura");
        gen_words(2);
        apply_reset(19.0);
        req_gap_max = 0;
        send_en     = 1'b1;
        fork
            consume_outputs(60);
        join_none
        wait (out_count == 8);
        #2.718;
        rst_n = 1'b0;
        #0.01;
        check_reset_values();
        send_en = 1'b0;
        #40;                                  // consume_outputs para com o reset
        if (rx_done !== 1'b0) fail("RX_DONE ativo após reset");
        new_test("R4 recomeço após o reset");
        gen_words(2);
        release_reset();
        run_transfer(0, 60);

        // ---------------- R5 ----------------
        new_test("R5 esperas aleatorias (CLK_A lento, CLK_B rapido)");
        half_a = 11.65;  // CLK_A = 23.3 ns
        half_b = 3.5;    // CLK_B =  7.0 ns
        gen_words(2);
        apply_reset(29.0);
        run_transfer(6, 35);

        // ---------------- R6 ----------------
        new_test("R6 clocks quase iguais (CLK_A = 10,0 ns, CLK_B = 10,1 ns), OUT_READY raro");
        half_a = 5.0;    // CLK_A = 10.0 ns
        half_b = 5.05;   // CLK_B = 10.1 ns
        gen_words(2);
        apply_reset(27.0);
        run_transfer(3, 20);

        // ---------------- Resultado ----------------
        $display("\n==============================================");
        if (errors == 0) $display("  TODOS OS TESTES PASSARAM");
        else             $display("  FALHA: %0d erro(s)", errors);
        $display("==============================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        #200_000;
        $display("[%0t] ERRO: timeout da simulação", $time);
        $finish;
    end

endmodule
