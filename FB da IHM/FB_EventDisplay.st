// ════════════════════════════════════════════════════════════════════
// FB_EventDisplay — Prepara eventos do ring buffer para exibição na IHM
// ════════════════════════════════════════════════════════════════════
// A IHM não navega o ring buffer diretamente. Este FB expõe
// N linhas "flat" prontas para bind em Text Fields.
//
// Suporta paginação: nPageOffset controla qual "página" exibir.
//   Página 0 = eventos mais recentes
//   Página 1 = próximos DISPLAY_LINES eventos, etc.
//
// Chamado sob demanda (quando operador abre a tela de histórico),
// NÃO a cada ciclo.
// ════════════════════════════════════════════════════════════════════
FUNCTION_BLOCK FB_EventDisplay

VAR_INPUT
    pEventLog       : REFERENCE TO FB_EventLog;     // Referência ao ring buffer
    bRefresh        : BOOL;                         // Pulso = atualiza dados
    nPageOffset     : UINT := 0;                    // Página (0 = mais recente)
END_VAR

VAR_OUTPUT
    nTotalEvents    : UINT;                         // Total de eventos no buffer
    nTotalPages     : UINT;                         // Total de páginas disponíveis
    nCurrentPage    : UINT;                         // Página atual (0-based)
END_VAR

VAR CONSTANT
    DISPLAY_LINES   : UINT := 10;                   // Linhas visíveis na tela
END_VAR

VAR
    // ── Dados "flat" para a IHM (cada linha = 1 evento) ──
	(* 
	ST_EventOutput
    asTimestamp      : STRING(20);   // 'DD/MM HH:MM:SS'
    asMessage        : STRING(60);   // Mensagem legível
    asParam1         : STRING(12);   // Valor contexto 1
    asParam2         : STRING(12);   // Valor contexto 2
    asSeverity       : STRING(8);    // 'INFO'/'WARN'/'ALARM'/'CRIT'
    asRaised         : STRING(5);    // 'RAISE' / 'CLEAR'
    abLineValid      : BOOL;         // TRUE = linha tem dados
	asCodeHex        : STRING(8);    // ex: '16#8700'
	*)

    Display     	: ARRAY[0..9] OF ST_EventOutput;
	
    // Auxiliares
    i               : UINT;
    nStartIdx       : UINT;
    stEvt           : ST_EventEntry;
    bOK             : BOOL;
    rTrigRefresh    : R_TRIG;
END_VAR

    // ════════════════════════════════════════════════════════════════════
    // Corpo do FB_EventDisplay — executa quando bRefresh tem borda de subida
    // ════════════════════════════════════════════════════════════════════
    rTrigRefresh(CLK := bRefresh);
    
    IF rTrigRefresh.Q THEN
    
        // Total de eventos e páginas
        nTotalEvents := pEventLog.nCount;
        IF nTotalEvents > 0 THEN
            nTotalPages := ((nTotalEvents - 1) / DISPLAY_LINES) + 1;
        ELSE
            nTotalPages := 0;
        END_IF
    
        // Clamp página
        IF nPageOffset >= nTotalPages THEN
            nPageOffset := 0;
        END_IF
        nCurrentPage := nPageOffset;
    
        // Índice inicial no ring buffer (reverso)
        nStartIdx := nPageOffset * DISPLAY_LINES;
    
        // Preencher linhas
        FOR i := 0 TO (DISPLAY_LINES - 1) DO
    
            bOK := pEventLog.GetEvent(
                nReverseIndex := nStartIdx + i,
                stOut => stEvt
            );
    
            IF bOK THEN
                Display[i].abLineValid := TRUE;
    
                // Timestamp → string legível
                Display[i].asTimestamp := FC_EpochToString(stEvt.tTimestamp);
    
                // Código → mensagem
                Display[i].asMessage := FC_EventCodeToString(stEvt.eCode);
    
                // Severidade (extraída do nibble alto do código)
                Display[i].asSeverity := FC_SeverityToString(stEvt.eCode);
    
                // Raise/Clear
                IF stEvt.bRaised THEN
                    Display[i].asRaised := 'RAISE';
                ELSE
                    Display[i].asRaised := 'CLEAR';
                END_IF
    
                // Parâmetros numéricos formatados
                Display[i].asParam1 := REAL_TO_STRING(stEvt.rParam1);
                Display[i].asParam2 := REAL_TO_STRING(stEvt.rParam2);
    			Display[i].asCodeHex := FC_UIntToHex16Sharp(TO_UINT(stEvt.eCode));
            ELSE
                // Linha vazia
                Display[i].abLineValid  := FALSE;
                Display[i].asTimestamp  := '';
                Display[i].asMessage    := '';
                Display[i].asSeverity   := '';
                Display[i].asRaised     := '';
                Display[i].asParam1     := '';
                Display[i].asParam2		:= '';
    			Display[i].asCodeHex	:= '';
            END_IF
    
        END_FOR
    
    END_IF
END_FUNCTION_BLOCK
