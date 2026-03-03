(*
    FB_DroopP - Droop para Potência Ativa
    Gera um comando base proporcional ao erro de potência.
    Uso: antes do PI (PI corrige residual).
*)
FUNCTION_BLOCK FB_DroopP
VAR_INPUT
    Enable        : BOOL;   // Habilita droop
    bReset        : BOOL;   // Reset do droop
    Error_kW      : REAL;   // Erro (Setpoint - Feedback)
    K_droop       : REAL;   // Ganho droop (kW/kW)
    Deadband_kW   : REAL;   // Zona morta
    P_max_kW      : REAL;   // Limite absoluto do droop (kW)
END_VAR

VAR_OUTPUT
    P_droop_kW    : REAL;   // Saída do droop (kW)
END_VAR

VAR
    P_cmd : REAL;
    erro  : REAL;
END_VAR

    // ──────────────────────────────────��───────────────────────────
    // Reset
    // ──────────────────────────────────────────────────────────────
    IF bReset THEN
        P_droop_kW := 0.0;
        RETURN;
    END_IF
    
    // ──────────────────────────────────────────────────────────────
    // Lógica do droop
    // ──────────────────────────────────────────────────────────────
    IF NOT Enable THEN
        P_droop_kW := 0.0;
        RETURN;
    END_IF
    
    // Aplica deadband ao erro
    erro := Error_kW;
    IF ABS(erro) < Deadband_kW THEN
        erro := 0.0;
    END_IF
    
    P_cmd := K_droop * erro;
    
    // Limite absoluto
    IF P_cmd > P_max_kW THEN
        P_cmd := P_max_kW;
    ELSIF P_cmd < -P_max_kW THEN
        P_cmd := -P_max_kW;
    END_IF
    
    P_droop_kW := P_cmd;
END_FUNCTION_BLOCK
