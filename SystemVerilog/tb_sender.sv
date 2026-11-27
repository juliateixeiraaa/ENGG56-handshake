// =============================================================================
// tb_sender.sv  —  Testbench unitário do Sender
//
// O DUT é só o sender.sv. O lado do Receiver é um modelo comportamental no
// domínio CLK_B: sincroniza REQ com 2 flip-flops, espera um número aleatório
// de ciclos, amostra tx_data e ativa ACK; depois espera REQ cair e desativa
// ACK (também com atraso aleatório). Assim o Sender é exercitado com ACKs
// rápidos, lentos e em qualquer fase em relação a CLK_A.
//
// Cenários:
//   S1  Reset inicial: valores de reset e IN_READY após a liberação
//   S2  Fluxo sem esperas (CLK_A rápido, CLK_B lento) + IN_VALID extra
//       ignorado depois das 16 palavras; Sender fica em DONE até o reset
//   S3  Reset assíncrono no meio do handshake e recomeço do zero
//   S4  Esperas aleatórias no IN_VALID e no ACK (CLK_A lento, CLK_B rápido)
//   S5  Clocks quase iguais (10,0 / 10,1 ns) com ACK lento
//
// Verificações automáticas (monitores sempre ligados):
//   - IN_READY = 0 em reset e depois da 16a palavra; nenhuma captura extra
//   - REQ não sobe antes da 16a palavra capturada
//   - 4 fases do handshake: REQ sobe com ACK = 0, cai só depois do ACK,
//     e não sobe de novo antes de ACK cair
//   - tx_data estável enquanto REQ ou ACK estiverem ativos
//   - tx_data muda pelo menos 1 ciclo de CLK_A antes de REQ subir
//   - as 16 palavras chegam ao modelo do Receiver na ordem certa
//   - depois do 16o handshake, REQ fica em 0 e o Sender fica em S_DONE
// =============================================================================
`timescale 1ns/1ps

module tb_sender;

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
    // O reset do Sender no topo vem de um reset_sync (liberação síncrona a
    // CLK_A). Aqui o testbench solta rst_n logo depois de uma borda de
    // subida de CLK_A, que é o que o reset_sync garante.
    logic         rst_n    = 1'b1;
    logic [W-1:0] data_in  = '0;
    logic         in_valid = 1'b0;
    logic         in_ready;
    logic         req;
    logic         ack      = 1'b0;
    logic [W-1:0] tx_data;

    sender #(.WIDTH(W), .DEPTH(N)) dut (
        .clk      (CLK_A),
        .rst_n    (rst_n),
        .data_in  (data_in),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .req      (req),
        .ack      (ack),
        .tx_data  (tx_data)
    );

    // ------------------------------------------------------------------
    // Estado do testbench
    // ------------------------------------------------------------------
    logic [W-1:0] words [0:N-1];
    int errors   = 0;
    int in_count = 0;      // palavras capturadas pelo Sender
    int rx_count = 0;      // palavras recebidas pelo modelo do Receiver
    int hs_count = 0;      // handshakes completos (descidas de ACK)
    string test_name = "";

    // Faixas de atraso do modelo do Receiver (ciclos de CLK_B)
    int ack_rise_max = 0;
    int ack_fall_max = 0;

    task automatic fail(input string msg);
        errors++;
        $display("[%0t] ERRO (%s): %s", $time, test_name, msg);
    endtask

    // ------------------------------------------------------------------
    // Modelo do Receiver (domínio CLK_B)
    // ------------------------------------------------------------------
    logic [1:0] req_sync = '0;
    wire        req_s    = req_sync[1];

    always @(posedge CLK_B or negedge rst_n)
        if (!rst_n) req_sync <= '0;
        else        req_sync <= {req_sync[0], req};

    initial begin
        forever begin
            @(posedge CLK_B);
            if (!rst_n) begin
                ack <= 1'b0;
            end else if (req_s && !ack) begin
                repeat ($urandom_range(ack_rise_max, 0)) @(posedge CLK_B);
                if (rst_n && req_s) begin
                    // amostra o barramento (bundled-data) e responde
                    if (rx_count >= N)
                        fail($sformatf("palavra extra recebida: %h", tx_data));
                    else if (tx_data !== words[rx_count])
                        fail($sformatf("palavra %0d: esperado %h, recebido %h",
                                       rx_count, words[rx_count], tx_data));
                    else
                        $display("[%0t] (%s) palavra %2d OK: %h",
                                 $time, test_name, rx_count, tx_data);
                    rx_count++;
                    ack <= 1'b1;
                end
            end else if (!req_s && ack) begin
                repeat ($urandom_range(ack_fall_max, 0)) @(posedge CLK_B);
                if (rst_n) begin
                    ack <= 1'b0;
                    hs_count++;
                end
            end
        end
    end

    // Reset assíncrono: o modelo solta ACK na hora, como o Receiver real
    always @(negedge rst_n) ack <= 1'b0;

    // ------------------------------------------------------------------
    // Monitores — interface de entrada (CLK_A)
    // ------------------------------------------------------------------
    always @(posedge CLK_A) begin
        // Checa antes de contar: na borda da 16a captura, IN_READY ainda é 1
        if (rst_n && in_ready && in_count >= N)
            fail("IN_READY ativo depois da 16a palavra");
        if (rst_n && in_valid && in_ready) begin
            if (in_count >= N)
                fail($sformatf("palavra extra capturada na entrada: %h", data_in));
            else if (data_in !== words[in_count])
                fail($sformatf("entrada %0d: esperado %h, aplicado %h",
                               in_count, words[in_count], data_in));
            in_count++;
        end
    end

    // IN_READY = 0 logo após o reset ativar é checado em check_reset_values;
    // aqui, garante que ele não sobe enquanto o reset estiver ativo.
    always @(posedge in_ready)
        if (!rst_n) fail("IN_READY subiu durante o reset");

    // ------------------------------------------------------------------
    // Monitores — handshake de 4 fases e bundled-data
    // ------------------------------------------------------------------
    realtime t_tx_change = 0;
    realtime t_pos_a     = 0;
    realtime period_a    = 4.0;

    always @(posedge CLK_A) begin
        if (t_pos_a > 0) period_a = $realtime - t_pos_a;
        t_pos_a = $realtime;
    end

    always @(tx_data) begin
        t_tx_change = $realtime;
        if (rst_n && (req || ack)) fail("tx_data mudou durante o handshake");
    end

    always @(posedge req) begin
        if (ack)           fail("REQ subiu com ACK ainda ativo");
        if (in_count < N)  fail($sformatf("REQ subiu com só %0d palavras capturadas", in_count));
        if (hs_count >= N) fail("REQ subiu depois do 16o handshake");
        // tx_data foi carregado em S_LOAD, 1 ciclo de CLK_A antes de S_REQ
        if ($realtime - t_tx_change < period_a - 0.001)
            fail($sformatf("tx_data mudou só %0.3f ns antes de REQ subir",
                           $realtime - t_tx_change));
    end

    always @(negedge req) if (rst_n && !ack) fail("REQ caiu antes do ACK");
    always @(posedge ack) if (!req)          fail("ACK subiu sem REQ");

    // ------------------------------------------------------------------
    // Tarefas auxiliares
    // ------------------------------------------------------------------
    task automatic new_test(input string name);
        test_name = name;
        in_count  = 0;
        rx_count  = 0;
        hs_count  = 0;
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
        if (in_ready !== 1'b0) fail("IN_READY deveria ser 0 em reset");
        if (req      !== 1'b0) fail("REQ deveria ser 0 em reset");
        if (tx_data  !== '0)   fail("tx_data deveria ser 0 em reset");
        if (dut.state !== dut.S_CAPTURE) fail("estado deveria ser S_CAPTURE em reset");
    endtask

    // Ativa o reset, confere os valores e solta logo após uma borda de CLK_A
    task automatic apply_reset(input real hold_ns);
        rst_n    = 1'b0;
        in_valid = 1'b0;
        #0.01;
        check_reset_values();
        #(hold_ns);
        @(posedge CLK_A);
        #0.1;
        rst_n = 1'b1;
        @(posedge CLK_A);
        #0.1;
        if (in_ready !== 1'b1) fail("IN_READY deveria estar ativo após o reset");
        if (req      !== 1'b0) fail("REQ deveria continuar 0 após o reset");
    endtask

    // Fonte externa: envia as N palavras; max_gap = ciclos ociosos máximos
    task automatic drive_inputs(input int max_gap);
        for (int i = 0; i < N; i++) begin
            in_valid <= 1'b0;
            data_in  <= 16'hxxxx;
            repeat ($urandom_range(max_gap, 0)) @(posedge CLK_A);
            in_valid <= 1'b1;
            data_in  <= words[i];
            @(posedge CLK_A);
            while (!in_ready) @(posedge CLK_A);
        end
        in_valid <= 1'b0;
        data_in  <= '0;
    endtask

    // Espera o fim da transferência e confere o estado final
    task automatic wait_done;
        wait (hs_count == N);
        repeat (6) @(posedge CLK_A);
        if (dut.state !== dut.S_DONE) fail("Sender não chegou a S_DONE");
        if (req      !== 1'b0)        fail("REQ ativo depois do 16o handshake");
        if (in_ready !== 1'b0)        fail("IN_READY ativo em S_DONE");
    endtask

    task automatic check_counts;
        if (in_count != N) fail($sformatf("%0d palavras capturadas (esperado %0d)", in_count, N));
        if (rx_count != N) fail($sformatf("%0d palavras recebidas (esperado %0d)", rx_count, N));
        if (hs_count != N) fail($sformatf("%0d handshakes (esperado %0d)", hs_count, N));
    endtask

    // ------------------------------------------------------------------
    // Sequência de testes
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_sender.vcd");
        $dumpvars(0, tb_sender);

        // ---------------- S1 ----------------
        new_test("S1 reset inicial");
        gen_words(0);
        #0.5;
        apply_reset(23.4);

        // ---------------- S2 ----------------
        new_test("S2 fluxo sem esperas");
        ack_rise_max = 0;
        ack_fall_max = 0;
        fork
            drive_inputs(0);
            wait_done();
        join
        // IN_VALID continua ativo depois das 16 palavras: nada é capturado
        in_valid <= 1'b1;
        data_in  <= 16'hDEAD;
        repeat (20) @(posedge CLK_A);
        in_valid <= 1'b0;
        if (dut.state !== dut.S_DONE) fail("Sender saiu de S_DONE sem reset");
        if (req !== 1'b0)             fail("REQ ativo em S_DONE");
        check_counts();

        // ---------------- S3 ----------------
        new_test("S3 reset no meio do handshake");
        gen_words(1);
        ack_rise_max = 3;
        ack_fall_max = 3;
        apply_reset(17.0);
        drive_inputs(0);
        wait (rx_count == 6 && req === 1'b1);  // REQ ativo, ACK já subindo
        #3.141;
        rst_n = 1'b0;
        #0.01;
        check_reset_values();
        #40;
        // Recomeça do zero: as 16 palavras de novo, na ordem
        new_test("S3 recomeço após o reset");
        gen_words(2);
        @(posedge CLK_A);
        #0.1;
        rst_n = 1'b1;
        @(posedge CLK_A);
        #0.1;
        if (in_ready !== 1'b1) fail("IN_READY deveria estar ativo após o reset");
        fork
            drive_inputs(1);
            wait_done();
        join
        check_counts();

        // ---------------- S4 ----------------
        new_test("S4 esperas aleatorias (CLK_A lento, CLK_B rapido)");
        half_a = 11.65;  // CLK_A = 23.3 ns
        half_b = 3.5;    // CLK_B =  7.0 ns
        ack_rise_max = 8;
        ack_fall_max = 8;
        gen_words(2);
        apply_reset(29.0);
        fork
            drive_inputs(4);
            wait_done();
        join
        check_counts();

        // ---------------- S5 ----------------
        new_test("S5 clocks quase iguais (CLK_A = 10,0 ns, CLK_B = 10,1 ns), ACK lento");
        half_a = 5.0;    // CLK_A = 10.0 ns
        half_b = 5.05;   // CLK_B = 10.1 ns
        ack_rise_max = 12;
        ack_fall_max = 12;
        gen_words(2);
        apply_reset(27.0);
        fork
            drive_inputs(2);
            wait_done();
        join
        check_counts();

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
