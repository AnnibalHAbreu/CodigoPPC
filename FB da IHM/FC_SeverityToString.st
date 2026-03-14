// ════════════════════════════════════════════════════════════════════
// FC_SeverityToString — Extrai severidade do nibble alto de E_EventCode
// ════════════════════════════════════════════════════════════════════
FUNCTION FC_SeverityToString : STRING(8)
VAR_INPUT
    eCode : E_EventCode;
END_VAR
VAR
    nHighNibble : UINT;
END_VAR

    nHighNibble := (TO_UINT(eCode) AND 16#F000);
    
    CASE nHighNibble OF
        16#1000: FC_SeverityToString := 'INFO';
        16#2000: FC_SeverityToString := 'WARN';
        16#4000: FC_SeverityToString := 'ALARM';
        16#8000: FC_SeverityToString := 'CRIT';
    ELSE
        FC_SeverityToString := '???';
    END_CASE
END_FUNCTION
