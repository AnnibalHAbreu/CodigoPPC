(*═════════════════════════════════════════════════════════════════════
 FB_ValidaMedicao
 
 Valida medições do medidor trifásico via Modbus, aplica filtro
 passa-baixa e verifica consistência física das grandezas.
 
 ENTRADAS:
 - (nenhuma - lê de valorLido.WordArray via Modbus)
 
 SAÍDAS:
 - bDadosOK: TRUE se medições são válidas
 - bPoucosErros: TRUE se < 5 erros consecutivos
 - diagnosticCode: Código de falha (0 = OK)
 
 LÓGICA:
 1. Conversão de escalas (Modbus → unidades físicas)
 2. Validação de ranges individuais
 3. Validação cruzada (Pt vs soma, PF vs P/S)
 4. Detecção de congelamento 
 5. Filtro passa-baixa exponencial (SOMENTE se validação OK)
 6. Atualização de variáveis globais (SOMENTE se validação OK)
 7. Janela de erros (5 consecutivos = FAIL_SAFE)
═════════════════════════════════════════════════════════════════════*)
FUNCTION_BLOCK FB_ValidaDados

VAR_INPUT
	Meas_Device     : E_MeasDeviceType;
END_VAR

VAR_OUTPUT
    bDadosOK		: BOOL 	:= FALSE;  // Dados aprovados
	bPoucosErros	: BOOL  := TRUE;  // IniciALARMente sem erros
END_VAR

VAR
	valorLido		: UN_Rele;
	Ua    	    	: REAL := 0.0; // 2006H - Tensão de fase A x 0,1 V
	Ub    	    	: REAL := 0.0; // 2008H - Tensão de fase B x 0,1 V
	Uc    	    	: REAL := 0.0; // 200AH - Tensão de fase C x 0,1 V
	
	Ia    	    	: REAL := 0.0; // 200CH - Corrente de fase A x 0,001 A 
	Ib    	    	: REAL := 0.0; // 200EH - Corrente de fase B x 0,001 A
	Ic    	    	: REAL := 0.0; // 2010H - Corrente de fase C x 0,001 A
	
	Pt    	    	: REAL := 0.0; // 2012H - Potencia ativa combinada x 0,1 W
	Pa    	    	: REAL := 0.0; // 2014H - Potencia ativa fase A x 0,1 W
	Pb    	    	: REAL := 0.0; // 2016H - Potencia ativa fase B x 0,1 W
	Pc    	   		: REAL := 0.0; // 2018H - Potencia ativa fase C x 0,1 W	
		
	Qt    	    	: REAL := 0.0; // 201AH - Potencia reativa combinada x 0,1 var
	Qa    	    	: REAL := 0.0; // 201CH - Potencia reativa fase A x 0,1 var
	Qb    	    	: REAL := 0.0; // 201EH - Potencia reativa fase B x 0,1 var
	Qc    	    	: REAL := 0.0; // 2020H - Potencia reativa fase C x 0,1 var

	PFt    	    	: REAL := 0.0; // 202AH - Fator de potência combinado (número positivo: indutivo, número negativo: capacitivo) (x  0,001)
	PFa    	    	: REAL := 0.0; // 202CH - Fator de potência de fase A (número positivo: indutivo, número negativo: capacitivo)  (×0,001)
	PFb    	    	: REAL := 0.0; // 202EH - Fator de potência de fase B (número positivo: indutivo, número negativo: capacitivo)  (×0,001)
	PFc    	    	: REAL := 0.0; // 2030H - Fator de potência de fase C (número positivo: indutivo, número negativo: capacitivo)  (×0,001)
	
	// Limites físicos (ajustar conforme instalação)
    PFMIN 			: REAL := 0.5;
    PFMAX 			: REAL := 1.0;
	
	// variaveis auxiliares
	Pt_last			: REAL;
	nErrors 		: UINT := 0;
	SomaP			: REAL;
	SomaQ 			: REAL;
	Calculado 		: REAL;
	Tolerancia  	: REAL :=0.05;
	Pt_lastatus		: REAL := 0.0;
    frozen_count 	: UINT := 0;
	FREEZE_THRESHOLD: UINT := 10;  		// 10 ciclos
	bFirstRun		: BOOL :=TRUE;
	Pt_filt 		: REAL :=0;
    Qt_filt 		: REAL :=0;
    PFt_filt 		: REAL :=0;
END_VAR

    // ═══════════════════════════════════════════════════════════════
    // 1. RESET DE ESTADO
    // ═══════════════════════════════════════════════════════════════
    
    GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := FALSE;
    
    // ═══════════════════════════════════════════════════════════════
    // 2. CONVERSÃO DE ESCALAS
    // ═══════════════════════════════════════════════════════════════
    
    CASE Meas_Device OF 
    	
    	E_MeasDeviceType.CHINT_DTSU666 :
    	 
    		Ua  := valorLido.EmReal.Ua * 0.1;				// em Volts
    		Ub  := valorLido.EmReal.Ub * 0.1;				// em Volts
    		Uc  := valorLido.EmReal.Uc * 0.1;				// em Volts
    		
    		Ia  := valorLido.EmReal.Ia * 0.001;				// em Amperes
    		Ib  := valorLido.EmReal.Ib * 0.001;				// em Amperes
    		Ic  := valorLido.EmReal.Ic * 0.001;				// em Amperes
    		
    		Pt  := valorLido.EmReal.Pt *0.0001;				// kW
    		Pa  := valorLido.EmReal.Pa *0.0001;				// kW
    		Pb  := valorLido.EmReal.Pb *0.0001;				// kW
    		Pc  := valorLido.EmReal.Pc *0.0001;				// kW
    		
    		Qt  := valorLido.EmReal.Qt *0.0001;				// kvar
    		Qa  := valorLido.EmReal.Qa *0.0001;				// kvar
    		Qb  := valorLido.EmReal.Qb *0.0001;				// kvar
    		Qc  := valorLido.EmReal.Qc *0.0001;				// xkvar
    		
    		PFt := valorLido.EmReal.PFt *0.001;	
    		PFa := valorLido.EmReal.PFa *0.001;
    		PFb := valorLido.EmReal.PFb *0.001;
    		PFc := valorLido.EmReal.PFc *0.001;
    
    	E_MeasDeviceType.RELAY_URP1439TU :
    
    		Ua  := valorLido.EmReal.Ua;				// em Volts
    		Ub  := valorLido.EmReal.Ub;				// em Volts
    		Uc  := valorLido.EmReal.Uc;				// em Volts
    		
    		Ia  := valorLido.EmReal.Ia;				// em Amperes
    		Ib  := valorLido.EmReal.Ib;				// em Amperes
    		Ic  := valorLido.EmReal.Ic;				// em Amperes
    		
    		PFt := valorLido.EmReal.PFt;	
    		PFa := valorLido.EmReal.PFa;
    		PFb := valorLido.EmReal.PFb;
    		PFc := valorLido.EmReal.PFc;
    
    	E_MeasDeviceType.RELAY_URP6000:
    		// a definir
    		
    	E_MeasDeviceType.RELAY_REMP_GD:
    		// a definir
    
    END_CASE
    
    // ═══════════════════════════════════════════════════════════════
    // 3. VALIDAÇÃO DE RANGES (SEM RETURN)
    // ═══════════════════════════════════════════════════════════════
    // validação de tensões
    
    IF (Ua < GVL_Persis.VMIN) OR (Ua > GVL_Persis.VMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_VOLTAGE_A_RANGE,bRaised:=TRUE,rParam1:=Ua,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (Ub < GVL_Persis.VMIN) OR (Ub > GVL_Persis.VMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_VOLTAGE_B_RANGE,bRaised:=TRUE,rParam1:=Ub,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (Uc < GVL_Persis.VMIN) OR (Uc > GVL_Persis.VMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_VOLTAGE_C_RANGE,bRaised:=TRUE,rParam1:=Uc,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    
    // validação de correntes
    IF (ABS(Ia) > GVL_Persis.IMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_CURRENT_A_RANGE,bRaised:=TRUE,rParam1:=Ia,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Ib) > GVL_Persis.IMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_CURRENT_B_RANGE,bRaised:=TRUE,rParam1:=Ib,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Ic) > GVL_Persis.IMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_CURRENT_C_RANGE,bRaised:=TRUE,rParam1:=Ic,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    
    // validação de potencias ativas
    IF (ABS(Pt) > GVL_Persis.PMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PT_RANGE,bRaised:=TRUE,rParam1:=Pt,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Pa) > GVL_Persis.PMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PA_RANGE,bRaised:=TRUE,rParam1:=Pa,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Pb) > GVL_Persis.PMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PB_RANGE,bRaised:=TRUE,rParam1:=Pb,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Pc) > GVL_Persis.PMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PC_RANGE,bRaised:=TRUE,rParam1:=Pc,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    
    // validação de potencias reativas
    IF (ABS(Qt) > GVL_Persis.QMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_QT_RANGE,bRaised:=TRUE,rParam1:=Qt,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Qa) > GVL_Persis.QMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_QA_RANGE,bRaised:=TRUE,rParam1:=Qa,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Qb) > GVL_Persis.QMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_QB_RANGE,bRaised:=TRUE,rParam1:=Qb,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(Qc) > GVL_Persis.QMAX) THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_QC_RANGE,bRaised:=TRUE,rParam1:=Qc,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    	
    // validação do fator das potencias
    	
    IF (ABS(PFt) < PFMIN) OR (ABS(PFt) >PFMAX)  THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PFT_RANGE,bRaised:=TRUE,rParam1:=PFt,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(PFa) < PFMIN) OR (ABS(PFa) >PFMAX)  THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PFA_RANGE,bRaised:=TRUE,rParam1:=PFa,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(PFb) < PFMIN) OR (ABS(PFb) >PFMAX)  THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PFB_RANGE,bRaised:=TRUE,rParam1:=PFb,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    IF (ABS(PFc) < PFMIN) OR (ABS(PFc) >PFMAX)  THEN
        GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    	FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PFC_RANGE,bRaised:=TRUE,rParam1:=PFc,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    END_IF
    
    // ═══════════════════════════════════════════════════════════════
    // 4. VALIDAÇÃO CRUZADA (SÓ SE NÃO HOUVER ERRO AINDA)
    // ═══════════════════════════════════════════════════════════════
    
    IF NOT GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR THEN
    	// Só valida se Pa significativo (ex: > 1 kW)
    	IF ABS(Pa) > 1.0 THEN
    		Calculado := Ua * Ia * PFa / 1000;
    		IF ABS(Pa - Calculado) > (ABS(Pa) * Tolerancia) THEN  // ✅ Usa Pa, não Calculado
    			GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    			FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PA_XCHECK_FAIL,bRaised:=TRUE,rParam1:=Pa,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    		END_IF
    	END_IF
    	
    	// Repetir para Pb e Pc
    	IF ABS(Pb) > 1.0 THEN
    		Calculado := Ub * Ib * PFb / 1000;
    		IF ABS(Pb - Calculado) > (ABS(Pb) * Tolerancia) THEN
    			GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    			FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PB_XCHECK_FAIL,bRaised:=TRUE,rParam1:=Pb,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    		END_IF
    	END_IF
    	
    	IF ABS(Pc) > 1.0 THEN
    		Calculado := Uc * Ic * PFc / 1000;
    		IF ABS(Pc - Calculado) > (ABS(Pc) * Tolerancia) THEN
    			GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    			FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PC_XCHECK_FAIL,bRaised:=TRUE,rParam1:=Pc,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    		END_IF
    	END_IF
    	// Pt = Pa + Pb + Pc
    	SomaP := Pa + Pb + Pc;
    	IF ABS(Pt) > 1.0 THEN  // ✅ Só valida se significativo
    		IF ABS(Pt - SomaP) > (ABS(Pt) * Tolerancia) THEN  // ✅ Usa Pt
    			GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    			FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PT_XCHECK_FAIL,bRaised:=TRUE,rParam1:=Pt,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    		END_IF
    	END_IF
    	
    	// FPt com base nas potencias ativas e reativas
    	SomaQ:=Qa + Qb + Qc;
    	Calculado := SQRT((SomaP * SomaP)+ (SomaQ * SomaQ));
    	IF Calculado > 10 THEN 									// 1 kva
    		Calculado := SomaP / Calculado;
    		IF ABS(PFt - Calculado) > 0.05 THEN
    			GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    			FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_PFT_XCHECK_FAIL,bRaised:=TRUE,rParam1:=PFt,rParam2:=0.0,uMachState:= GVL_Main.MachineState);
    		END_IF
    	END_IF
    END_IF;
    
    // ═══════════════════════════════════════════════════════════════
    // 5. DETECÇÃO DE CONGELAMENTO (OPCIONAL)
    // ═══════════════════════════════════════════════════════════════
    IF NOT GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR THEN
    	IF ABS(Pt - Pt_last) < 1.0 THEN  // < 1 kW de variação
    		frozen_count := frozen_count + 1;
    	ELSE
    		frozen_count := 0;
    	END_IF
    	
    	IF frozen_count > FREEZE_THRESHOLD THEN
    		GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR := TRUE;
    		FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_FROZEN,bRaised:=TRUE,rParam1:=Pt,rParam2:=Pt_last,uMachState:= GVL_Main.MachineState);
    	END_IF
    END_IF
    
    Pt_lastatus:= Pt;
    // ═══════════════════════════════════════════════════════════════
    // 6. TRATAMENTO FINAL DE ERRO/SUCESSO
    // ═══════════════════════════════════════════════════════==══════
    IF GVL_ALARM_MANAGER.ALARM_MEAS_RANGE_ERROR THEN
    	
        nErrors := MIN(nErrors + 1, 5);	// Clamp em 5
        bDadosOK := FALSE;  // Dado atual é inválido
        
        IF nErrors < 5 THEN
            bPoucosErros := TRUE;    	// ⚠️ Ainda tolerável (1-4 erros)
        ELSE
            bPoucosErros := FALSE;   	// 🚨 Degradação crítica
        END_IF    
        // ❌ NÃO atualiza variáveis globais (mantém último valor válido)
        // ❌ NÃO reseta filtro (preserva estado anterior)  
    ELSE
    	// 1. Decrementa contador de erros (recuperação gradual)
        IF nErrors > 0 THEN
            nErrors := nErrors - 1;
        END_IF
        
        bDadosOK := TRUE;
        bPoucosErros := TRUE;
    	
        // 2. FILTRO PASSA-BAIXA (Suavização de Medição)
        // ─────────────────────────────────────────────────────────
        IF bFirstRun THEN
            Pt_filt := Pt;
            Qt_filt := Qt;
            PFt_filt := PFt;
            bFirstRun := FALSE;
        ELSE
    		// Filtro exponencial: y[n] = α·x[n] + (1-α)·y[n-1]
            // ALPHA configurável (ex: 0.25 → ~3s para 95% do valor)
            Pt_filt := GVL_Persis.ALPHA * Pt + (1.0 - GVL_Persis.ALPHA) * Pt_filt;
            Qt_filt := GVL_Persis.ALPHA * Qt + (1.0 - GVL_Persis.ALPHA) * Qt_filt;
            PFt_filt := GVL_Persis.ALPHA * PFt + (1.0 - GVL_Persis.ALPHA) * PFt_filt;
        END_IF
    	
    	// 3. ATUALIZAÇÃO DE VARIÁVEIS GLOBAIS
        // ──────────────────────────────────────────────────────────
    	GVL_Main.Ua  := Ua;				// em Volts
    	GVL_Main.Ub  := Ub;				// em Volts
    	GVL_Main.Uc  := Uc;				// em Volts
    	
    	GVL_Main.Ia  := Ia;				// em Amperes
    	GVL_Main.Ib  := Ib;				// em Amperes
    	GVL_Main.Ic  := Ic;				// em Amperes
    	
    	// Potência Ativa (FILTRADA para controle)
    	GVL_Main.Pt  := Pt_filt;			// kW
    	GVL_Main.Pa  := Pa;				// kW
    	GVL_Main.Pb  := Pb;				// kW
    	GVL_Main.Pc  := Pc;				// kW
    	
    	// Potência Reativa (FILTRADA para controle de PF)
    	GVL_Main.Qt  := Qt_filt;			// kvar
    	GVL_Main.Qa  := Qa;				// kvar
    	GVL_Main.Qb  := Qb;				// kvar
    	GVL_Main.Qc  := Qc;				// kvar
        
        // Fator de Potência (FILTRADO para controle)
    	GVL_Main.PFt := PFt_filt;				
    	GVL_Main.PFa := PFa;
    	GVL_Main.PFb := PFb;
    	GVL_Main.PFc := PFc;
    
    END_IF
    
END_FUNCTION_BLOCK
