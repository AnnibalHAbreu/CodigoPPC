// ════════════════════════════════════════════════════════════════════
// FC_EpochToString — Converte UDINT epoch UTC para string legível
// ════════════════════════════════════════════════════════════════════
// Formato: 'DD/MM HH:MM:SS'
// Simplificação: usa SysTimeRtcConvertUtcToLocal + formatação manual
// Se tTimestamp = 0, retorna '-- sem RTC --'
// ════════════════════════════════════════════════════════════════════
FUNCTION FC_EpochToString : STRING(20)
VAR_INPUT
    tEpoch : UDINT;
END_VAR
VAR
    dtLocal     : DT;
    sTemp       : STRING(20);
    nDay        : UINT;
    nMonth      : UINT;
    nHour       : UINT;
    nMin        : UINT;
    nSec        : UINT;
END_VAR

    IF tEpoch = 0 THEN
        FC_EpochToString := '-- sem RTC --';
        RETURN;
    END_IF
    
    // Converte epoch UDINT para DT (DATE_AND_TIME)
    // DT no CODESYS V3 é segundos desde 01/01/1970 (mesmo que UDINT epoch)
    dtLocal := UDINT_TO_DT(tEpoch);
    
    // Extrai componentes usando funções padrão do SysTime / Util
    // Nota: a implementação exata depende das libs disponíveis no target.
    // Alternativa simples — usar DT_TO_STRING e truncar:
    sTemp := DT_TO_STRING(dtLocal);
    
    // DT_TO_STRING retorna formato 'DT#YYYY-MM-DD-HH:MM:SS'
    // Extraímos apenas 'DD/MM HH:MM:SS' (14 chars)
    FC_EpochToString := MID(sTemp, 2, 12);  // DD
    FC_EpochToString := CONCAT(FC_EpochToString, '/');
    FC_EpochToString := CONCAT(FC_EpochToString, MID(sTemp, 2, 9)); // MM
    FC_EpochToString := CONCAT(FC_EpochToString, ' ');
    FC_EpochToString := CONCAT(FC_EpochToString, MID(sTemp, 8, 15)); // HH:MM:SS
END_FUNCTION
