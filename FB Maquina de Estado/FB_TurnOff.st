(*
  FB_TurnOff - OPÇÃO B + MODO 1 (corrigido)
  
  Correções vs versão anterior:
  1. TO_INIT não avança imediatamente — aguarda 1 scan para Main executar ações
  2. Log de transição não sobrescreve evento de negócio (prioridade explícita)
  3. TO_DISCONNECT permanece 1 scan mínimo (log garantido)
  4. Reset COM garantido antes de escrita (via xReqResetCOM junto com xWriteZeroEnable)
  5. nMaxInv passado como parâmetro (conforme decidido)
  6. Saídas K1/K2 em estado seguro quando xRequestStop=TRUE (previne buraco de 1 scan)
*)
FUNCTION_BLOCK FB_TurnOff
VAR_INPUT
    xEnable          : BOOL;
    xStartResetEdge  : BOOL;

    xK2_in           : BOOL;

    rPt_kW           : REAL;
    xMeasDataOK      : BOOL;

    nMaxInv          : UINT := 30;
    rP_Threshold_kW  : REAL := 0.5;
    tVerifyTimeout   : TIME := T#30S;
    tK2Timeout       : TIME := T#2S;
    uMaxWriteRetries : UINT := 3;

    // feedback das escritas (Main fornece)
    xCom1Done        : BOOL;
    xCom1Critical    : BOOL;
    xCom2Done        : BOOL;
    xCom2Critical    : BOOL;
END_VAR

VAR_OUTPUT
    // saídas físicas
    xK1_out          : BOOL;
    xK2_out          : BOOL;
    xLedRed          : BOOL;
    xLedYellow       : BOOL;
    xLedGreen        : BOOL;

    // pedidos ao Main (OPÇÃO B)
    xReqZeroSetpoints : BOOL;   // pulso 1 scan: Main deve zerar arrays P/Q
    xReqResetPI       : BOOL;   // pulso 1 scan: Main deve chamar fbControle(bReset:=TRUE)
    xReqResetCOM      : BOOL;   // pulso 1 scan: Main deve passar Reset:=TRUE ao fbWriteCOM
    xWriteZeroEnable  : BOOL;   // nível: enquanto TRUE, Main chama fbWriteCOM normalmente

    // transições
    xRequestStop     : BOOL;
    xRequestStart    : BOOL;

    // log 1 por transição/ocorrência
    xLogEvent        : BOOL;
    eLogCode         : E_EventCode;
    rLogParam1       : REAL;
    rLogParam2       : REAL;
    
    // diagnóstico
    eSubState        : E_TurnOffState;
    uWriteRetryCount : UINT;
END_VAR

VAR
   Estado               : E_TurnOffState := E_TurnOffState.TO_INIT;
   PrevEstado           : E_TurnOffState := E_TurnOffState.TO_INIT;

    uRetry           : UINT := 0;

    tonVerify        : TON;
    tonK2            : TON;

    bInitPulseDone   : BOOL := FALSE;
    bDisconnectDone  : BOOL := FALSE;   // garante TO_DISCONNECT permanece 1 scan
END_VAR

    // ──────────────────────────────────────────────────────────────
    // Defaults (seguros): todo scan limpa pedidos e flags
    // ──────────────────────────────────────────────────────────────
    xRequestStop      := FALSE;
    xRequestStart     := FALSE;
    
    xReqZeroSetpoints := FALSE;
    xReqResetPI       := FALSE;
    xReqResetCOM      := FALSE;
    xWriteZeroEnable  := FALSE;
    
    xLogEvent  := FALSE;
    eLogCode   := E_EventCode.EVT_NONE;
    rLogParam1 := 0.0;
    rLogParam2 := 0.0;
    
    // ──────────────────────────────────────────────────────────────
    // Desabilitado: reseta tudo e sai
    // ──────────────────────────────────────────────────────────────
    IF NOT xEnable THEN
        Estado := E_TurnOffState.TO_INIT;
        PrevEstado := E_TurnOffState.TO_INIT;
        uRetry := 0;
        tonVerify(IN := FALSE);
        tonK2(IN := FALSE);
        bInitPulseDone := FALSE;
        bDisconnectDone := FALSE;
    
        xK1_out := FALSE;
        xK2_out := FALSE;
        xLedRed := FALSE;
        xLedYellow := FALSE;
        xLedGreen := FALSE;
        
        eSubState := E_TurnOffState.TO_INIT;
        uWriteRetryCount := 0;
        RETURN;
    END_IF
    
    // Diagnóstico
    eSubState := Estado;
    uWriteRetryCount := uRetry;
    
    // ──────────────────────────────────────────────────────────────
    // Log de transição: 1 evento por mudança de subestado
    // ATENÇÃO: eventos de negócio (retry, timeout, K2 falhou) são
    // gerados DENTRO do CASE e podem sobrescrever este.
    // Prioridade: evento de negócio > evento de transição.
    // Por isso, aqui setamos xLogEvent=TRUE mas o CASE pode
    // sobrescrever com evento mais relevante.
    // ──────────────────────────────────────────────────────────────
    IF Estado <> PrevEstado THEN
        PrevEstado := Estado;
        xLogEvent := TRUE;
        CASE Estado OF
            E_TurnOffState.TO_INIT:        eLogCode := E_EventCode.INFO_TURNOFF_ENTRY;
            E_TurnOffState.TO_WRITE_ZERO:  eLogCode := E_EventCode.INFO_TURNOFF_ZERO_SENT;
            E_TurnOffState.TO_VERIFY:      eLogCode := E_EventCode.INFO_TURNOFF_ZERO_SENT;
            E_TurnOffState.TO_DISCONNECT:  eLogCode := E_EventCode.INFO_TURNOFF_EXPORT_CONFIRMED;
                                           rLogParam1 := rPt_kW;
            E_TurnOffState.TO_CONFIRM:     eLogCode := E_EventCode.INFO_TURNOFF_K2_TRIPPED;
            E_TurnOffState.TO_DONE:        eLogCode := E_EventCode.INFO_TURNOFF_DONE;
        END_CASE
    END_IF
    
    // ──────────────────────────────────────────────────────────────
    // Submáquina de estados
    // ──────────────────────────────────────────────────────────────
    CASE Estado OF
    
        // ══════════════════════════════════════════════════════════
        // TO_INIT: Zera setpoints e prepara escrita
        // NÃO avança no mesmo scan — aguarda 1 scan para Main
        // executar as ações (zerar arrays, resetar PI, resetar COM)
        // ══════════════════════════════════════════════════════════
        E_TurnOffState.TO_INIT:
            xLedYellow := TRUE;
            xLedGreen  := FALSE;
            xLedRed    := FALSE;
    
            // Mantém permissivo enquanto reduz geração
            xK1_out := TRUE;
            xK2_out := FALSE;
    
            tonVerify(IN := FALSE);
            tonK2(IN := FALSE);
            bDisconnectDone := FALSE;
    
            IF NOT bInitPulseDone THEN
                // Pede ações ao Main (pulso 1 scan)
                xReqZeroSetpoints := TRUE;
                xReqResetPI       := TRUE;
                xReqResetCOM      := TRUE;
                bInitPulseDone    := TRUE;
                // NÃO avança: espera o próximo scan para Main ter executado
            ELSE
                // 2o scan: Main já zerou setpoints e resetou COM
                // Agora pode avançar para escrita
               Estado:= E_TurnOffState.TO_WRITE_ZERO;
            END_IF
    
        // ══════════════════════════════════════════════════════════
        // TO_WRITE_ZERO: Habilita escrita de zero via Main
        // O Main chama fbWriteCOM1/2 enquanto xWriteZeroEnable=TRUE
        // ══════════════════════════════════════════════════════════
        E_TurnOffState.TO_WRITE_ZERO:
            xLedYellow := TRUE;
            xLedGreen  := FALSE;
            xLedRed    := FALSE;
    
            xK1_out := TRUE;
            xK2_out := FALSE;
    
            // Habilita escritas de zero no Main
            xWriteZeroEnable := TRUE;
    
            // Aguarda resultado das duas COM (feedback do Main)
            IF xCom1Done AND xCom2Done THEN
                IF xCom1Critical OR xCom2Critical THEN
                    uRetry := uRetry + 1;
    
                    // Evento de negócio (sobrescreve transição se houver)
                    xLogEvent  := TRUE;
                    eLogCode   := E_EventCode.WARN_TURNOFF_WRITE_RETRY;
                    rLogParam1 := TO_REAL(uRetry);
                    rLogParam2 := 0.0;
    
                    IF uRetry >= uMaxWriteRetries THEN
                        // Esgotou tentativas → escala para STOP
                        xLogEvent  := TRUE;
                        eLogCode   := E_EventCode.CRIT_TURNOFF_WRITE_EXHAUSTED;
                        rLogParam1 := TO_REAL(uRetry);
                        rLogParam2 := 0.0;
                        
                        // Comanda estado seguro antes de sair
                        xK1_out := FALSE;
                        xK2_out := TRUE;
                        xRequestStop := TRUE;
                    ELSE
                        // Retry: volta para INIT para re-preparar
                        bInitPulseDone := FALSE;
                       Estado:= E_TurnOffState.TO_INIT;
                    END_IF
                ELSE
                    // Escrita OK → verifica geração
                   Estado:= E_TurnOffState.TO_VERIFY;
                END_IF
            END_IF
    
        // ══════════════════════════════════════════════════════════
        // TO_VERIFY: Confirma que geração caiu para ~0 kW
        // ══════════════════════════════════════════════════════════
        E_TurnOffState.TO_VERIFY:
            xLedYellow := TRUE;
            xLedGreen  := FALSE;
            xLedRed    := FALSE;
    
            xK1_out := TRUE;
            xK2_out := FALSE;
    
            tonVerify(IN := TRUE, PT := tVerifyTimeout);
    
            IF xMeasDataOK AND (ABS(rPt_kW) < rP_Threshold_kW) THEN
                tonVerify(IN := FALSE);
    
                xLogEvent  := TRUE;
                eLogCode   := E_EventCode.INFO_TURNOFF_EXPORT_CONFIRMED;
                rLogParam1 := rPt_kW;
                rLogParam2 := rP_Threshold_kW;
    
               Estado:= E_TurnOffState.TO_DISCONNECT;
            END_IF
    
            IF tonVerify.Q THEN
                tonVerify(IN := FALSE);
    
                xLogEvent  := TRUE;
                eLogCode   := E_EventCode.CRIT_TURNOFF_VERIFY_TIMEOUT;
                rLogParam1 := rPt_kW;
                rLogParam2 := REAL#30.0;
    
                // Comanda estado seguro antes de sair
                xK1_out := FALSE;
                xK2_out := TRUE;
                xRequestStop := TRUE;
            END_IF
    
        // ══════════════════════════════════════════════════════════
        // TO_DISCONNECT: Comanda K1 off + K2 trip
        // PERMANECE 1 scan mínimo (garante log e aplicação)
        // ══════════════════════════════════════════════════════════
        E_TurnOffState.TO_DISCONNECT:
            xLedYellow := TRUE;
            xLedGreen  := FALSE;
            xLedRed    := FALSE;
    
            xK1_out := FALSE;
            xK2_out := TRUE;
    
            tonK2(IN := FALSE);   // prepara timer para TO_CONFIRM
    
            IF NOT bDisconnectDone THEN
                bDisconnectDone := TRUE;
                // Permanece neste estado por 1 scan
            ELSE
               Estado:= E_TurnOffState.TO_CONFIRM;
            END_IF
    
        // ══════════════════════════════════════════════════════════
        // TO_CONFIRM: Verifica se K2 efetivamente abriu
        // ══════════════════════════════════════════════════════════
        E_TurnOffState.TO_CONFIRM:
            xLedYellow := TRUE;
            xLedGreen  := FALSE;
            xLedRed    := FALSE;
    
            xK1_out := FALSE;
            xK2_out := TRUE;
    
            tonK2(IN := TRUE, PT := tK2Timeout);
    
            IF tonK2.Q THEN
                tonK2(IN := FALSE);
    
                IF xK2_in THEN
                    // K2 não abriu — falha grave
                    xLogEvent := TRUE;
                    eLogCode  := E_EventCode.CRIT_TURNOFF_K2_NOT_OPENED;
                    xLedRed   := TRUE;
                ELSE
                    // K2 aberto confirmado
                    xLogEvent := TRUE;
                    eLogCode  := E_EventCode.INFO_TURNOFF_K2_CONFIRMED;
                END_IF
    
               Estado := E_TurnOffState.TO_DONE;
            END_IF
    
        // ══════════════════════════════════════════════════════════
        // TO_DONE: Latch — aguarda reset manual
        // ══════════════════════════════════════════════════════════
        E_TurnOffState.TO_DONE:
            xK1_out := FALSE;
            xK2_out := TRUE;
    
            xLedGreen  := FALSE;
            xLedYellow := TRUE;
            xLedRed    := xK2_in;   // vermelho se K2 ainda fechado
    
            IF xStartResetEdge THEN
                xRequestStart := TRUE;
    
                // Rearma para próxima entrada
                Estado             := E_TurnOffState.TO_INIT;
                PrevEstado         := E_TurnOffState.TO_INIT;
                uRetry         := 0;
                bInitPulseDone := FALSE;
                bDisconnectDone := FALSE;
            END_IF
    
    END_CASE
END_FUNCTION_BLOCK
