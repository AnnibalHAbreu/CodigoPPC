(*
    FB_FailSafe — Lógica completa do estado FAIL do PPC-GD
    Responsabilidade:
      • Executar a sequência FS_INIT → FS_FORCE_ZERO → FS_VALIDATE
      • Monitorar timers normativos (15s hard-limit, 30s LPI, global)
      • Decidir transição para STOP ou READ (recuperação)
      • Encapsular TODOS os efeitos colaterais do estado FAIL

    Contrato com MainProgram:
      • MainProgram chama este FB enquanto CurrentState = FAIL
      • Ao entrar: xEnable := TRUE
      • Ao sair (transição de estado): MainProgram usa xRequestStop / xRequestRead
      • Reset de estado interno: xEnable := FALSE por pelo menos 1 ciclo

    Fluxo interno:
      FAIL_ENTRY =>  FS_INIT => FS_FORCE_ZERO =>  FS_VALIDATE
                                   |                |
                             (escrita falha)   (recuperacao OK)
                                   |                |
                              STOP (trip)      READ (retoma)
                                   |
                         (estoura retries) => STOP

    Timers normativos DIS-NOR-033:
      ton15s  : P > LPI + 10% Pnom por > 15S =>  STOP imediato
      ton30s  : P > LPI por > 30S            =>  STOP imediato
      tonGlobal: permanecia em FAIL > 120S   =>  STOP imediato
*)
FUNCTION_BLOCK FB_FailSafe
VAR_INPUT
    xEnable             : BOOL;             // TRUE = MainProgram está em estado FAIL
    xMeasDone           : BOOL;             // fbReadMeas.result = DONE
    xMeasOK             : BOOL;             // MedidorOK (dado validado)
    xCom1Done           : BOOL;             // fbWriteCOM1.Done
    xCom1Critical       : BOOL;             // fbWriteCOM1.bCritical
    xCom2Done           : BOOL;             // fbWriteCOM2.Done
    xCom2Critical       : BOOL;             // fbWriteCOM2.bCritical
    rExport_mag         : REAL;             // Magnitude de exportação atual (kW, >= 0)
    rLPI_mag            : REAL;             // Limite de exportação (kW, >= 0)
    rHardLimit_mag      : REAL;             // LPI + 10% Pnom (kW)
    uCurrentState       : E_MachineState;   // Para log de eventos
END_VAR

VAR_OUTPUT
    xRequestStop        : BOOL;             // Solicita transição → STOP
    xRequestRead        : BOOL;             // Solicita transição → READ (recuperação)
    xReqZeroSetpoints   : BOOL;             // Solicita zerar P_inv / Q_inv no MainProgram
    xReqResetPI         : BOOL;             // Solicita reset do FB_Controle
    xReqWriteCOM_Reset  : BOOL;             // Reset dos FB_WriteCom (borda de entrada em FS_FORCE_ZERO)
    xWriteEnable        : BOOL;             // Habilita chamada dos fbWriteCOM no MainProgram
    FailState           : E_FailState;      // Sub-estado atual (observabilidade IHM)
END_VAR

VAR
    // ── Sub-estado interno ────────────────────────────────────────
    iState              : E_FailState := E_FailState.FS_INIT;
    iPrevState          : E_FailState := E_FailState.FS_INIT;
    bInitDone           : BOOL := FALSE;    // Evita re-execução do FS_INIT

    // ── Timers normativos ─────────────────────────────────────────
    ton15s              : TON;              // Hard limit: P > LPI+10%Pnom por 15s
    ton30s              : TON;              // Exportação > LPI por 30s
    tonGlobal           : TON;              // Permanência máxima em FAIL (120s)
    tonRecovery         : TON;              // Estabilidade mínima antes de recuperar (10s)
    tonMeasTimeout      : TON;              // Medidor ausente por > 5s em FS_VALIDATE

    // ── Contadores de recuperação ─────────────────────────────────
    uRecoveryCycles     : UINT := 0;
    RECOVERY_CYCLES     : UINT := 10;       // Ciclos consecutivos OK para recuperar

    // ── Contador de retries de escrita ───────────────────────────
    uWriteRetries       : UINT := 0;
    MAX_WRITE_RETRIES   : UINT := 3;

    // ── Critérios de recuperação ──────────────────────────────────
    bMeasRecovered      : BOOL;
    bExportOK           : BOOL;
    bComRecovered       : BOOL;
    bAllOK              : BOOL;
    bRecoveryApproved   : BOOL;

    // ── Controle de pulsos de saída ───────────────────────────────
    bZeroSent           : BOOL := FALSE;    // Garante que xReqZeroSetpoints dura 1 ciclo
    bResetPISent        : BOOL := FALSE;    // Garante que xReqResetPI dura 1 ciclo
END_VAR

    METHOD PRIVATE _ResetAllOnRecovery : BOOL
    VAR_INPUT
    END_VAR

        
        // ════════════════════════════════════════════════════════════════════
        // MÉTODO INTERNO: Reset completo ao recuperar
        // Extrai do corpo principal para legibilidade
        // ════════════════════════════════════════════════════════════════════
            iState              := E_FailState.FS_INIT;
            bInitDone           := FALSE;
            uRecoveryCycles     := 0;
            uWriteRetries       := 0;
            ton15s(IN := FALSE);
            ton30s(IN := FALSE);
            tonGlobal(IN := FALSE);
            tonRecovery(IN := FALSE);
            tonMeasTimeout(IN := FALSE);
            GVL_Main.LedYellowOut                          := FALSE;
            GVL_Alarm.CRIT_FAIL_ENTRY             := FALSE;
            GVL_Alarm.CRIT_FAIL_WRITE_FAILED      := FALSE;
            GVL_Alarm.CRIT_FAIL_GLOBAL_TIMEOUT    := FALSE;
            FC_LogEvent(
                eCode      := E_EventCode.INFO_FAIL_RECOVERY,
                bRaised    := TRUE,
                rParam1    := rExport_mag,
                rParam2    := rLPI_mag,
                uMachState := uCurrentState
            );
    END_METHOD

    // ════════════════════════════════════════════════════════════════════
    // CORPO
    // ════════════════════════════════════════════════════════════════════
    
    // ── Limpa saídas a cada ciclo (evita saídas travadas) ────────────
    xRequestStop      := FALSE;
    xRequestRead      := FALSE;
    xReqZeroSetpoints := FALSE;
    xReqResetPI       := FALSE;
    xReqWriteCOM_Reset:= FALSE;
    xWriteEnable      := FALSE;
    
    // ── Se desabilitado: reset completo do estado interno ────────────
    IF NOT xEnable THEN
        iState            := E_FailState.FS_INIT;
        iPrevState        := E_FailState.FS_INIT;
        bInitDone         := FALSE;
        bZeroSent         := FALSE;
        bResetPISent      := FALSE;
        uRecoveryCycles   := 0;
        uWriteRetries     := 0;
        ton15s(IN := FALSE);
        ton30s(IN := FALSE);
        tonGlobal(IN := FALSE);
        tonRecovery(IN := FALSE);
        tonMeasTimeout(IN := FALSE);
        FailState         := E_FailState.FS_INIT;
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════════
    // A. TIMERS NORMATIVOS — executam SEMPRE (independente de sub-estado)
    //    Decisão é feita na cadeia IF abaixo com prioridade explícita
    // ════════════════════════════════════════════════════════════════════
    
    tonGlobal(IN := TRUE,  PT := T#120S);
    ton15s(IN := xMeasOK AND (rExport_mag > rHardLimit_mag), PT := T#15S);
    ton30s(IN := xMeasOK AND (rExport_mag > rLPI_mag),        PT := T#30S);
    
    // ════════════════════════════════════════════════════════════════════
    // B. CADEIA DE DECISÃO COM PRIORIDADE EXPLÍCITA
    //    Apenas UMA decisão prevalece por ciclo
    //    Prioridade: Global > HardLimit15s > Export30s > Sub-estados
    // ════════════════════════════════════════════════════════════════════
    
    // ── PRIORIDADE 1: Timeout global ─────────────────────────────────
    IF tonGlobal.Q THEN
        GVL_Alarm.CRIT_FAIL_GLOBAL_TIMEOUT := TRUE;
        FC_LogEvent(
            eCode      := E_EventCode.CRIT_FAIL_GLOBAL_TIMEOUT,
            bRaised    := TRUE,
            rParam1    := rExport_mag,
            rParam2    := rLPI_mag,
            uMachState := uCurrentState
        );
        tonGlobal(IN := FALSE);
        xRequestStop := TRUE;
    
    // ── PRIORIDADE 2: Hard limit 15s ─────────────────────────────────
    ELSIF ton15s.Q THEN
        GVL_Alarm.CRIT_HARDLIMIT_15S := TRUE;
        FC_LogEvent(
            eCode      := E_EventCode.CRIT_HARDLIMIT_15S,
            bRaised    := TRUE,
            rParam1    := rExport_mag,
            rParam2    := rHardLimit_mag,
            uMachState := uCurrentState
        );
        xRequestStop := TRUE;
    
    // ── PRIORIDADE 3: Exportação > LPI por 30s ───────────────────────
    ELSIF ton30s.Q THEN
        GVL_Alarm.CRIT_EXPORT_OVER_LPI_30S := TRUE;
        FC_LogEvent(
            eCode      := E_EventCode.CRIT_EXPORT_OVER_LPI_30S,
            bRaised    := TRUE,
            rParam1    := rExport_mag,
            rParam2    := rLPI_mag,
            uMachState := uCurrentState
        );
        xRequestStop := TRUE;
    
    // ── PRIORIDADE 4: Sub-estados ─────────────────────────────────────
    ELSE
    
        CASE iState OF
    
        // ────────────────────────────────────────────────────────────
        E_FailState.FS_INIT:
        // Entrada no estado FAIL: inicializa tudo uma única vez
        // ────────────────────────────────────────────────────────────
    
            GVL_Main.LedYellowOut := TRUE;
            GVL_Main.LedGreenOut  := FALSE;
    
            tonRecovery(IN := FALSE);
            tonMeasTimeout(IN := FALSE);
            uRecoveryCycles := 0;
    
            IF NOT bInitDone THEN
                // Zera setpoints: pulso de 1 ciclo para o MainProgram executar o FOR
                xReqZeroSetpoints := TRUE;
                xReqResetPI       := TRUE;
                bInitDone         := TRUE;
    
                GVL_Alarm.CRIT_FAIL_ENTRY := TRUE;
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_FAIL_ENTRY,
                    bRaised    := TRUE,
                    rParam1    := rExport_mag,
                    rParam2    := rLPI_mag,
                    uMachState := uCurrentState
                );
            END_IF
    
            iPrevState := iState;
            iState     := E_FailState.FS_FORCE_ZERO;
    
        // ────────────────────────────────────────────────────────────
        E_FailState.FS_FORCE_ZERO:
        // Envia setpoint zero para todos os inversores via Modbus
        // Permanece aqui até ambos os canais confirmarem Done
        // ────────────────────────────────────────────────────────────
    
            // Pulso de Reset apenas na primeira entrada neste sub-estado
            xReqWriteCOM_Reset := (iPrevState = E_FailState.FS_INIT);
            iPrevState         := iState;
    
            // Habilita escrita: MainProgram chamará fbWriteCOM1 e fbWriteCOM2
            xWriteEnable := TRUE;
    
            IF xCom1Done AND xCom2Done THEN
                IF xCom1Critical OR xCom2Critical THEN
                    // ❌ Escrita falhou
                    uWriteRetries := uWriteRetries + 1;
                    GVL_Alarm.CRIT_FAIL_WRITE_FAILED := TRUE;
                    FC_LogEvent(
                        eCode      := E_EventCode.CRIT_FAIL_WRITE_ZERO_FAILED,
                        bRaised    := TRUE,
                        rParam1    := TO_REAL(uWriteRetries),
                        rParam2    := 0.0,
                        uMachState := uCurrentState
                    );
    
                    IF uWriteRetries >= MAX_WRITE_RETRIES THEN
                        // Esgotou tentativas → STOP
                        FC_LogEvent(
                            eCode      := E_EventCode.CRIT_FAIL_WRITE_EXHAUSTED,
                            bRaised    := TRUE,
                            rParam1    := TO_REAL(uWriteRetries),
                            rParam2    := 0.0,
                            uMachState := uCurrentState
                        );
                        xRequestStop := TRUE;
                    ELSE
                        // Tenta novamente: volta ao início de FS_FORCE_ZERO
                        iPrevState := E_FailState.FS_INIT;  // força Reset nos COMx
                    END_IF
    
                ELSE
                    // ✅ Escrita OK — avança para validação
                    uWriteRetries := 0;
                    GVL_Alarm.CRIT_FAIL_WRITE_FAILED := FALSE;
                    iState := E_FailState.FS_VALIDATE;
                END_IF
            END_IF
    
        // ────────────────────────────────────────────────────────────
        E_FailState.FS_VALIDATE:
        // Monitora condições de recuperação
        // Precisa de RECOVERY_CYCLES ciclos consecutivos OK + 10s estável
        // ────────────────────────────────────────────────────────────
    
            bMeasRecovered := xMeasDone AND xMeasOK;
            bExportOK      := (rExport_mag <= rLPI_mag);
            bComRecovered  := (NOT xCom1Critical) AND (NOT xCom2Critical);
            bAllOK         := bMeasRecovered AND bExportOK AND bComRecovered;
    
            IF bAllOK THEN
                IF uRecoveryCycles < RECOVERY_CYCLES THEN
                    uRecoveryCycles := uRecoveryCycles + 1;
                END_IF
    
                tonRecovery(IN := TRUE, PT := T#10S);
                bRecoveryApproved := (uRecoveryCycles >= RECOVERY_CYCLES) AND tonRecovery.Q;
    
                IF bRecoveryApproved THEN
                    // ✅ RECUPERAÇÃO APROVADA — limpa e retorna ao ciclo normal
                    _ResetAllOnRecovery();
                    xRequestRead := TRUE;
                END_IF
    
            ELSE
                // ❌ Condições ainda não OK — reinicia contadores de recuperação
                uRecoveryCycles := 0;
                tonRecovery(IN := FALSE);
    
                // Watchdog: medidor ausente por > 5s → STOP
                tonMeasTimeout(IN := (NOT bMeasRecovered), PT := T#5S);
                GVL_Alarm.CRIT_MEAS_TIMEOUT_IN_FAIL := tonMeasTimeout.Q;
    
                IF tonMeasTimeout.Q THEN
                    FC_LogEvent(
                        eCode      := E_EventCode.CRIT_MEAS_TIMEOUT_IN_FAIL,
                        bRaised    := TRUE,
                        rParam1    := rExport_mag,
                        rParam2    := rLPI_mag,
                        uMachState := uCurrentState
                    );
                    tonMeasTimeout(IN := FALSE);
                    xRequestStop := TRUE;
                END_IF
            END_IF
    
        END_CASE
    
    END_IF
    
    // ── Exporta sub-estado para observabilidade da IHM ───────────────
    FailState := iState;
    
    
    
END_FUNCTION_BLOCK
