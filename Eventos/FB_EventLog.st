// ════════════════════════════════════════════════════════════════════
// FB_EventLog — Buffer rotativo de eventos em NVRAM
// ════════════════════════════════════════════════════════════════════
// Plataforma: WAGO CC100 / CODESYS V3.5 SP21 Patch 4
//
// RESPONSABILIDADES:
//   1. Armazenar eventos em ring buffer RETAIN (sobrevive a power-cycle)
//   2. Limitar a 1 escrita por chamada (proteção de NVRAM)
//   3. Fornecer último evento e contadores para HMI
//   4. Permitir leitura indexada para exportação/diagnóstico
//
// GARANTIAS:
//   - Nunca estoura array (índice clamped por MOD)
//   - Nunca aloca memória dinâmica
//   - Tempo de execução O(1) por chamada (sem loops)
//   - Não usa STRING em runtime
//
// USO:
//   fbEventLog.LogEvent(
//       eCode      := E_EventCode.CRIT_HARD_LIMIT_15S,
//       bRaised    := TRUE,
//       rParam1    := Global.Pt,
//       rParam2    := REAL#-500.0,   // limite violado
//       uMachState := UINT_TO_UINT(MachineState)
//   );
// ════════════════════════════════════════════════════════════════════
FUNCTION_BLOCK FB_EventLog
VAR RETAIN
    // ── Ring buffer persistente ──
    aBuffer         : ARRAY[0..(GVL_Log.MAX_EVENT_ENTRIES - 1)] OF ST_EventEntry;
    nHead           : UINT := 0;            // Próxima posição de escrita
    bWrapped        : BOOL := FALSE;        // TRUE = buffer já deu pelo menos uma volta completa
    nTotalLogged    : UDINT := 0;           // Contador total desde último factory reset (para telemetria)
END_VAR
VAR
    // ── Saídas para HMI / lógica externa (recalculadas a cada LogEvent) ──
    stLastEvent     : ST_EventEntry;        // Cópia do último evento registrado
    nCount          : UINT := 0;            // Quantas entradas válidas existem no buffer
    bOverflow       : BOOL := FALSE;        // Sinaliza que eventos antigos foram sobrescritos
END_VAR

    // ════════════════════════════════════════════════════════════════════
    // METHOD LogEvent — Insere um evento no ring buffer
    // ════════════════════════════════════════════════════════════════════
    // Complexidade: O(1). Uma escrita de struct + incremento de ponteiro.
    // Pode ser chamado de qualquer FB (ErrorManager, MainProgram, etc.)
    //
    // IMPORTANTE: Não chame mais de ~5 vezes por ciclo de scan (1s).
    // Em cascata de falhas, o caller deve agregar — ex.: registrar
    // apenas o primeiro erro de range por ciclo, não um por fase.
    // ════════════════════════════════════════════════════════════════════
    METHOD LogEvent
    VAR_INPUT
        eCode           : E_EventCode;      // Código do evento
        bRaised         : BOOL;             // TRUE = raise, FALSE = clear
        rParam1         : REAL := 0.0;      // Contexto #1 (opcional)
        rParam2         : REAL := 0.0;      // Contexto #2 (opcional)
        uMachState      : UINT := 0;        // Estado da máquina (opcional)
    END_VAR
    VAR
        tNow            : UDINT;
        result          : RTS_IEC_RESULT;
    END_VAR

        // ── 1. Obter timestamp ──
        // SysTimeRtcGet retorna epoch UTC em segundos.
        // Se RTC falhar (result <> 0), registra timestamp = 0.
        // O evento AINDA É REGISTRADO — melhor ter evento sem hora
        // do que perder evento crítico por falha de RTC.
        
        tNow := SysTimeRtcGet(result);
        IF result <> 0 THEN
            tNow := 0;  // Sinaliza "RTC indisponível" — não descarta o evento
        END_IF
        
        // ── 2. Escrever no buffer ──
        // nHead já é a posição correta (calculada no final do último LogEvent)
        aBuffer[nHead].tTimestamp   := tNow;
        aBuffer[nHead].eCode        := eCode;
        aBuffer[nHead].bRaised      := bRaised;
        aBuffer[nHead].rParam1      := rParam1;
        aBuffer[nHead].rParam2      := rParam2;
        aBuffer[nHead].uMachState   := uMachState;
        
        // ── 3. Atualizar cópia do último evento (para HMI) ──
        stLastEvent := aBuffer[nHead];
        
        // ── 4. Avançar ponteiro circular ──
        nHead := (nHead + 1) MOD GVL_Log.MAX_EVENT_ENTRIES;
        
        // ── 5. Detectar wrap-around ──
        IF nHead = 0 THEN
            bWrapped := TRUE;
        END_IF
        
        // ── 6. Atualizar contadores ──
        nTotalLogged := nTotalLogged + 1;
        
        // nCount = quantas entradas válidas existem
        IF bWrapped THEN
            nCount := GVL_Log.MAX_EVENT_ENTRIES;
            bOverflow := TRUE;
        ELSE
            nCount := nHead;    // Antes do wrap, nHead = número de entradas escritas
            bOverflow := FALSE;
        END_IF
    END_METHOD

    // ════════════════════════════════════════════════════════════════════
    // METHOD GetEvent — Lê evento por índice reverso (0 = mais recente)
    // ════════════════════════════════════════════════════════════════════
    // Para HMI: exibe os últimos N eventos em ordem cronológica reversa.
    // Para exportação: itera de 0 a nCount-1.
    //
    // Retorna TRUE se o índice é válido, FALSE se fora do range.
    // Quando retorna FALSE, stOut fica zerado (não retorna lixo).
    // ════════════════════════════════════════════════════════════════════
    METHOD GetEvent : BOOL
    VAR_INPUT
        nReverseIndex   : UINT;     // 0 = mais recente, 1 = anterior, ...
    END_VAR
    VAR_OUTPUT
        stOut           : ST_EventEntry;
    END_VAR
    VAR
        nActualIdx      : UINT;
        nTemp           : INT;
    END_VAR

        // Validação de range
        IF nReverseIndex >= nCount THEN
            // Índice fora do range — zera saída e retorna FALSE
            stOut.tTimestamp     := 0;
            stOut.eCode          := E_EventCode.EVT_NONE;
            stOut.bRaised        := FALSE;
            stOut.rParam1        := 0.0;
            stOut.rParam2        := 0.0;
            stOut.uMachState     := 0;
            GetEvent := FALSE;
            RETURN;
        END_IF
        
        // Calcula índice real no buffer circular
        // nHead aponta para a PRÓXIMA posição de escrita.
        // Último escrito = nHead - 1.
        // Índice reverso N = nHead - 1 - N (com wrap-around).
        nTemp := UINT_TO_INT(nHead) - 1 - UINT_TO_INT(nReverseIndex);
        IF nTemp < 0 THEN
            nTemp := nTemp + UINT_TO_INT(GVL_Log.MAX_EVENT_ENTRIES);
        END_IF
        nActualIdx := INT_TO_UINT(nTemp);
        
        stOut := aBuffer[nActualIdx];
        GetEvent := TRUE;
    END_METHOD

    METHOD Clear
    VAR
        i : UINT;
    END_VAR

        FOR i := 0 TO (GVL_Log.MAX_EVENT_ENTRIES - 1) DO
            aBuffer[i].tTimestamp   := 0;
            aBuffer[i].eCode        := E_EventCode.EVT_NONE;
            aBuffer[i].bRaised      := FALSE;
            aBuffer[i].rParam1      := 0.0;
            aBuffer[i].rParam2      := 0.0;
            aBuffer[i].uMachState   := 0;
        END_FOR
        
        nHead := 0;
        bWrapped := FALSE;
        nTotalLogged := 0;
        nCount := 0;
        bOverflow := FALSE;
        
        // Registra o próprio clear como primeiro evento do buffer limpo
        // (para rastreabilidade — saber que houve reset intencional)
        LogEvent(
            eCode       := E_EventCode.INFO_STARTUP_BEGIN,  // Reutiliza como "system reset"
            bRaised     := TRUE,
            rParam1     := 0.0,
            rParam2     := 0.0,
            uMachState  := 0
        );
    END_METHOD


END_FUNCTION_BLOCK
