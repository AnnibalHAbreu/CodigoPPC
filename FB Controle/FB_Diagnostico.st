(*
    ════════════════════════════════════════════════════════════════
    FB_Diagnostico - Diagnóstico de Fator de Potência
    ════════════════════════════════════════════════════════════════
    
    Gera diagnóstico completo do sistema de compensação de PF,
    incluindo alarmes, recomendações e estatísticas.
    
    ═══���════════════════════════════════════════════════════════════
*)

FUNCTION_BLOCK FB_Diagnostico
VAR_INPUT
    P_allocated_kW : REAL;
    Q_commanded_kvar : REAL;
    Q_allocated_kvar : REAL;
    Q_capacity_kvar : REAL;
    PF_measured : REAL;
    PF_achieved : REAL;
    bQ_limited : BOOL;
END_VAR

VAR
    Q_deficit : REAL;
    Q_deficit_pct : REAL;
    S_total_avail : REAL;
    S_total_used : REAL;
    bank_size : REAL;
    bank_size_int : DINT;  // ✅ DINT (não INT)
END_VAR

    // ════════════════════════════════════════════════════════════════
    // 1. ARMAZENA VALORES BÁSICOS
    // ════════════════════════════════════════════════════════════════
    
    GVL_Main.P_generated_kW := P_allocated_kW;
    GVL_Main.P_allocated_kW := P_allocated_kW;
    GVL_Main.Q_commanded_kvar := Q_commanded_kvar;
    GVL_Main.Q_allocated_kvar := Q_allocated_kvar;
    GVL_Main.Q_available_kvar := Q_capacity_kvar;
    GVL_Main.PF_measured := PF_measured;
    GVL_Main.PF_achieved := PF_achieved;
    
    // Q medido (do ponto de conexão)
    GVL_Main.Q_measured_kvar := GVL_Main.Qt;  // Já convertido em kvar pelo FB_AjustaLeitura
    
    // ════════════════════════════════════════════════════════════════
    // 2. CALCULA DÉFICIT DE Q
    // ════════════════════════════════════════════════════════════════
    
    Q_deficit := Q_commanded_kvar - Q_allocated_kvar;
    GVL_Main.Q_deficit_kvar := Q_deficit;
    
    // Déficit percentual
    IF ABS(Q_commanded_kvar) > 0.1 THEN
        Q_deficit_pct := (ABS(Q_deficit) / ABS(Q_commanded_kvar)) * 100.0;
    ELSE
        Q_deficit_pct := 0.0;
    END_IF
    GVL_Main.Q_deficit_percent := Q_deficit_pct;
    
    // ════════════════════════════════════════════════════════════════
    // 3. CALCULA UTILIZAÇÃO DE S
    // ════════════════════════════════════════════════════════════════
    
    // S total disponível
    S_total_avail := GVL_Main.InstalledSmax;
    GVL_Main.S_total_available_kVA := S_total_avail;
    
    // S total usado
    S_total_used := SQRT((P_allocated_kW * P_allocated_kW) + (Q_allocated_kvar * Q_allocated_kvar));
    GVL_Main.S_total_used_kVA := S_total_used;
    
    // Utilização percentual
    IF S_total_avail > 0.0 THEN
        GVL_Main.S_utilization_pct := (S_total_used / S_total_avail) * 100.0;
    ELSE
        GVL_Main.S_utilization_pct := 0.0;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 4. CALCULA UTILIZAÇÃO DE Q
    // ════════════════════════════════════════════════════════════════
    
    GVL_Main.Q_capacity_total_kvar := Q_capacity_kvar;
    
    IF Q_capacity_kvar > 0.0 THEN
        GVL_Main.Q_utilization_pct := (ABS(Q_allocated_kvar) / Q_capacity_kvar) * 100.0;
    ELSE
        GVL_Main.Q_utilization_pct := 0.0;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 5. CALCULA TAMANHO DE BANCO DE CAPACITORES
    // ════════════════════════════════════════════════════════════════
    
    IF Q_deficit > 0.1 THEN
        // Adiciona 10% de margem
        bank_size := ABS(Q_deficit) * 1.1;
    	bank_size := DINT_TO_REAL(TRUNC(bank_size / 5.0) + 1) * 5.0;
        GVL_Main.Capacitor_bank_size_kvar := bank_size;
        GVL_Main.Capacitor_bank_recommended := TRUE;
    ELSE
        GVL_Main.Capacitor_bank_size_kvar := 0.0;
        GVL_Main.Capacitor_bank_recommended := FALSE;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 6. DETERMINA STATUS DE PF
    // ════════════════════════════════════════════════════════════════
    
    IF PF_achieved >= GVL_Main.PF_target THEN
        GVL_Main.PF_OK := TRUE;
        GVL_Main.PFErro := FALSE;
        GVL_Main.PF_alarm_code := 0;  // OK
    ELSE
        GVL_Main.PF_OK := FALSE;
        
        IF bQ_limited THEN
            GVL_Main.PFErro := TRUE;
            
            // Classifica severidade
            IF Q_deficit_pct > 20.0 THEN
                GVL_Main.PF_alarm_code := 2;  // Crítico
    			FC_LogEvent(
    				eCode:=E_EventCode.ALARM_Q_LIMITED_SURPASS,
    				bRaised:=TRUE,
    				rParam1:=0.0,
    				rParam2:=0.0,
    				uMachState := GVL_Main.MachineState
    				);
            ELSE
                GVL_Main.PF_alarm_code := 1;  // Aviso
    			FC_LogEvent(
    				eCode:=E_EventCode.ALARM_Q_LIMITED_REACHED,
    				bRaised:=TRUE,
    				rParam1:=0.0,
    				rParam2:=0.0,
    				uMachState := GVL_Main.MachineState
    				);
            END_IF
        ELSE
            // PF < 0.92 mas não por limite de Q (transitório)
            GVL_Main.PFErro := FALSE;
            GVL_Main.PF_alarm_code := 1;
        END_IF
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 7. ATUALIZA HISTÓRICO (OPCIONAL - implementar com timers)
    // ════════════════════════════════════════════════════════════════
    
    // Atualiza PF mínimo
    IF PF_achieved < GVL_Main.PF_min_24h THEN
        GVL_Main.PF_min_24h := PF_achieved;
    END_IF
    
    // Atualiza déficit máximo
    IF Q_deficit > GVL_Main.Q_deficit_max_24h THEN
        GVL_Main.Q_deficit_max_24h := Q_deficit;
    END_IF
    
    // Conta alarmes (incrementar quando alarme dispara pela primeira vez)
    // (Implementar com edge detection)
END_FUNCTION_BLOCK
