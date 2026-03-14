// ════════════════════════════════════════════════════════════════════
// FC_UIntToHex16Sharp — Formata UINT como '16#XXXX' (4 nibbles)
// Ex.: 16#8700 -> '16#8700'
// tentar usar UINT_TO_HEXSTR se o CODESYS aceitar
// ════════════════════════════════════════════════════════════════════
FUNCTION FC_UIntToHex16Sharp : STRING(7)
VAR_INPUT
    uValue : UINT;
END_VAR
VAR
    aHex   : STRING(16) := '0123456789ABCDEF';
    n0, n1, n2, n3 : UINT;
    sOut : STRING(7);
END_VAR

    n3 := (uValue AND 16#000F);
    n2 := (SHR(uValue, 4)  AND 16#000F);
    n1 := (SHR(uValue, 8)  AND 16#000F);
    n0 := (SHR(uValue, 12) AND 16#000F);
    
    // Monta '16#' + 4 dígitos
    sOut := '16#';
    sOut := CONCAT(sOut, MID(aHex, TO_INT(n0) + 1, 1));
    sOut := CONCAT(sOut, MID(aHex, TO_INT(n1) + 1, 1));
    sOut := CONCAT(sOut, MID(aHex, TO_INT(n2) + 1, 1));
    sOut := CONCAT(sOut, MID(aHex, TO_INT(n3) + 1, 1));
    
    FC_UIntToHex16Sharp := sOut;
END_FUNCTION
