FUNCTION_BLOCK FB_PI
VAR_INPUT
    setpoint    : REAL;         		// Setpoint desejado
    feedback    : REAL;         		// Medição atual (feedback)
    Kp          : REAL;         		// Ganho proporcional
    Ki          : REAL;         		// Ganho integral
    OutMax      : REAL;         		// Limite superior de saída
    OutMin      : REAL;         		// Limite inferior de saída
    CycleTime   : REAL;         		// Tempo de ciclo (s)
    RampUp      : REAL := 1.0E+6;  		//  Rampa de subida (unidade/s). Default = sem limite
    RampDown    : REAL := 1.0E+6;  		//  Rampa de descida (unidade/s). Default = sem limite
    Deadband    : REAL := 0.0;          //  deadband em kW (já convertido de %)
    bReset      : BOOL := FALSE;        //  reset do PI
END_VAR

VAR_OUTPUT
    u           : REAL;         		// Saída do controlador
    erro        : REAL;         		// Erro atual (setpoint - feedback)
    bSaturated  : BOOL;         		// TRUE = saída saturada
END_VAR

VAR
    integ           : REAL := 0.0;      // Integral acumulada
    LastOut         : REAL := 0.0;
    erroAtual       : REAL;             // Erro no ciclo atual
    u_prop          : REAL;             // Componente proporcional
    u_raw           : REAL;             // Saída antes da saturação
    u_limited       : REAL;         	// Saída após saturação, antes da rampa
    delta           : REAL;         	// Variação desejada
    delta_max       : REAL;         	// Variação máxima permitida
    primeiro_ciclo  : BOOL := TRUE;     // Flag de primeira execução
    sinal_saturacao : INT;              // +1: saturado max, -1: saturado min, 0: não saturado
END_VAR

    
    // ════════════════════════════════════════════════════════════════
    // Reset explícito
    // ════════════════════════════════════════════════════════════════
    IF bReset THEN
        integ := 0.0;
        LastOut := 0.0;
        u := 0.0;
        bSaturated := FALSE;
        primeiro_ciclo := TRUE;
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Inicialização suave na primeira execução
    // ════════════════════════════════════════════════════════════════
    IF primeiro_ciclo THEN
        integ := 0.0;
        primeiro_ciclo := FALSE;
        
        // Se quiser inicializar LastOut com valor atual do medidor:
        // LastOut := feedback;  // Opcional: evita salto inicial
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Cálculo do Erro + Deadband
    // ════════════════════════════════════════════════════════════════
    erroAtual := setpoint - feedback;
    
    // ✅ Deadband
    IF ABS(erroAtual) < Deadband THEN
        erroAtual := 0.0;
    END_IF
    
    erro := erroAtual;  // Saída para diagnóstico
    
    // ════════════════════════════════════════════════════════════════
    // Componente Proporcional
    // ════════════════════════════════════════════════════════════════
    u_prop := Kp * erroAtual;
    
    // ════════════════════════════════════════════════════════════════
    // Saída Raw (P + I + LastOut)
    // ══════════════════════════════════════════���═════════════════════
    u_prop := Kp * erroAtual;
    u_raw := u_prop + integ;
    
    // ════════════════════════════════════════════════════════════════
    // Saturação
    // ════════════════════════════════════════════════════════════════
    IF u_raw > OutMax THEN
        u_limited := OutMax;
        bSaturated := TRUE;
        sinal_saturacao := 1;
    ELSIF u_raw < OutMin THEN
        u_limited := OutMin;
        bSaturated := TRUE;
        sinal_saturacao := -1;
    ELSE
        u_limited := u_raw;
        bSaturated := FALSE;
        sinal_saturacao := 0;
    END_IF
    
    // ════════════════════════════════════════���═══════════════════════
    // Rate Limiter (Rampa)
    // ════════════════════════════════════════════════════════════════
    delta := u_limited - LastOut;
    
    IF delta > 0.0 THEN
        delta_max := RampUp * CycleTime;
        IF delta > delta_max THEN
            u := LastOut + delta_max;
        ELSE
            u := u_limited;
        END_IF
    ELSIF delta < 0.0 THEN
        delta_max := RampDown * CycleTime;
        IF ABS(delta) > delta_max THEN
            u := LastOut - delta_max;
        ELSE
            u := u_limited;
        END_IF
    ELSE
        u := u_limited;
    END_IF
    // ════════════════════════════════════════════════════════════════
    // Anti-windup Melhorado (Conditional Integration)
    // ════════════════════════════════════════════════════════════════
    // Regras:
    // 1. NÃO saturado → acumula normALARMente
    // 2. Saturado MAS erro na direção oposta → permite desacumular
    // 3. Saturado E erro na mesma direção → freeze (não acumula)
    
    IF NOT bSaturated THEN
        // Caso 1: Normal - acumula integral
        integ := integ + (Ki * erroAtual * CycleTime);
        
    ELSIF (sinal_saturacao = 1 AND erroAtual < 0.0) OR (sinal_saturacao = -1 AND erroAtual > 0.0) THEN
        // Caso 2: Saturado MAS erro está tentando sair da saturação
        // Permite acumular para ajudar a desaturar
        integ := integ + (Ki * erroAtual * CycleTime);
        
    ELSE
        // Caso 3: Saturado E erro empurrando mais para saturação
        // NÃO acumula (freeze integral)
        // integ permanece inalterado
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // Atualiza LastOut
    // ════════════════════════════════════════════════════════════════
    LastOut := u;
END_FUNCTION_BLOCK
