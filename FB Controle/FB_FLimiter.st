(*
    FB_FLimiter - Limitador por Fase
    
    Função:
    - Verifica se o comando causaria EXPORTAÇÃO excessiva em alguma fase
    - Se fase está IMPORTANDO: ignora (não há problema)
    - Se fase está EXPORTANDO: verifica se comando excederia limite
    
    Lógica:
    1. Calcula P futuro por fase = P_atual + (P_cmd / 3)
    2. Para cada fase EXPORTANDO (P < 0):
       - Verifica se P_futuro < P_phase_limit (mais exportação que permitido)
       - Se sim, calcula comando máximo para essa fase
    3. Usa o MENOR comando máximo entre as fases
    
    Convenção de sinais:
    - P > 0: Importação
    - P < 0: Exportação
    - MaxExportLimit: VALOR POSITIVO na agenda (ex: 90 kW)
    - P_phase_limit: NEGATIVO internamente (ex: -30 kW)
	    
    Exemplo:
    - Agenda: MaxExportLimit = 90 kW (sem sinal)
    - Internamente: P_phase_limit = -90/3 = -30 kW por fase
    - Se Pa = -25 kW (exportando 25 kW)
    - Se P_cmd = -18 kW (quer aumentar exportação)
    - P_future_A = -25 + (-18/3) = -31 kW → EXCEDE -30 kW → LIMITA
*)

FUNCTION_BLOCK FB_FLimiter
VAR_INPUT
    P_cmd_in : REAL;                // Comando de P calculado pelo PI (kW)
    PowerMode : UINT;               // 0=Total, 1=Por fase, 2=Ambos
END_VAR

VAR_OUTPUT
    P_cmd_out : REAL;               // Comando de P limitado por fase (kW)
    bPhase_limited : BOOL;          // TRUE = alguma fase limitou
	sLimited_phase : STRING;        // Qual fase limitou: 'A', 'B', 'C', 'AB', etc.
END_VAR

VAR
    P_cmd_per_phase : REAL;         // Comando adicional por fase (kW)
    P_future_A : REAL;              // P futuro na fase A após aplicar comando (kW)
    P_future_B : REAL;              // P futuro na fase B após aplicar comando (kW)
    P_future_C : REAL;              // P futuro na fase C após aplicar comando (kW)
    P_phase_limit : REAL;           // Limite de exportação por fase (kW negativo)
    P_max_cmd_A : REAL;             // Comando máximo permitido para fase A (kW)
    P_max_cmd_B : REAL;             // Comando máximo permitido para fase B (kW)
    P_max_cmd_C : REAL;             // Comando máximo permitido para fase C (kW)
    P_max_cmd_total : REAL;         // Comando máximo total permitido (kW)
	NO_LIMIT : REAL;                // Constante para "sem limite"
    bLimitA : BOOL;                 // Fase A está limitando
    bLimitB : BOOL;                 // Fase B está limitando
    bLimitC : BOOL;                 // Fase C está limitando
END_VAR

    // Comando adicional por fase (distribuído equilibradamente)
    P_cmd_per_phase := P_cmd_in / 3.0;
    
    // Limite de exportação por fase
    // Se MaxExportLimit = -90 kW, então por fase = -30 kW
    P_phase_limit := -ABS(GVL_Main.MaxExportLimit) / 3.0;
    
    // ════════════════════════════════════════════════════════════════
    // ════════════════════════════════════════════════════════════════
    // Inicialização
    // ════════════════════════════════════════════════════════════════
    NO_LIMIT := GVL_Main.InstalledPower * 10.0;  // Valor grande, mas realista
    sLimited_phase := '';
    bLimitA := FALSE;
    bLimitB := FALSE;
    bLimitC := FALSE;
    
    // ════════════════════════════════════════════════════════════════
    // Se PowerMode = 0, não verifica fase
    // ════════════════════════════════════════════════════════════════
    IF PowerMode = 0 THEN
        P_cmd_out := P_cmd_in;
        bPhase_limited := FALSE;
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Proteção: Se InstalledPower não configurado
    // ════════════════════════════════════════════════════════════════
    IF GVL_Main.InstalledPower <= 0.0 THEN
        P_cmd_out := 0.0;
        bPhase_limited := TRUE;
        sLimited_phase := 'ERROR: InstalledPower=0';
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Calcula P futuro em cada fase após aplicar comando
    // ════════════════════════════════════════════════════════════════
    P_future_A := GVL_Main.Pa + P_cmd_per_phase;
    P_future_B := GVL_Main.Pb + P_cmd_per_phase;
    P_future_C := GVL_Main.Pc + P_cmd_per_phase;
    
    // ════════════════════════════════════════════════════════════════
    // Verifica FASE A
    // ════════════════════════════════════════════════════════════════
    IF P_future_A < 0.0 THEN
        // Fase A estará EXPORTANDO após aplicar comando
        
        IF P_future_A < P_phase_limit THEN
            // Excederia o limite de exportação!
            // Calcula quanto PODE aumentar exportação sem exceder:
            // P_max_per_phase = P_limit - P_atual
            // P_max_total = P_max_per_phase * 3
            P_max_cmd_A := (P_phase_limit - GVL_Main.Pa) * 3.0;
            bLimitA := TRUE;
        ELSE
            // Dentro do limite: sem restrição
            P_max_cmd_A := NO_LIMIT;
        END_IF
        
    ELSE
        // Fase A estará IMPORTANDO: sem problema
        P_max_cmd_A := NO_LIMIT;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Verifica FASE B
    // ════════════════════════════════════════════════════════════════
    IF P_future_B < 0.0 THEN
        // Fase B estará EXPORTANDO
        
        IF P_future_B < P_phase_limit THEN
            P_max_cmd_B := (P_phase_limit - GVL_Main.Pb) * 3.0;
            bLimitB := TRUE;
        ELSE
            P_max_cmd_B := NO_LIMIT;
        END_IF
        
    ELSE
        // Fase B estará IMPORTANDO
        P_max_cmd_B := NO_LIMIT;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Verifica FASE C
    // ════════════════════════════════════════════════════════════════
    IF P_future_C < 0.0 THEN
        // Fase C estará EXPORTANDO
        
        IF P_future_C < P_phase_limit THEN
            P_max_cmd_C := (P_phase_limit - GVL_Main.Pc) * 3.0;
            bLimitC := TRUE;
        ELSE
            P_max_cmd_C := NO_LIMIT;
        END_IF
        
    ELSE
        // Fase C estará IMPORTANDO
        P_max_cmd_C := NO_LIMIT;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Aplica o MENOR limite (fase mais restritiva)
    // ════════════════════════════════════════════════════════════════
    P_max_cmd_total := MIN(P_max_cmd_A, MIN(P_max_cmd_B, P_max_cmd_C));
    
    // ════════════════════════════════════════════════════════════════
    // Verifica se houve limitação
    // ════════════════════════════════════════════════════════════════
    IF P_cmd_in > P_max_cmd_total THEN
        P_cmd_out := P_max_cmd_total;
        bPhase_limited := TRUE;
        
        // Identifica qual(is) fase(s) limitou
        IF bLimitA THEN sLimited_phase := CONCAT(sLimited_phase, 'A'); END_IF
        IF bLimitB THEN sLimited_phase := CONCAT(sLimited_phase, 'B'); END_IF
        IF bLimitC THEN sLimited_phase := CONCAT(sLimited_phase, 'C'); END_IF
        
    ELSE
        P_cmd_out := P_cmd_in;
        bPhase_limited := FALSE;
        sLimited_phase := '';
    END_IF
END_FUNCTION_BLOCK
