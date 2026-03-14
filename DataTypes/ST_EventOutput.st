// ════════════════════════════════════════════════════════════════════
// ST_Event — Registro individual de evento no ring buffer
// ════════════════════════════════════════════════════════════════════
TYPE ST_EventOutput :
STRUCT
	asTimestamp      : STRING(20);   // 'DD/MM HH:MM:SS'
    asMessage        : STRING(60);   // Mensagem legível
    asParam1         : STRING(12);   // Valor contexto 1
    asParam2         : STRING(12);   // Valor contexto 2
    asSeverity       : STRING(8);    // 'INFO'/'WARN'/'ALARM'/'CRIT'
    asRaised         : STRING(5);    // 'RAISE' / 'CLEAR'
    abLineValid      : BOOL;         // TRUE = linha tem dados
	asCodeHex        : STRING(8);    // ex: '16#8700'	
END_STRUCT
END_TYPE
