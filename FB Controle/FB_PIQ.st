(*
    FB_PIQ - Controlador PI para Fator de Potência
    Lógica para PF ≥ 0.92:
    - Se PV (PF medido) ≥ SP (PF target): erro = 0 (objetivo atingido)
    - Se PV < SP: erro = SP - PV (precisa aumentar Q)
    Diferente de um PI normal:
    - Erro ZERO quando PF ≥ target (não tenta melhorar além do necessário)
    - Saída é comando de Q (kvar)
*)

FUNCTION_BLOCK FB_PIQ
VAR_INPUT
    SP : REAL;                      		// Setpoint de PF (0.92)
    PV : REAL;                      		// PF medido (absoluto)
	Kp : REAL;              
    Ki : REAL;              
    CycleTime : REAL;       				
    P_cmd : REAL;                   		// Comando de P (para referência)
    RampUp : REAL;                  		// Rampa de subida (kvar/s)
    RampDown : REAL;                		// Rampa de descida (kvar/s)
    DeadbandAbs : REAL;             		// Zona morta de PF (ex: 0.01)
    Reset : BOOL;                   		// Zera o controlador
    bExternal_Saturated : BOOL := FALSE;  	// NOVO: Saturação externa (de FB_QAlloc)
	OutMax : REAL := 1000.0;    			// Limite superior de MV (kvar)
    OutMin : REAL := 0.0;       			// Limite inferior de MV (kvar)
END_VAR

VAR_OUTPUT
    MV : REAL;                      // Comando de Q (kvar)
    Error : REAL;                   // BOOL → REAL (valor do erro)
    Saturated : BOOL;               // TRUE = saída saturada
END_VAR

VAR
    integral : REAL := 0.0;         // Acumulador integral
    P_term : REAL;                  // Termo proporcional
    I_term : REAL;                  // Termo integral
    MV_raw : REAL;                  // Saída bruta (antes de rampa)
    MV_prev : REAL := 0.0;          // Saída do ciclo anterior
    delta : REAL;                   // Variação desejada
    delta_max : REAL;               // Variação máxima permitida
    erro : REAL;                    // Erro de PF
    sinal_saturacao : INT;      	// para anti-windup direcional
END_VAR

    // ════════════════════════════════════════════════════════════════
    // 1. RESET
    // ════════════════════════════════════════════════════════════════
    IF Reset THEN
        integral := 0.0;
        MV := 0.0;
        MV_prev := 0.0;
        Error := 0.0;  
        Saturated := FALSE;
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 2. CALCULA ERRO COM LÓGICA ESPECIAL (PF ≥ TARGET)
    // ════════════════════════════════════════════════════════════════
    
    IF PV >= SP THEN
        erro := 0.0;  // PF medido ≥ PF target: objetivo atingido
    ELSE
        erro := SP - PV;  // PF medido < PF target: precisa corrigir
    END_IF
    
    Error := erro;  // ✅ Saída do erro
    
    // ════════════════════════════════════════════════════════════════
    // 3. ZONA MORTA (DEADBAND)
    // ════════════════════════════════════════════════════════════════
    
    IF ABS(erro) < DeadbandAbs THEN
        erro := 0.0;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 4. CÁLCULO PI
    // ════════════════════════════════════════════════════════════════
    
    P_term := Kp * erro;
    I_term := integral + (Ki * erro * CycleTime);
    MV_raw := P_term + I_term;
    
    // ════════════════════════════════════════════════════════════════
    // 5. ✅ SATURAÇÃO COM OutMax/OutMin (ALTERAÇÃO)
    // ════════════════════════════════════════════════════════════════
    IF MV_raw > OutMax THEN
        MV_raw := OutMax;
        sinal_saturacao := 1;
    ELSIF MV_raw < OutMin THEN
        MV_raw := OutMin;
        sinal_saturacao := -1;
    ELSE
        sinal_saturacao := 0;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 6. ANTI-WINDUP (Conditional Integration)
    // ════════════════════════════════════════════════════════════════
    
    IF bExternal_Saturated OR (sinal_saturacao <> 0) THEN
        // Saturado: só acumula se erro empurra para FORA da saturação
        IF (sinal_saturacao = 1 AND erro < 0.0) OR
           (sinal_saturacao = -1 AND erro > 0.0) THEN
            integral := I_term;  // Permite desacumular
        END_IF
        // Caso contrário: integral permanece (freeze)
        Saturated := TRUE;
    ELSE
        integral := I_term;
        Saturated := FALSE;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 7. RATE LIMITER (Rampa)
    // ════════════════════════════════════════════════════════════════
    
    delta := MV_raw - MV_prev;
    
    IF delta > 0.0 THEN
        delta_max := RampUp * GVL_Main.ControlCycle;
        IF delta > delta_max THEN
            MV := MV_prev + delta_max;
        ELSE
            MV := MV_raw;
        END_IF
        
    ELSIF delta < 0.0 THEN
        delta_max := RampDown * GVL_Main.ControlCycle;
        IF ABS(delta) > delta_max THEN
            MV := MV_prev - delta_max;
        ELSE
            MV := MV_raw;
        END_IF
        
    ELSE
        MV := MV_raw;
    END_IF
    
    MV_prev := MV;
END_FUNCTION_BLOCK
