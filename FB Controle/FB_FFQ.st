(*
    FB_FFQ - Feedforward de Potência Reativa 

    Calcula o Q MÍNIMO necessário para que a SAÍDA DOS INVERSORES
    atinja PF_target quando gerando P_active_kW.
    
    IMPORTANTE:
    - NÃO usa medição do PCC (isso é responsabilidade do FB_PIQ)
    - Fornece estimativa inicial (feedforward)
    - PIQ corrige com base no PF medido (feedback)
  
    ════════════════════════════════════════════════════════════════
    LÓGICA CORRETA (GD Solar com Carga Indutiva):
    ════════════════════════════════════════════════════════════════
    
    1. Medidor no PCC lê:
       - P_medido (importação/exportação)
       - Q_medido (da carga, tipicamente INDUTIVO +)
    
    2. Para atingir PF = 0.92 no PCC:
       Q_permitido = |P_medido| × tan(acos(0.92))
                   = |P_medido| × 0.4256
    
    3. Inversores devem compensar Q da carga:
       Q_inv = Q_medido - Q_permitido
    
    EXEMPLO:
    ────────────────────────────────────────────────────────────────
    P_medido = -100 kW (exportando)
    Q_medido = +300 kvar (carga indutiva)
    
    Q_permitido = 100 × 0.4256 = 42.56 kvar
    Q_inv = 300 - 42.56 = 257.44 kvar CAPACITIVO
    
    → Inversores fornecem -257.44 kvar (CAPACITIVO)
    → PF_pcc = 100 / √(100² + 42.56²) ≈ 0.92 ✅
    ════════════════════════════════════════════════════════════════

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

    // Proteção: se potência ativa é zero ou negativa, não há Q a calcular
    IF P_active_kW <= 0.0 THEN
        Q_reactive_kvar := 0.0;
        RETURN;
    END_IF
    
    // Proteção: PF_target deve estar entre 0 e 1
    IF PF_target_abs <= 0.0 OR PF_target_abs > 1.0 THEN
        Q_reactive_kvar := 0.0;
        RETURN;
    END_IF
    
    // Q total necessário no ponto de conexão para PF = 0.92
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
    
    // Aplica o sinal (Indutivo = positivo, Capacitivo = negativo)
    // - Cargas normalmente são INDUTIVAS (consomem Q+)
    // - Inversores devem fornecer Q CAPACITIVO (Q-) para compensar
    // - PF_sign é configurável para casos especiais (ex: carga capacitiva)
    //
    // REGRA:
    // - PF_sign > 0 → Q positivo (inversor fornece Q indutivo - raro)
    // - PF_sign < 0 → Q negativo (inversor fornece Q capacitivo - normal)
    // Nota: Para controle de exportação, normalmente usamos capacitivo (negativo)
    
        IF PF_sign < 0.0 THEN
            Q_reactive_kvar := -Q_target;  // Capacitivo
        ELSE
            Q_reactive_kvar := Q_target;   // Indutivo
        END_IF
    
    // Resultado: Q_reactive_var é o Q MÍNIMO para atingir PF_target
    // - Se injetar menos Q: PF > PF_target (melhor)
    // - Se injetar mais Q: PF < PF_target (pior)
    // - Se injetar exatamente Q: PF = PF_target
END_FUNCTION_BLOCK
