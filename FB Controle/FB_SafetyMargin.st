(*
    ════════════════════════════════════════════════════════════════
    FB_SafetyMargin - Margem de Segurança para Correção de TC
    ════════════════════════════════════════════════════════════════
    
    Função:
    - Aplica margem de segurança para compensar erro de TC em baixas correntes
    - Desloca setpoint para lado da importação (garante não exportar)
    
    Exemplo:
    - P_cmd = 100 kW
    - TC_Power = 329 kW
    - Margin = 3%
    - SafetyMargin = 3% × 329 = 9.87 kW
    - P_adjusted = 100 - 9.87 = 90.13 kW
    ════════════════════════════════════════════════════════════════
*)
FUNCTION_BLOCK FB_SafetyMargin
VAR_INPUT
    P_cmd_raw_kW : REAL;        // Comando sem margem
    Margin_pct : REAL;          // Percentual (ex: 3.0)
    TC_Power_kW : REAL;         // Potência do TC
END_VAR

VAR_OUTPUT
    P_cmd_adjusted_kW : REAL;   // Comando com margem
    Margin_applied_kW : REAL;   // Margem aplicada (para telemetria)
END_VAR

VAR
    SafetyMargin_kW : REAL;
END_VAR

    // ════════════════════════════════════════════════════════════════
    // IMPLEMENTAÇÃO
    // ════════════════════════════════════════════════════════════════
    // 1. Proteção: se TC não configurado, não aplica margem
    IF TC_Power_kW <= 0.0 THEN
        P_cmd_adjusted_kW := P_cmd_raw_kW;
        Margin_applied_kW := 0.0;
        RETURN;
    END_IF
    
    // 2. Calcula margem em kW
    SafetyMargin_kW := (Margin_pct / 100.0) * TC_Power_kW;
    
    // 3. Aplica margem (reduz comando)
    P_cmd_adjusted_kW := P_cmd_raw_kW - SafetyMargin_kW;
    
    // 4. Limita para não ficar negativo
    IF P_cmd_adjusted_kW < 0.0 THEN
        P_cmd_adjusted_kW := 0.0;
    END_IF
    
    // 5. Armazena margem aplicada (para HMI)
    Margin_applied_kW := SafetyMargin_kW;
END_FUNCTION_BLOCK
