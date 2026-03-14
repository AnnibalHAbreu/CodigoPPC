(*
    ════════════════════════════════════════════════════════════════
    FB_PAlloc - Alocador de Potência Ativa (PRIORIDADE MÁXIMA)
    ════════════════════════════════════════════════════════════════
*)
FUNCTION_BLOCK FB_PAlloc
VAR_INPUT
    P_total_cmd_kW : REAL;          // Comando de P total (do FB_PI)
END_VAR

VAR_OUTPUT
    P_allocated_kW : REAL;          // ✅ ADICIONAR ESTA SAÍDA!
END_VAR

VAR
    i : UINT;
    P_target_i : REAL;
    P_actual_i : REAL;
    P_total_calc : REAL;
    proportion : REAL;
END_VAR

    
    P_total_calc := 0.0;
    
    FOR i := 1 TO GVL_Main.NMAXINVERSORES DO     
        
        IF GVL_Pers.InvActivePower[i] > 0.0 THEN
            
            // Proporção do inversor
            proportion := GVL_Pers.InvActivePower[i] / GVL_Main.InstalledPower;
            
            // P proporcional
            P_target_i := P_total_cmd_kW * proportion;
            
            // Limita apenas pela nominal (ignora S_max por enquanto)
            P_actual_i := MIN(P_target_i, GVL_Pers.InvActivePower[i]);
            
            // Armazena P
            GVL_Main.P_inv_kW[i] := P_actual_i;
            
            // Setpoint percentual
            IF GVL_Pers.InvActivePower[i] > 0.0 THEN
                GVL_Main.P_inv_Percent[i] := (P_actual_i / GVL_Pers.InvActivePower[i]) * 100.0;
            ELSE
                GVL_Main.P_inv_Percent[i] := 0.0;
            END_IF
            
            P_total_calc := P_total_calc + P_actual_i;
            
        ELSE
            GVL_Main.P_inv_kW[i] := 0.0;
            GVL_Main.P_inv_Percent[i] := 0.0;
        END_IF
        
    END_FOR
    
    // ✅ ATUALIZA SAÍDA
    P_allocated_kW := P_total_calc;
END_FUNCTION_BLOCK
