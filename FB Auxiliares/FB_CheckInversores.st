// ════════════════════════════════════════════════════════════════════
// FB_CheckInversores — Varredura de presença de inversores no startup
// ════════════════════════════════════════════════════════════════════
//
// Responsabilidade:
//   Percorrer sequencialmente todos os inversores configurados
//   (InvActivePower > 0) em COM1 e COM2, disparar 1 transação
//   Modbus em cada um e verificar ACK. Não valida o valor lido.
//
// Critério de avanço:
//   respondidos / configurados >= GVL_Persis.InvCheckThreshold → xDone=TRUE
//   abaixo do limiar ou timeout global                         → xFailed=TRUE
//
// Contrato com FB_Startup:
//   • xEnable := TRUE  para iniciar/continuar a varredura
//   • xEnable := FALSE reseta o FB (pronto para nova execução)
//   • Lê resultado via xDone / xFailed a cada ciclo
//   • xFailed=TRUE: ler uRespondedTotal e uConfiguredTotal para log
//
// Restrições:
//   • 1 transação Modbus por ciclo de scan (sequencial, determinístico)
//   • Não escreve em GVL_ALARM_MANAGER — responsabilidade do FB_Startup
//   • Tempo máximo: TimeInvTimeout (default 60s para até 30 inversores)
// ════════════════════════════════════════════════════════════════════
FUNCTION_BLOCK FB_CheckInversores

VAR_INPUT
    xEnable         : BOOL;             // TRUE = executar; FALSE = reset
    tTxTimeout      : TIME := T#500MS;  // timeout por transação individual
    tGlobalTimeout  : TIME := T#60S;    // timeout para varredura completa
END_VAR

VAR_OUTPUT
    xDone           : BOOL;             // varredura concluída e acima do limiar
    xFailed         : BOOL;             // abaixo do limiar ou timeout global
    uRespondedTotal : UINT;             // total de inversores que responderam
    uConfiguredTotal: UINT;             // total de inversores configurados
    uLastFailIdx    : UINT;             // índice do último inversor que não respondeu
    uLastFailCOM    : UINT;             // canal do último inversor que não respondeu (1 ou 2)
END_VAR

VAR
    fbTx            : FB_ModBus;        // instância única reutilizada ciclo a ciclo
    uCheckIdx       : UINT := 1;        // índice atual (1..15 dentro do canal)
    uCheckCOM       : UINT := 1;        // canal atual: 1=COM1, 2=COM2, 3=avaliação final
    uRespondedCOM1  : UINT := 0;
    uRespondedCOM2  : UINT := 0;
    bInitDone       : BOOL := FALSE;    // guarda de inicialização
    TonGlobal       : TON;
    // ── Startup: verificação de presença de inversores ────────────
    // Fração mínima de inversores que devem responder para avançar o startup.
    // 1.0 = todos devem responder (padrão conservador)
    // 0.8 = pelo menos 80% devem responder
    CheckThreshold  : REAL := 1.0;
END_VAR

    // ── Reset quando desabilitado ─────────────────────────────────────
    IF NOT xEnable THEN
        xDone            := FALSE;
        xFailed          := FALSE;
        uRespondedCOM1   := 0;
        uRespondedCOM2   := 0;
        uRespondedTotal  := 0;
        uConfiguredTotal := 0;
        uLastFailIdx     := 0;
        uLastFailCOM     := 0;
        uCheckIdx        := 1;
        uCheckCOM        := 1;
        bInitDone        := FALSE;
        TonGlobal(IN := FALSE);
        RETURN;
    END_IF
    
    // ── Se já terminou, mantém resultado sem re-executar ─────────────
    IF xDone OR xFailed THEN
        RETURN;
    END_IF
    
    // ── Inicialização na primeira entrada ────────────────────────────
    IF NOT bInitDone THEN
        uConfiguredTotal := GVL_Main.NInversoresCOM01 + GVL_Main.NInversoresCOM02;
        bInitDone        := TRUE;
    
        // COM2 vazio é permitido — varredura só em COM1
        // uCheckCOM já = 1, sem ação adicional
    END_IF
    
    // ── Timeout global ────────────────────────────────────────────────
    TonGlobal(IN := TRUE, PT := tGlobalTimeout);
    IF TonGlobal.Q THEN
        TonGlobal(IN := FALSE);
        uRespondedTotal := uRespondedCOM1 + uRespondedCOM2;
        xFailed := TRUE;
        RETURN;
    END_IF
    
    // ── Varredura COM1 ────────────────────────────────────────────────
    IF uCheckCOM = 1 THEN
    
        IF uCheckIdx <= GVL_Main.NInversoresCOM01 THEN
            fbTx(
                tTimeout := tTxTimeout,
                trigInv  := GVL_Main.trigInvCOM100[uCheckIdx, 0],
                pSlave   := GVL_Main.pInversores100[uCheckIdx]^
            );
    
            CASE fbTx.result OF
                E_ModbusResult.DONE:
                    uRespondedCOM1 := uRespondedCOM1 + 1;
                    uCheckIdx      := uCheckIdx + 1;
    
                E_ModbusResult.ERRO,
                E_ModbusResult.TIMEOUT:
                    uLastFailIdx := uCheckIdx;
                    uLastFailCOM := 1;
                    uCheckIdx    := uCheckIdx + 1;
    
                // BUSY: aguarda sem avançar
            END_CASE
    
        ELSE
            // COM1 concluída
            uCheckIdx := 1;
            uCheckCOM := 2;  // avança para COM2 (mesmo que vazia — avaliação em uCheckCOM=3)
        END_IF
    
    // ── Varredura COM2 ────────────────────────────────────────────────
    ELSIF uCheckCOM = 2 THEN
    
        IF GVL_Main.NInversoresCOM02 = 0 THEN
            // Canal vazio — pula direto para avaliação
            uCheckCOM := 3;
    
        ELSIF uCheckIdx <= GVL_Main.NInversoresCOM02 THEN
            fbTx(
                tTimeout := tTxTimeout,
                trigInv  := GVL_Main.trigInvCOM200[uCheckIdx, 0],
                pSlave   := GVL_Main.pInversores200[uCheckIdx]^
            );
    
            CASE fbTx.result OF
                E_ModbusResult.DONE:
                    uRespondedCOM2 := uRespondedCOM2 + 1;
                    uCheckIdx      := uCheckIdx + 1;
    
                E_ModbusResult.ERRO,
                E_ModbusResult.TIMEOUT:
                    uLastFailIdx := uCheckIdx;
                    uLastFailCOM := 2;
                    uCheckIdx    := uCheckIdx + 1;
    
                // BUSY: aguarda sem avançar
            END_CASE
    
        ELSE
            // COM2 concluída
            uCheckCOM := 3;
        END_IF
    
    // ── Avaliação final ───────────────────────────────────────────────
    ELSIF uCheckCOM = 3 THEN
    
        TonGlobal(IN := FALSE);
        uRespondedTotal := uRespondedCOM1 + uRespondedCOM2;
    
        IF uConfiguredTotal = 0 THEN
            // Proteção defensiva — não deveria chegar aqui (stInit já bloqueia)
            xFailed := TRUE;
            RETURN;
        END_IF
    
        IF (TO_REAL(uRespondedTotal) / TO_REAL(uConfiguredTotal)) >= CheckThreshold THEN
            xDone := TRUE;
        ELSE
            xFailed := TRUE;
        END_IF
    
    END_IF
    
END_FUNCTION_BLOCK
