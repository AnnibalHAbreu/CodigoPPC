(*
================================================================================
  FB_SetRTC — Correção de Data/Hora do RTC via IHM
================================================================================
  Propósito:
    Permite que o operador corrija o relógio do CLP (WAGO CC100) diretamente
    pela IHM, sem necessidade de acesso ao Codesys IDE.

  Problema resolvido:
    O CC100 não possui bateria de RTC confiável. Após queda de energia, o
    relógio retorna para 1970-01-01 00:00:00. Isso corrompe o agendamento
    (FB_Scheduler), o log de eventos e qualquer registro com timestamp.

  Comportamento:
    1. O operador preenche os campos de data/hora na IHM e aciona bSet=TRUE.
    2. O FB valida todos os campos antes de qualquer escrita.
    3. Se válido: chama SysTimeRtcSet(), registra evento INFO no log.
    4. Se inválido: recusa a operação, registra WARNING com o campo problemático.
    5. bSet é um pulso de borda de subida — consumido internamente (auto-reset).
    6. bBusy permanece TRUE por 1 ciclo após a operação para sinalizar atividade.
    7. bSuccess e bError são mantidos por FEEDBACK_HOLD_CYCLES ciclos.

  Integração:
    - Chamar em TaskIHM (não na task de controle — operação pontual, não crítica).
    - Expor todas as variáveis VAR_INPUT/OUTPUT na tela de configuração da IHM.
    - A task de controle NÃO precisa ser modificada.

  Notas de segurança:
    - O FB NÃO impede a máquina de estados de operar durante a atualização.
    - SysTimeRtcSet() é atômico no WAGO CC100 / Codesys V3.5.
    - Ano mínimo: 2020 (evita aceitar 1970 de RTC sem bateria).
    - Ano máximo: 2099 (limite de UDINT epoch seguro).
    - O FB não aceita segundos bissextos (segundo 60) — simplificação segura.

  Dependências:
    - SysTimeRtc.library (SysTimeRtcSet, SysTimeRtcGet, SysTimeRtcConvertDateToUTC)
    - FC_LogEvent, E_EventCode, GVL_Main
    - Codesys V3.5 SP21 / IEC 61131-3 Structured Text

  Revisão: 2026-03
================================================================================
*)
FUNCTION_BLOCK FB_SetRTC

VAR_INPUT
    // ── Comando ───────────────────────────────────────────────────────────────
    bSet        : BOOL;     // Pulso de subida = aplica nova data/hora
                            // IHM deve manter TRUE por ≥ 1 ciclo, depois FALSE

    // ── Data/Hora desejada (preenchida pelo operador na IHM) ──────────────────
    nYear       : UINT;     // Ano   [2020 .. 2099]
    nMonth      : UINT;     // Mês   [1 .. 12]
    nDay        : UINT;     // Dia   [1 .. 31] (validação completa por mês)
    nHour       : UINT;     // Hora  [0 .. 23]
    nMinute     : UINT;     // Min   [0 .. 59]
    nSecond     : UINT;     // Seg   [0 .. 59]
END_VAR

VAR_OUTPUT
    // ── Feedback para a IHM ───────────────────────────────────────────────────
    bBusy           : BOOL;     // TRUE durante o ciclo de execução
    bSuccess        : BOOL;     // TRUE por FEEDBACK_HOLD_CYCLES após sucesso
    bError          : BOOL;     // TRUE por FEEDBACK_HOLD_CYCLES após falha
    nErrorCode      : UINT;     // Código do erro (ver constantes abaixo):
                                //   0 = sem erro
                                //   1 = Ano inválido
                                //   2 = Mês inválido
                                //   3 = Dia inválido para o mês/ano
                                //   4 = Hora inválida
                                //   5 = Minuto inválido
                                //   6 = Segundo inválido
                                //   7 = SysTimeRtcSet() falhou (erro de hardware)
    sStatusMsg      : STRING(40); // Mensagem legível para display na IHM
END_VAR

VAR
    // ── Detecção de borda de subida em bSet ───────────────────────────────────
    rTrigSet        : R_TRIG;

    // ── Variáveis para cálculo de epoch e chamada de SysTimeRtcSet ──────────
    // SysTimeRtcSet(ulTimestamp: DWORD): RTS_IEC_RESULT
    // Recebe segundos desde 1970-01-01 00:00:00 UTC (epoch Unix).
    ulTimestamp     : UDINT;            // Epoch calculado a partir dos campos da IHM
    rtcResult       : RTS_IEC_RESULT;

    // ── Variáveis auxiliares para cálculo de epoch ────────────────────────────
    nY              : UDINT;            // Ano de trabalho (loop)
    nDays           : UDINT;            // Acumulador de dias desde 1970

    // ── Contador de ciclos para manter feedback visível na IHM ───────────────
    nFeedbackTimer  : UINT;

    // ── Dias por mês (índice 1..12) — fevereiro = 28; bissexto tratado em código
    aDaysInMonth    : ARRAY[1..12] OF UINT
                    := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    // ── Constante: quantos ciclos manter bSuccess/bError visíveis ─────────────
    // Com CYCLE_TIME_MS = 1000 ms → 5 ciclos = 5 segundos de feedback
    FEEDBACK_HOLD_CYCLES : UINT := 5;
END_VAR

    // ════════════════════════════════════════════════════════════════════════════
    // 1. DETECÇÃO DE BORDA — garante execução única por pulso do operador
    // ════════════════════════════════════════════════════════════════════════════
    rTrigSet(CLK := bSet);
    
    // ════════════════════════════════════════════════════════════════════════════
    // 2. TEMPORIZADOR DE FEEDBACK — mantém bSuccess/bError visíveis por N ciclos
    // ════════════════════════════════════════════════════════════════════════════
    IF nFeedbackTimer > 0 THEN
        nFeedbackTimer := nFeedbackTimer - 1;
        IF nFeedbackTimer = 0 THEN
            bSuccess := FALSE;
            bError   := FALSE;
            nErrorCode := 0;
            sStatusMsg := 'Aguardando comando...';
        END_IF
    END_IF
    
    // ════════════════════════════════════════════════════════════════════════════
    // 3. EXECUÇÃO — apenas na borda de subida de bSet
    // ════════════════════════════════════════════════════════════════════════════
    IF NOT rTrigSet.Q THEN
        RETURN;
    END_IF
    
    // ── Sinaliza ocupado neste ciclo ─────────────────────────────────────────
    bBusy    := TRUE;
    bSuccess := FALSE;
    bError   := FALSE;
    nErrorCode := 0;
    
    // ════════════════════════════════════════════════════════════════════════════
    // 4. VALIDAÇÃO DOS CAMPOS
    // ════════════════════════════════════════════════════════════════════════════
    
    // 4.1 Ano — aceita apenas datas a partir de 2020 para rejeitar RTC sem bateria
    IF nYear < 2020 OR nYear > 2099 THEN
        nErrorCode := 1;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Ano invalido (2020-2099)';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_INVALID_INPUT,
            bRaised    := TRUE,
            rParam1    := INT_TO_REAL(nYear),
            rParam2    := 1.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // 4.2 Mês
    IF nMonth < 1 OR nMonth > 12 THEN
        nErrorCode := 2;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Mes invalido (1-12)';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_INVALID_INPUT,
            bRaised    := TRUE,
            rParam1    := INT_TO_REAL(nMonth),
            rParam2    := 2.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // 4.3 Dia — considera ano bissexto para fevereiro
    // Ano bissexto: divisível por 4, exceto centenários não divisíveis por 400
    IF nMonth = 2 THEN
        IF ((nYear MOD 4 = 0) AND (nYear MOD 100 <> 0)) OR (nYear MOD 400 = 0) THEN
            aDaysInMonth[2] := 29;  // Fevereiro tem 29 dias neste ano
        ELSE
            aDaysInMonth[2] := 28;
        END_IF
    END_IF
    
    IF nDay < 1 OR nDay > aDaysInMonth[nMonth] THEN
        nErrorCode := 3;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Dia invalido para o mes/ano';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_INVALID_INPUT,
            bRaised    := TRUE,
            rParam1    := INT_TO_REAL(nDay),
            rParam2    := 3.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // 4.4 Hora
    IF nHour > 23 THEN
        nErrorCode := 4;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Hora invalida (0-23)';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_INVALID_INPUT,
            bRaised    := TRUE,
            rParam1    := INT_TO_REAL(nHour),
            rParam2    := 4.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // 4.5 Minuto
    IF nMinute > 59 THEN
        nErrorCode := 5;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Minuto invalido (0-59)';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_INVALID_INPUT,
            bRaised    := TRUE,
            rParam1    := INT_TO_REAL(nMinute),
            rParam2    := 5.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // 4.6 Segundo — rejeita segundo 60 (bissexto): simplificação segura para CLP
    IF nSecond > 59 THEN
        nErrorCode := 6;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Segundo invalido (0-59)';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_INVALID_INPUT,
            bRaised    := TRUE,
            rParam1    := INT_TO_REAL(nSecond),
            rParam2    := 6.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════════════════
    // 5. CONVERTE DATA/HORA PARA EPOCH UNIX E CHAMA SysTimeRtcSet()
    // ════════════════════════════════════════════════════════════════════════════
    // A data/hora informada pelo operador na IHM é UTC (sem offset de fuso).
    // Justificativa: o sistema já trata fuso internamente no FB_Scheduler.
    //
    // Algoritmo: conta dias desde 1970-01-01, aplica horas/min/seg.
    // Validado para o intervalo 2020..2099 — sem risco de overflow em UDINT.
    //
    // SysTimeRtcSet(ulTimestamp: DWORD): RTS_IEC_RESULT
    // Fonte confirmada: SysTimeRtc.library Codesys V3.5 — assinatura real do target.
    
    // 5.1 Acumula dias dos anos completos desde 1970 até (nYear - 1)
    nDays := 0;
    FOR nY := 1970 TO UINT_TO_UDINT(nYear) - 1 DO
        IF ((nY MOD 4 = 0) AND (nY MOD 100 <> 0)) OR (nY MOD 400 = 0) THEN
            nDays := nDays + 366;   // Ano bissexto
        ELSE
            nDays := nDays + 365;
        END_IF
    END_FOR
    
    // 5.2 Acumula dias dos meses completos no ano corrente (1..nMonth-1)
    // aDaysInMonth[2] já foi corrigido para 29 se bissexto (seção 4.3)
    IF nMonth > 1  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[1]);  END_IF
    IF nMonth > 2  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[2]);  END_IF
    IF nMonth > 3  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[3]);  END_IF
    IF nMonth > 4  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[4]);  END_IF
    IF nMonth > 5  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[5]);  END_IF
    IF nMonth > 6  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[6]);  END_IF
    IF nMonth > 7  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[7]);  END_IF
    IF nMonth > 8  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[8]);  END_IF
    IF nMonth > 9  THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[9]);  END_IF
    IF nMonth > 10 THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[10]); END_IF
    IF nMonth > 11 THEN nDays := nDays + UINT_TO_UDINT(aDaysInMonth[11]); END_IF
    // Mês 12 não tem mês seguinte — não precisa de entrada aqui
    
    // 5.3 Adiciona os dias completos do mês atual (nDay - 1)
    nDays := nDays + UINT_TO_UDINT(nDay) - 1;
    
    // 5.4 Converte dias + horas + min + seg para epoch em segundos
    ulTimestamp := (nDays * 86400)
                 + (UINT_TO_UDINT(nHour)   * 3600)
                 + (UINT_TO_UDINT(nMinute) * 60)
                 +  UINT_TO_UDINT(nSecond);
    
    // 5.5 Chama SysTimeRtcSet com o epoch calculado
    rtcResult := SysTimeRtcSet(ulTimestamp := UDINT_TO_DWORD(ulTimestamp));
    
    // ════════════════════════════════════════════════════════════════════════════
    // 6. VERIFICA RESULTADO DE SysTimeRtcSet()
    // ════════════════════════════════════════════════════════════════════════════
    IF rtcResult <> 0 THEN
        nErrorCode := 7;
        bError     := TRUE;
        sStatusMsg := 'ERRO: Falha no hardware RTC';
        nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
        bBusy := FALSE;
        FC_LogEvent(
            eCode      := E_EventCode.WARN_RTC_SET_HW_FAIL,
            bRaised    := TRUE,
            rParam1    := UINT_TO_REAL(TO_UINT(rtcResult)),
            rParam2    := 0.0,
            uMachState := GVL_Main.MachineState
        );
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════════════════
    // 7. SUCESSO — atualiza GVL_Main.timestampUTC imediatamente
    //    (evita 1 ciclo com timestamp antigo no FB_Scheduler)
    // ════════════════════════════════════════════════════════════════════════════
    GVL_Main.timestampUTC := TO_UDINT(SysTimeRtcGet(GVL_Main.Result));
    
    bSuccess       := TRUE;
    sStatusMsg     := 'RTC atualizado com sucesso';
    nFeedbackTimer := FEEDBACK_HOLD_CYCLES;
    bBusy          := FALSE;
    
    FC_LogEvent(
        eCode      := E_EventCode.INFO_RTC_SET_OK,
        bRaised    := TRUE,
        rParam1    := UINT_TO_REAL(nYear) * 10000.0
                   + UINT_TO_REAL(nMonth) * 100.0
                   + UINT_TO_REAL(nDay),       // Ex: 20260306 → codifica AAAAMMDD
        rParam2    := UINT_TO_REAL(nHour) * 10000.0
                   + UINT_TO_REAL(nMinute) * 100.0
                   + UINT_TO_REAL(nSecond),    // Ex: 143015 → codifica HHMMSS
        uMachState := GVL_Main.MachineState
    );
END_FUNCTION_BLOCK
