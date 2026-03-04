
(*
    ════════════════════════════════════════════════════════════════
    FB_QAlloc - Alocador de Potência Reativa
    ════════════════════════════════════════════════════════════════
	         
   // Protocolo Goodwe:
   //   - Indutivo (Q ≥ 0): Reg 80-100 → PF = Reg/100 (0.80-1.00)
   //   - Capacitivo (Q < 0): Reg 1-20 → PF = (100-Reg)/100 (0.80-0.99)
*)

FUNCTION_BLOCK FB_QAlloc
VAR_INPUT
    Q_total_cmd_kvar : REAL;        // Comando de Q total (do FB_PIQ)
END_VAR

VAR_OUTPUT
    bQ_limit_reached : BOOL;        // TRUE = Não conseguiu alocar todo Q
    Q_allocated_kvar : REAL;        // Q efetivamente alocado
    PF_effective : REAL;            // PF efetivo total resultante
    Q_capacity_total : REAL;        // Capacidade total de Q disponível (kvar)
    S_total_used : REAL;            // S total utilizado (kVA)
END_VAR

VAR

	// ✅ Acumuladores totais
    Q_total : REAL;
    P_total : REAL;
    Q_capacity_total_internal : REAL;
    S_total_used_internal : REAL;

	// ✅ Variáveis por inversor
    Q_target_i : REAL;
    Q_actual_i : REAL;
    Q_max_i : REAL;
    S_available_i : REAL;
    P_actual_i : REAL;
	
    // ✅ Auxiliares
    i : UINT;
    proportion : REAL;
    S_total : REAL;
    S_i : REAL;  // ✅ S do inversor i (calculado 1 vez)
	                
    PF_abs : REAL;  // PF absoluto (sem sinal)
    PF_reg : REAL;  // Registrador Modbus calculado (1-20 ou 80-100)
END_VAR


    // ════════════════════════════════════════════════════════════════
    // INICIALIZAÇÃO
    // ════════════════════════════════════════════════════════════════
    
    Q_total := 0.0;
    P_total := 0.0;
    Q_capacity_total_internal := 0.0;
    S_total_used_internal := 0.0;
    bQ_limit_reached := FALSE;
    
    // ════════════════════════════════════════════════════════════════
    // LOOP PRINCIPAL
    // ════════════════════════════════════════════════════════════════
    
    FOR i := 1 TO GVL_Main.NMAXINVERSORES DO
        
        IF GVL_Persis.InvActivePower[i] > 0.0 THEN
            
            // ────────────────────────────────────────────────────────
            // A. LÊ P JÁ ALOCADO
            // ────────────────────────────────────────────────────────
            P_actual_i := GVL_Main.P_inv_kW[i];
            
            // ────────────────────────────────────────────────────────
            // B. CALCULA Q MÁXIMO DISPONÍVEL
            // ────────────────────────────────────────────────────────
            S_available_i := GVL_Persis.InvSmaxPower[i];
            
            IF S_available_i > ABS(P_actual_i) THEN
                Q_max_i := SQRT((S_available_i * S_available_i) - (P_actual_i * P_actual_i));
            ELSE
                Q_max_i := 0.0;
            END_IF
            
            GVL_Main.Inv_Q_available[i] := Q_max_i;
            
            // ─────────────────────────────────────────���──────────────
            // C. DISTRIBUI Q PROPORCIONALARMENTE
            // ────────────────────────────────────────────────────────
            IF GVL_Main.P_allocated_kW > 0.01 THEN
                proportion := GVL_Main.P_inv_kW[i] / GVL_Main.P_allocated_kW;
            ELSE
                proportion := 0.0;
            END_IF
            
            Q_target_i := Q_total_cmd_kvar * proportion;
            
            // ────────────────────────────────────────────────────────
            // D. LIMITA Q AO DISPONÍVEL
            // ────────────────────────────────────────────────────────
            IF ABS(Q_target_i) > Q_max_i THEN
                
                IF Q_target_i >= 0.0 THEN
                    Q_actual_i := Q_max_i;
                ELSE
                    Q_actual_i := -Q_max_i;
                END_IF
                
                bQ_limit_reached := TRUE;
                GVL_Main.Inv_limited[i] := TRUE;
                
            ELSE
                Q_actual_i := Q_target_i;
                GVL_Main.Inv_limited[i] := FALSE;
            END_IF
            
            // ────────────────────────────────────────────────────────
            // E. ARMAZENA Q
            // ────────────────────���───────────────────────────────────
            GVL_Main.Q_inv_kvar[i] := Q_actual_i;
            
            // ────────────────────────────────────────────────────────
            // F. CALCULA S UTILIZADO (✅ UMA VEZ)
            // ────────────────────────────────────────────────────────
            S_i := SQRT((P_actual_i * P_actual_i) + (Q_actual_i * Q_actual_i));
            
            S_total_used_internal := S_total_used_internal + S_i;
            
            // Utilização de S (%)
            IF S_available_i > 0.0 THEN
                GVL_Main.Inv_S_utilization[i] := (S_i / S_available_i) * 100.0;
            ELSE
                GVL_Main.Inv_S_utilization[i] := 0.0;
            END_IF
            
            // ────────────────────────────────────────────────────────
            // G. CALCULA PF INDIVIDUAL
            // ────────────────────────────────────────────────────────
            IF S_i > 0.01 THEN
                GVL_Main.PF_inv[i] := P_actual_i / S_i;
            ELSE
                GVL_Main.PF_inv[i] := 1.0;
            END_IF
    
            // ────────────────────────────────────────────────────────
            // Protocolo Goodwe:
            //   - Indutivo (Q ≥ 0): Reg 80-100 → PF = Reg/100 (0.80-1.00)
            //   - Capacitivo (Q < 0): Reg 1-20 → PF = (100-Reg)/100 (0.80-0.99)
            // ──────────────────────────────────────────────────────────
            // VALIDAÇÃO DE RANGE FÍSICO
            // ──────────────────────────────────────────────────────────
            PF_abs := ABS(GVL_Main.PF_inv[i]);
    
            IF PF_abs < 0.80 THEN
            // ❌ CRÍTICO: PF < 0.80 não é suportado pelo inversor
    			IF GVL_Main.Q_inv_kvar[i] >= 0.0 THEN
    				GVL_Main.PF_inv[i] := 0.80;   // Indutivo
    			ELSE
    				GVL_Main.PF_inv[i] := -0.80;  // Capacitivo
    			END_IF
    			FC_LogEvent(
    				eCode := E_EventCode.ALARM_MEAS_PFT_RANGE,  // Reutiliza evento existente
    				bRaised := TRUE,
    				rParam1 := UINT_TO_REAL(i),
    				rParam2 := PF_abs,
    				uMachState := GVL_Main.MachineState
    				);
    			PF_abs := 0.80;
                    
            ELSIF PF_abs > 1.0 THEN
                // ❌ CRÍTICO: PF > 1.0 fisicamente impossível
    			IF GVL_Main.Q_inv_kvar[i] >= 0.0 THEN
    				GVL_Main.PF_inv[i] := 1.0;
    			ELSE
    				GVL_Main.PF_inv[i] := -1.0;
    			END_IF
                FC_LogEvent(
                    eCode := E_EventCode.ALARM_MEAS_PFT_RANGE,
                    bRaised := TRUE,
                    rParam1 := UINT_TO_REAL(i),
                    rParam2 := PF_abs,
                    uMachState := GVL_Main.MachineState
                );
                PF_abs := 1.0;
            END_IF
    
           // ──────────────────────────────────────────────────────────
           // CONVERSÃO PARA FORMATO MODBUS (Baseado no SINAL de Q)
           // ──────────────────────────────────────────────────────────
    
           IF GVL_Main.Q_inv_kvar[i] >= 0.0 THEN
                // ── INDUTIVO (Q positivo) → Range 80-100 ──
                PF_reg := PF_abs * 100.0;
                  
                // Clamp no range válido
                IF PF_reg < 80.0 THEN
                    PF_reg := 80.0;
                ELSIF PF_reg > 100.0 THEN
                    PF_reg := 100.0;
           		END_IF
                    
           ELSE
                // ── CAPACITIVO (Q negativo) → Range 1-20 ──
                // Fórmula: Reg = 100 - (PF × 100)
                // Ex: PF 0.90 → Reg = 100 - 90 = 10
                PF_reg := 100.0 - (PF_abs * 100.0);
                   
                // Clamp no range válido
                IF PF_reg < 1.0 THEN
                    PF_reg := 1.0;
                 ELSIF PF_reg > 20.0 THEN
                     PF_reg := 20.0;
                END_IF
           END_IF
    
           // ──────────────────────────────────────────────────────────
           // ARMAZENA VALOR FINAL
           // ──────────────────────────────────────────────────────────
           GVL_Main.PF_inv_Percent[i] := PF_reg;
           
    	   // ────────────────────────────────────────────────────────
           // H. ACUMULADORES
           // ────────────────────────────────────────────────────────
           P_total := P_total + P_actual_i;
           Q_total := Q_total + Q_actual_i;
           Q_capacity_total_internal := Q_capacity_total_internal + Q_max_i;
            
        ELSE
            // Inversor inativo
            GVL_Main.Q_inv_kvar[i] := 0.0;
            GVL_Main.PF_inv[i] := 1.0;
            GVL_Main.Inv_Q_available[i] := 0.0;
            GVL_Main.Inv_S_utilization[i] := 0.0;
            GVL_Main.Inv_limited[i] := FALSE;
            GVL_Main.PF_inv_Percent[i] := 100.0;  // PF = 1.0 em formato Modbus
        END_IF
        
    END_FOR
    
    // ════════════════════════════════════════════════════════════════
    // SAÍDAS
    // ════════════════════════════════════════════════════════════════
    
    Q_allocated_kvar := Q_total;
    Q_capacity_total := Q_capacity_total_internal;
    S_total_used := S_total_used_internal;
    
    // PF efetivo total
    IF P_total > 0.01 OR ABS(Q_total) > 0.01 THEN
        S_total := SQRT((P_total * P_total) + (Q_total * Q_total));
        PF_effective := P_total / S_total;
    ELSE
        PF_effective := 1.0;
    END_IF
END_FUNCTION_BLOCK
