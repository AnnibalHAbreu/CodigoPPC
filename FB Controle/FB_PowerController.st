(*
    ════════════════════════════════════════════════════════════════
    FB_PowerController - Controlador de Potência Ativa
    ════════════════════════════════════════════════════════════════
    
    Responsabilidade:
    - Calcular comando de P (PI + Safety Margin + Limites de Fase)
    - Encapsular toda lógica relacionada a potência ativa
    
    Pipeline:
    1. PI → P_cmd_raw
    2. Safety Margin → P_cmd_with_margin
    3. Limitador de Fase → P_cmd_limited
    
    ════════════════════════════════════════════════════════════════
*)
FUNCTION_BLOCK FB_PowerController
VAR_INPUT
    ExportLimit_kW : REAL;      // Do scheduler (kW)
    Feedback_kW : REAL;         // Leitura do medidor (kW)
    bReset : BOOL;              // Reset do PI
END_VAR

VAR_OUTPUT
    P_cmd_kW : REAL;            // Comando final (kW)
    bSaturated : BOOL;          // PI saturado
    bPhase_limited : BOOL;      // Limitado por fase
    sLimited_phase : STRING;    // Qual fase limitou
    Margin_applied_kW : REAL;   // Margem aplicada (telemetria)
	EffectiveExportLimit_kW : REAL;
END_VAR

VAR
    // Sub-blocos
    fbPI : FB_PI;
    fbSafetyMargin : FB_SafetyMargin;
    fbFLimiter : FB_FLimiter;
	fbDroop : FB_DroopP;
    
    // Variáveis internas
    P_setpoint : REAL;
    P_cmd_raw : REAL;
    P_cmd_with_margin : REAL;
	lastInstalledPower : REAL := -1.0;
	
	// Droop
    P_error_kW : REAL;
    P_droop_kW : REAL;
	
    P_droop_max_kW : REAL;
    P_cmd_sum : REAL;
	
	// ✅ Deadband em kW (convertido de %)
	Deadband_P_kW     : REAL;
    Droop_Deadband_kW : REAL;
END_VAR

    // ────────────────────────────────────────────────────────────────
    // ETAPA 1: CONTROLADOR PI
    // ────────────────────────────────────────────────────────────────
    
    // Setpoint negativo (exportação)
    P_setpoint := -ABS(ExportLimit_kW);
    
    // Erro (kW)
    P_error_kW := Feedback_kW - P_setpoint;
    
    // Converte deadband (%) para kW (mínimo 1 kW)
    // Recalcula apenas se InstalledPower mudou
    IF lastInstalledPower <> GVL_Main.InstalledPower THEN
        Deadband_P_kW := MAX(1.0, GVL_Main.InstalledPower * (GVL_Pers.Deadband_P / 100.0));
        Droop_Deadband_kW := MAX(1.0, GVL_Main.InstalledPower * (GVL_Pers.Deadband_Droop / 100.0));
    	Deadband_P_kW := MIN(20.0, MAX(1.0, GVL_Main.InstalledPower * (GVL_Pers.Deadband_P / 100.0)));
    	Droop_Deadband_kW := MIN(20.0, MAX(1.0, GVL_Main.InstalledPower * (GVL_Pers.Deadband_Droop / 100.0)));		
        lastInstalledPower := GVL_Main.InstalledPower;
    END_IF
    
    // Limite máximo do droop (fração da potência instalada)
    P_droop_max_kW := GVL_Pers.Droop_Max * GVL_Main.InstalledPower;
    
    // Calcula droop
    fbDroop(
        Enable      := GVL_Pers.Droop_Enable,
        bReset      := bReset,                 
        Error_kW    := P_error_kW,
        K_droop     := GVL_Pers.K_Droop,
        Deadband_kW := Droop_Deadband_kW,
        P_max_kW    := P_droop_max_kW
    );
    
    P_droop_kW := fbDroop.P_droop_kW;
    
    // PI de potência ativa
    fbPI(
        setpoint    := P_error_kW,
        feedback    := 0.0,
        Kp          := GVL_Pers.Kp_P,
        Ki          := GVL_Pers.Ki_P,
        OutMax      := GVL_Main.InstalledPower,
        OutMin      := 0.0,
        CycleTime   := GVL_Main.ControlCycle,
    	RampUp      := GVL_Pers.RampUp_P,     
        RampDown    := GVL_Pers.RampDown_P,    
        Deadband    := Deadband_P_kW,
    	bReset      := bReset          
    );
    
    // Soma droop + PI
    P_cmd_sum := P_droop_kW + fbPI.u;
    
    // Comando bruto (segue fluxo normal)
    P_cmd_raw := P_cmd_sum;
    IF P_cmd_raw < 0.0 THEN
        P_cmd_raw := 0.0;
    ELSIF P_cmd_raw > GVL_Main.InstalledPower THEN
        P_cmd_raw := GVL_Main.InstalledPower;
    END_IF
    bSaturated := fbPI.bSaturated;
    
    // ─────────────────────────────────────────���──────────────────────
    // ETAPA 2: SAFETY MARGIN
    // ────────────────────────────────────────────────────────────────
    
    fbSafetyMargin(
        P_cmd_raw_kW := P_cmd_raw,
        Margin_pct := GVL_Pers.SafetyMargin_pct,
        TC_Power_kW := GVL_Pers.TC_Power_kW
    );
    
    P_cmd_with_margin := fbSafetyMargin.P_cmd_adjusted_kW;
    Margin_applied_kW := fbSafetyMargin.Margin_applied_kW;  // ✅ Telemetria
    EffectiveExportLimit_kW := P_setpoint + Margin_applied_kW;
    // ────────────────────────────────────────────────────────────────
    // ETAPA 3: LIMITADOR DE FASE
    // ────────────────────────────────────────────────────────────────
    
    fbFLimiter(
        P_cmd_in := P_cmd_with_margin,
        PowerMode := GVL_Pers.PowerMode
    );
    
    P_cmd_kW := fbFLimiter.P_cmd_out;
    bPhase_limited := fbFLimiter.bPhase_limited;
    sLimited_phase := fbFLimiter.sLimited_phase;
    
    // ────────────────────────────────────────────────────────────────
    // PROTEÇÃO FINAL: Potência Instalada
    // ────────────────────────────────────────────────────────────────
    
    IF P_cmd_kW > GVL_Main.InstalledPower THEN
        P_cmd_kW := GVL_Main.InstalledPower;
        bSaturated := TRUE;
    END_IF
END_FUNCTION_BLOCK
