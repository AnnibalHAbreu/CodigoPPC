(*
    FB_FFQ - Feedforward de Potência Reativa 
    Função:
    - Calcula o Q MÍNIMO necessário para atingir PF_target
    - Não calcula Q exato, mas o valor mínimo aceitável
    - Se o sistema fornecer menos Q, o PF ficará maior (melhor)
    - Se fornecer mais Q, o PF ficará menor (pior)
    Fórmula:
    Q_min = P × tan(acos(PF_target)) => Simplificado: Q_min = P × √(1 - PF²) / PF
*)

FUNCTION_BLOCK FB_FFQ
VAR_INPUT
    P_active_kW   : REAL;    // Potência ativa comandada (kW)
    PF_target_abs : REAL;    // PF alvo (0.92)
    PF_sign       : REAL;    // 1.0 = indutivo, -1.0 = capacitivo
END_VAR

VAR_OUTPUT
    Q_reactive_kvar : REAL;   // Potência Reativa Calculada (var) - Q mínimo para atingir PF_target
END_VAR

VAR
    tan_phi : REAL;           // Tangente do ângulo de fase
    Q_target    : REAL;       // Q total necessário no ponto de conexão
END_VAR

    // 1. Proteção: se potência ativa é zero ou negativa, não há Q a calcular
    IF P_active_kW <= 0.0 THEN
        Q_reactive_kvar := 0.0;
        RETURN;
    END_IF
    
    // Proteção: PF_target deve estar entre 0 e 1
    IF PF_target_abs <= 0.0 OR PF_target_abs > 1.0 THEN
        Q_reactive_kvar := 0.0;
        RETURN;
    END_IF
    
    // 2. Q total necessário no ponto de conexão para PF = 0.92
    // Método 1: usando tan(acos(PF))
    // phi := ACOS(PF_target_abs);              // Ângulo de fase em radianos
    // tan_phi := TAN(phi);                     // Tangente do ângulo
    // Q_reactive_var := P_active_W * tan_phi;
    // Método 2: Simplificado (mais eficiente, evita ACOS e TAN)
    // tan(acos(x)) = sqrt(1 - x²) / x
    tan_phi := SQRT(1.0 - (PF_target_abs * PF_target_abs)) / PF_target_abs;
    Q_target := P_active_kW * tan_phi;
    
    // atribuição correta
    Q_reactive_kvar := Q_target;
    
    // 3. Aplica o sinal (Indutivo = positivo, Capacitivo = negativo)
    // Nota: Para controle de exportação, normALARMente usamos indutivo (Q positivo)
    IF PF_sign < 0.0 THEN
        Q_reactive_kvar := -Q_reactive_kvar;  // Capacitivo
    END_IF
    
    // Resultado: Q_reactive_var é o Q MÍNIMO para atingir PF_target
    // - Se injetar menos Q: PF > PF_target (melhor)
    // - Se injetar mais Q: PF < PF_target (pior)
    // - Se injetar exatamente Q: PF = PF_target
END_FUNCTION_BLOCK
