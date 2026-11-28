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
//   S3b Reset no meio da captura (7 palavras) com IN_VALID = 1 durante o
//       reset, e recomeço do zero
//   S4  Esperas aleatórias no IN_VALID e no ACK (CLK_A lento, CLK_B rápido)
//   S5  Clocks quase iguais (10,0 / 10,1 ns) com ACK lento
//
// Verificações automáticas (monitores sempre ligados):
//   - IN_READY = 0 em reset e depois da 16a palavra; nenhuma captura extra
//   - REQ não sobe antes da 16a palavra capturada
//   - 4 fases do handshake: REQ sobe com ACK = 0, cai só depois do ACK,
//     e não sobe de novo antes de ACK cair
//   - REQ cai pelo menos (SYNC_STAGES + 1) ciclos de CLK_A depois de ACK
//     subir (sincronizador do ACK presente e com o número certo de FFs)
//   - tx_data estável enquanto REQ ou ACK estiverem ativos
//   - tx_data muda pelo menos 1 ciclo de CLK_A antes de REQ subir
//   - as 16 palavras chegam ao modelo do Receiver na ordem certa
//   - depois do 16o handshake, REQ fica em 0 e o Sender fica em S_DONE
//
// Fora do alcance: metaestabilidade. A simulação RTL não a modela; essa
// parte fica com a análise de CDC/STA.
//
// Opções (ver Makefile.simulation):
//   +seed=N              semente das esperas e palavras aleatórias (padrão 1)
//   -P tb_sender.SYNC_STAGES=K   FFs do sincronizador do ACK (padrão 2)
// =============================================================================
`timescale 1ns/1ps

module tb_sender #(
    parameter int SYNC_STAGES = 2
);

    localparam int W = 16;
    localparam int N = 16;

    // Ciclos de CLK_A que wait_done espera antes de declarar travamento
    // (o cenário mais longo, S4, usa ~200 ciclos)
    localparam int DONE_TIMEOUT = 2000;

    // ------------------------------------------------------------------
    // Semente: todas as escolhas aleatórias passam por rnd()
    // ------------------------------------------------------------------
    int unsigned seed = 1;

    function automatic int unsigned rnd(input int unsigned max);
        return $urandom(seed) % (max + 1);
    endfunction

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

    sender #(.WIDTH(W), .DEPTH(N), .SYNC_STAGES(SYNC_STAGES)) dut (
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
                repeat (rnd(ack_rise_max)) @(posedge CLK_B);
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
                repeat (rnd(ack_fall_max)) @(posedge CLK_B);
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

    // ACK passa por SYNC_STAGES FFs até virar ack_s; depois, 1 ciclo para a
    // FSM ir a S_WAIT_ACK_LOW e 1 para o registrador de req cair. Com o ACK
    // subindo logo antes de uma borda, o mínimo é (SYNC_STAGES + 1) ciclos.
    realtime t_ack_rise = 0;
    always @(posedge ack) begin
        t_ack_rise = $realtime;
        if (!req) fail("ACK subiu sem REQ");
    end

    always @(negedge req) begin
        if (rst_n && !ack) fail("REQ caiu antes do ACK");
        if (rst_n && ($realtime - t_ack_rise < (SYNC_STAGES + 1) * period_a - 0.001))
            fail($sformatf("REQ caiu só %0.3f ns depois de ACK (mínimo %0d ciclos de CLK_A: sincronizador ausente ou curto?)",
                           $realtime - t_ack_rise, SYNC_STAGES + 1));
    end

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
                default: words[i] = rnd(16'hFFFF);
            endcase
    endtask

    task automatic check_reset_values;
        if (in_ready !== 1'b0) fail("IN_READY deveria ser 0 em reset");
        if (req      !== 1'b0) fail("REQ deveria ser 0 em reset");
        if (tx_data  !== '0)   fail("tx_data deveria ser 0 em reset");
        if (dut.state !== dut.S_CAPTURE) fail("estado deveria ser S_CAPTURE em reset");
    endtask

    // Solta o reset logo após uma borda de CLK_A (o que o reset_sync do topo
    // garante); antes, confere que os valores de reset se mantiveram
    task automatic release_reset;
        @(posedge CLK_A);
        #0.1;
        check_reset_values();
        in_valid = 1'b0;
        rst_n    = 1'b1;
        @(posedge CLK_A);
        #0.1;
        if (in_ready !== 1'b1) fail("IN_READY deveria estar ativo após o reset");
        if (req      !== 1'b0) fail("REQ deveria continuar 0 após o reset");
    endtask

    // Ativa o reset, confere os valores e solta depois de hold_ns
    task automatic apply_reset(input real hold_ns);
        rst_n    = 1'b0;
        in_valid = 1'b0;
        #0.01;
        check_reset_values();
        #(hold_ns);
        release_reset();
    endtask

    // Fonte externa: envia as n primeiras palavras; max_gap = ciclos ociosos máximos
    task automatic drive_inputs(input int max_gap, input int n = N);
        for (int i = 0; i < n; i++) begin
            in_valid <= 1'b0;
            data_in  <= 16'hxxxx;
            repeat (rnd(max_gap)) @(posedge CLK_A);
            in_valid <= 1'b1;
            data_in  <= words[i];
            @(posedge CLK_A);
            while (!in_ready) @(posedge CLK_A);
        end
        in_valid <= 1'b0;
        data_in  <= '0;
    endtask

    // Espera o fim da transferência e confere o estado final. Se o Sender
    // travar, acusa o erro com o ponto em que parou e segue para o próximo
    // cenário.
    // (Laço com contador em vez de fork/join_any + disable fork: no Icarus 12,
    // disable fork dentro de uma task chamada num fork derruba o vvp.)
    task automatic wait_done;
        int cycles = 0;
        while (hs_count != N && cycles < DONE_TIMEOUT) begin
            @(posedge CLK_A);
            cycles++;
        end
        if (hs_count != N) begin
            fail($sformatf("travou: in_count = %0d, rx_count = %0d, hs_count = %0d, estado = %s",
                           in_count, rx_count, hs_count, dut.state.name()));
        end else begin
            repeat (6) @(posedge CLK_A);
            if (dut.state !== dut.S_DONE) fail("Sender não chegou a S_DONE");
            if (req      !== 1'b0)        fail("REQ ativo depois do 16o handshake");
            if (in_ready !== 1'b0)        fail("IN_READY ativo em S_DONE");
        end
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
        void'($value$plusargs("seed=%d", seed));
        $display("tb_sender: seed = %0d, SYNC_STAGES = %0d", seed, SYNC_STAGES);

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
        release_reset();
        fork
            drive_inputs(1);
            wait_done();
        join
        check_counts();

        // ---------------- S3b ----------------
        new_test("S3b reset no meio da captura");
        gen_words(2);
        apply_reset(13.0);
        drive_inputs(1, 7);                    // 7 palavras capturadas
        in_valid <= 1'b1;                      // fonte continua oferecendo a 8a
        data_in  <= words[7];
        #1.7;                                  // fora da borda de CLK_A
        if (in_count != 7) fail($sformatf("%0d palavras capturadas antes do reset (esperado 7)", in_count));
        rst_n = 1'b0;                          // in_valid continua 1
        #0.01;
        check_reset_values();
        repeat (5) @(posedge CLK_A);           // in_valid = 1 por 5 bordas em reset
        if (in_count != 7) fail("palavra capturada durante o reset");
        new_test("S3b recomeço após o reset");
        gen_words(0);
        release_reset();
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

    // Watchdog: último recurso (wait_done já tem timeout próprio)
    initial begin
        #400_000;
        fail($sformatf("timeout da simulação: in_count = %0d, rx_count = %0d, hs_count = %0d, estado = %s",
                       in_count, rx_count, hs_count, dut.state.name()));
        $display("\n==============================================");
        $display("  FALHA: %0d erro(s)", errors);
        $display("==============================================\n");
        $finish;
    end

endmodule
