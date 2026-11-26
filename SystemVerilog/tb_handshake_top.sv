// =============================================================================
// tb_handshake_top.sv  —  Testbench do sistema completo
//
// Cenários:
//   T1  Reset inicial: valores de reset e liberação síncrona em cada domínio
//   T2  Fluxo sem esperas (CLK_A rápido, CLK_B lento) + IN_VALID extra ignorado
//   T3  Reset assíncrono no meio do handshake
//   T4  Esperas aleatórias: IN_VALID inativo e OUT_READY inativo
//   T5  Clocks invertidos (CLK_A lento, CLK_B rápido) com esperas
//   T6  Clocks quase iguais (10,0 / 10,1 ns): a fase relativa escorrega
//       0,1 ns por ciclo e passa por bordas praticamente coincidentes
//
// Verificações automáticas (monitores sempre ligados):
//   - ordem e conteúdo das 16 palavras em DATA_OUT
//   - DATA_OUT/OUT_VALID estáveis enquanto OUT_VALID=1 e OUT_READY=0
//   - OUT_VALID nunca ativo antes de RX_DONE e sobe junto com ele;
//     RX_DONE "grudado" até o reset
//   - sequência correta das 4 fases do handshake REQ/ACK
//   - tx_data estável enquanto REQ ou ACK estiverem ativos
//   - reset_sender_n / reset_receiver_n sobem só na borda do próprio clock
// =============================================================================
`timescale 1ns/1ps

module tb_handshake_top;

    localparam int W = 16;
    localparam int N = 16;

    // ------------------------------------------------------------------
    // Clocks independentes (períodos ajustáveis durante a simulação)
    // ------------------------------------------------------------------
    // Períodos (ver config.mk / handshake.sdc). Pares escolhidos com
    // mdc(T_A, T_B) = 0,1 ns: a fase relativa entre as bordas varre muitos
    // valores distintos em vez de repetir poucos alinhamentos.
    //   T2      : 4,0 / 5,7 ns   (mesmo par do SDC Nangate45, 40:57)
    //   T4      : 10,0 / 14,3 ns (mesmo par do SDC Sky130HD, 100:143)
    //   T5      : 23,3 / 7,0 ns  (razão ~3,3 invertida, 233:70)
    //   T6      : 10,0 / 10,1 ns (quase iguais, 100:101)
    // Na simulação RTL não há atrasos: só a razão e a fase entre os clocks
    // importam. Os valores absolutos de T2/T4 coincidem com o SDC apenas
    // por rastreabilidade.
    real half_a = 2.0;     // CLK_A = 4.0 ns
    real half_b = 2.85;    // CLK_B = 5.7 ns (não múltiplo de CLK_A)

    logic CLK_A = 1'b0;
    logic CLK_B = 1'b0;

    initial begin #1.3; forever #(half_a) CLK_A = ~CLK_A; end   // fases iniciais
    initial begin #3.7; forever #(half_b) CLK_B = ~CLK_B; end   // diferentes

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic         RESET_N   = 1'b1;   // vai a 0 em t=0.5 ns (gera borda de descida)
    logic [W-1:0] DATA_IN   = '0;
    logic         IN_VALID  = 1'b0;
    logic         IN_READY;
    logic         RX_DONE;
    logic         OUT_READY = 1'b0;
    logic [W-1:0] DATA_OUT;
    logic         OUT_VALID;
    logic         OUT_DONE;

    handshake_top #(.WIDTH(W), .DEPTH(N)) dut (
        .CLK_A     (CLK_A),
        .CLK_B     (CLK_B),
        .RESET_N   (RESET_N),
        .DATA_IN   (DATA_IN),
        .IN_VALID  (IN_VALID),
        .IN_READY  (IN_READY),
        .RX_DONE   (RX_DONE),
        .OUT_READY (OUT_READY),
        .DATA_OUT  (DATA_OUT),
        .OUT_VALID (OUT_VALID),
        .OUT_DONE  (OUT_DONE)
    );

    // ------------------------------------------------------------------
    // Estado do testbench
    // ------------------------------------------------------------------
    logic [W-1:0] words [0:N-1];   // palavras do teste atual
    int errors    = 0;
    int in_count  = 0;             // palavras aceitas na entrada
    int out_count = 0;             // palavras aceitas na saída
    int hs_count  = 0;             // handshakes REQ/ACK (subidas de ACK)
    string test_name = "";

    task automatic fail(input string msg);
        errors++;
        $display("[%0t] ERRO (%s): %s", $time, test_name, msg);
    endtask

    // ------------------------------------------------------------------
    // Monitores — interface de entrada (CLK_A)
    // ------------------------------------------------------------------
    always @(posedge CLK_A) begin
        if (IN_VALID && IN_READY) begin
            if (in_count >= N)
                fail($sformatf("palavra extra capturada na entrada: %h", DATA_IN));
            else if (DATA_IN !== words[in_count])
                fail($sformatf("entrada %0d: esperado %h, aplicado %h",
                               in_count, words[in_count], DATA_IN));
            in_count++;
        end
    end

    // ------------------------------------------------------------------
    // Monitores — interface de saída (CLK_B)
    // ------------------------------------------------------------------
    logic         prev_valid = 1'b0;
    logic         prev_ready = 1'b0;
    logic [W-1:0] prev_data  = '0;
    logic         prev_rxdone = 1'b0;

    always @(posedge CLK_B) begin
        if (!RESET_N) begin
            prev_valid  <= 1'b0;
            prev_ready  <= 1'b0;
            prev_rxdone <= 1'b0;
        end else begin
            // Transferência de saída: confere ordem e conteúdo
            if (OUT_VALID && OUT_READY) begin
                if (out_count >= N)
                    fail("palavra extra entregue na saída");
                else if (DATA_OUT !== words[out_count])
                    fail($sformatf("saída %0d: esperado %h, recebido %h",
                                   out_count, words[out_count], DATA_OUT));
                else
                    $display("[%0t] (%s) saída %2d OK: %h", $time, test_name, out_count, DATA_OUT);
                out_count++;
            end

            // Estabilidade enquanto OUT_VALID=1 e OUT_READY=0
            if (prev_valid && !prev_ready) begin
                if (!OUT_VALID)
                    fail("OUT_VALID caiu sem a palavra ter sido aceita");
                if (DATA_OUT !== prev_data)
                    fail("DATA_OUT mudou enquanto OUT_READY estava inativo");
            end

            // OUT_VALID só depois de RX_DONE
            if (OUT_VALID && !RX_DONE)
                fail("OUT_VALID ativo antes de RX_DONE");

            // OUT_VALID sobe na mesma borda de CLK_B que RX_DONE
            // (decisão do grupo em 22/11, ver README e relatório 2.4)
            if (RX_DONE && !prev_rxdone && !OUT_VALID)
                fail("OUT_VALID não subiu junto com RX_DONE");

            // RX_DONE permanece ativo até o reset
            if (prev_rxdone && !RX_DONE)
                fail("RX_DONE caiu sem reset");

            // OUT_DONE só depois da 16ª palavra
            if (OUT_DONE && out_count < N)
                fail("OUT_DONE ativo antes da 16a palavra");

            prev_valid  <= OUT_VALID;
            prev_ready  <= OUT_READY;
            prev_data   <= DATA_OUT;
            prev_rxdone <= RX_DONE;
        end
    end

    // ------------------------------------------------------------------
    // Monitores — handshake interno de 4 fases
    // ------------------------------------------------------------------
    always @(posedge dut.req) if (dut.ack)                fail("REQ subiu com ACK ainda ativo");
    always @(posedge dut.ack) begin
        if (!dut.req) fail("ACK subiu sem REQ");
        hs_count++;
    end
    always @(negedge dut.req) if (RESET_N && !dut.ack)    fail("REQ caiu antes do ACK");
    always @(negedge dut.ack) if (RESET_N &&  dut.req)    fail("ACK caiu com REQ ainda ativo");

    // Bundled-data: tx_data não pode mudar durante a janela do handshake
    always @(dut.tx_data) if (RESET_N && (dut.req || dut.ack))
        fail("tx_data mudou durante o handshake");

    // ------------------------------------------------------------------
    // Monitores — reset: liberação síncrona em cada domínio
    // ------------------------------------------------------------------
    realtime t_pos_a = 0, t_pos_b = 0;
    always @(posedge CLK_A) t_pos_a = $realtime;
    always @(posedge CLK_B) t_pos_b = $realtime;

    always @(posedge dut.reset_sender_n)
        if ($realtime != t_pos_a) fail("reset_sender liberado fora da borda de CLK_A");
    always @(posedge dut.reset_receiver_n)
        if ($realtime != t_pos_b) fail("reset_receiver liberado fora da borda de CLK_B");

    // ------------------------------------------------------------------
    // Tarefas auxiliares
    // ------------------------------------------------------------------
    task automatic new_test(input string name);
        test_name = name;
        in_count  = 0;
        out_count = 0;
        hs_count  = 0;
        $display("\n==== %s ====", name);
    endtask

    task automatic gen_words(input int mode);
        for (int i = 0; i < N; i++)
            case (mode)
                0:       words[i] = 16'hA500 + i;            // padrão fácil de ler
                1:       words[i] = 16'h1 << i;              // walking one
                default: words[i] = $urandom;                // aleatório
            endcase
    endtask

    // Aplica reset (assíncrono) e solta em um instante qualquer
    task automatic apply_reset(input real hold_ns);
        RESET_N   = 1'b0;
        IN_VALID  = 1'b0;
        OUT_READY = 1'b0;
        #0.01;
        check_reset_values();
        #(hold_ns);
        RESET_N = 1'b1;
        repeat (4) @(posedge CLK_A);
        repeat (4) @(posedge CLK_B);
        if (!dut.reset_sender_n)   fail("reset_sender não foi liberado");
        if (!dut.reset_receiver_n) fail("reset_receiver não foi liberado");
        if (!IN_READY)             fail("IN_READY deveria estar ativo após o reset");
    endtask

    task automatic check_reset_values;
        if (dut.reset_sender_n   !== 1'b0) fail("reset_sender não ativou imediatamente");
        if (dut.reset_receiver_n !== 1'b0) fail("reset_receiver não ativou imediatamente");
        if (IN_READY  !== 1'b0) fail("IN_READY deveria ser 0 em reset");
        if (RX_DONE   !== 1'b0) fail("RX_DONE deveria ser 0 em reset");
        if (OUT_VALID !== 1'b0) fail("OUT_VALID deveria ser 0 em reset");
        if (OUT_DONE  !== 1'b0) fail("OUT_DONE deveria ser 0 em reset");
        if (dut.req   !== 1'b0) fail("REQ deveria ser 0 em reset");
        if (dut.ack   !== 1'b0) fail("ACK deveria ser 0 em reset");
    endtask

    // Fonte externa: envia as N palavras; max_gap = ciclos ociosos máximos
    task automatic drive_inputs(input int max_gap);
        for (int i = 0; i < N; i++) begin
            IN_VALID <= 1'b0;
            DATA_IN  <= 16'hxxxx;
            repeat ($urandom_range(max_gap, 0)) @(posedge CLK_A);
            IN_VALID <= 1'b1;
            DATA_IN  <= words[i];
            @(posedge CLK_A);
            while (!IN_READY) @(posedge CLK_A);   // espera captura (valid && ready)
        end
        IN_VALID <= 1'b0;
        DATA_IN  <= '0;
    endtask

    // Consumidor externo: espera RX_DONE e lê as N palavras;
    // ready_pct = probabilidade (%) de OUT_READY ativo em cada ciclo
    task automatic consume_outputs(input int ready_pct);
        wait (RX_DONE === 1'b1);
        @(posedge CLK_B);
        while (out_count < N) begin
            OUT_READY <= ($urandom_range(99, 0) < ready_pct);
            @(posedge CLK_B);
        end
        OUT_READY <= 1'b0;
        repeat (3) @(posedge CLK_B);
        if (OUT_DONE  !== 1'b1) fail("OUT_DONE não ativou após a 16a palavra");
        if (OUT_VALID !== 1'b0) fail("OUT_VALID continua ativo após OUT_DONE");
        if (RX_DONE   !== 1'b1) fail("RX_DONE deveria continuar ativo");
    endtask

    task automatic check_counts;
        if (in_count  != N) fail($sformatf("%0d palavras capturadas (esperado %0d)", in_count, N));
        if (out_count != N) fail($sformatf("%0d palavras entregues (esperado %0d)", out_count, N));
        if (hs_count  != N) fail($sformatf("%0d handshakes (esperado %0d)", hs_count, N));
    endtask

    // ------------------------------------------------------------------
    // Sequência de testes
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_handshake_top.vcd");
        $dumpvars(0, tb_handshake_top);

        // ---------------- T1 ----------------
        new_test("T1 reset inicial");
        gen_words(0);
        #0.5;                                     // garante borda 1->0 em RESET_N
        apply_reset(23.4);

        // ---------------- T2 ----------------
        new_test("T2 fluxo sem esperas");
        fork
            drive_inputs(0);
            consume_outputs(100);
        join
        // IN_VALID continua ativo depois das 16 palavras: nada pode ser capturado
        IN_VALID <= 1'b1;
        DATA_IN  <= 16'hDEAD;
        repeat (10) @(posedge CLK_A);
        if (IN_READY) fail("IN_READY ativo depois de 16 palavras");
        IN_VALID <= 1'b0;
        check_counts();

        // ---------------- T3 ----------------
        new_test("T3 reset no meio do handshake");
        gen_words(1);
        apply_reset(17.0);
        drive_inputs(0);
        wait (hs_count == 5);
        #3.141;                                   // instante não alinhado aos clocks
        RESET_N = 1'b0;
        #0.01;
        check_reset_values();
        #40;
        RESET_N = 1'b1;
        repeat (4) @(posedge CLK_B);
        if (RX_DONE) fail("RX_DONE ativo após reset");

        // ---------------- T4 ----------------
        new_test("T4 esperas aleatorias (IN_VALID e OUT_READY inativos)");
        half_a = 5.0;    // CLK_A = 10.0 ns
        half_b = 7.15;   // CLK_B = 14.3 ns
        gen_words(2);
        apply_reset(31.0);
        fork
            drive_inputs(4);
            consume_outputs(35);
        join
        check_counts();

        // ---------------- T5 ----------------
        new_test("T5 clocks invertidos (CLK_A lento, CLK_B rapido)");
        half_a = 11.65;  // CLK_A = 23.3 ns
        half_b = 3.5;    // CLK_B =  7.0 ns
        gen_words(2);
        apply_reset(29.0);
        fork
            drive_inputs(3);
            consume_outputs(50);
        join
        check_counts();

        // ---------------- T6 ----------------
        // Caso clássico de CDC: com períodos quase iguais, a fase relativa
        // escorrega 0,1 ns por ciclo, e ao longo da transferência as bordas
        // de CLK_A e CLK_B passam por todos os alinhamentos, inclusive o
        // quase coincidente.
        new_test("T6 clocks quase iguais (CLK_A = 10,0 ns, CLK_B = 10,1 ns)");
        half_a = 5.0;    // CLK_A = 10.0 ns
        half_b = 5.05;   // CLK_B = 10.1 ns
        gen_words(2);
        apply_reset(27.0);
        fork
            drive_inputs(0);
            consume_outputs(100);
        join
        check_counts();

        // ---------------- Resultado ----------------
        $display("\n==============================================");
        if (errors == 0) $display("  TODOS OS TESTES PASSARAM");
        else             $display("  FALHA: %0d erro(s)", errors);
        $display("==============================================\n");
        $finish;
    end

    // Watchdog: evita simulação infinita se algo travar
    initial begin
        #200_000;
        $display("[%0t] ERRO: timeout da simulação", $time);
        $finish;
    end

endmodule
