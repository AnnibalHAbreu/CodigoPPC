(*
   FB_Controle: Bloco Principal de Controle de Exportação (Zero Grid / Limitação).
   
   OBJETIVO:
   Gerenciar a potência ativa e reativa dos inversores para garantir que a exportação 
   de energia no ponto de conexão (PCC) não ultrapasse os limites definidos na agenda.

   ESTRATÉGIA DE CONTROLE (Lógica Inversa):
   - PV (Process Variable) é o valor medido no ponto de conexão
     - Valor Positivo (+) = Importando da rede (Consumo > Geração).
     - Valor Negativo (-) = Exportando para rede (Geração > Consumo).
   - SP (Set Point) é o limite de exportação (ex: -50kW).
   - O PID atua para manter PV >= SP.
     - Se PV > SP (Importando), o PID aumenta a geração.
     - Se PV < SP (Exportando), o PID reduz a geração.
	 Controle de Exportação em kW (Zero = Autoconsumo, Negativo = Exportação, Positivo = Importação).
	Erro: SP - PV.
	Ex: Quero exportar -10kW. Medidor lê +5kW (Importando). Erro = -10 - 5 = -15.
	Para aumentar a geração (reduzir a importação), o PID precisa agir. 
	Atenção: Como o comando do inversor é sempre positivo (0..100% de geração), a lógica interna do PI deve ser Inversa (Erro negativo -> Aumenta Saída) ou ajustamos o sinal do erro na entrada.
	
	No código abaixo, a estratégia usada foi de Normalizar o Erro para "Quanto falta gerar".
	Se o medidor diz +10kW (Importando), precisamos gerar +10kW a mais.
	Se o medidor diz -20kW (Exportando muito) e o limite é -10kW, precisamos gerar 10kW a menos.
	
    Hierarquia de prioridades ou objetivos:
	
    Prioridade 1: MAXIMIZAR P (Potência Ativa)
	Objetivo: Gerar o máximo de potência ativa possível
	Limite: Exportação máxima (agenda + safety margin + limite de fase)
	Flexibilidade: RÍGIDO - nunca exceder
	
	Prioridade 2: PF ≥ 0.92 NO PONTO DE CONEXÃO
	Objetivo: Manter fator de potência ≥ 0.92 (indutivo)
	Método: Compensar Q da carga com Q dos inversores
	Flexibilidade: SOFT - sinaliza se não conseguir, mas NÃO reduz P
	
	Prioridade 3: BALANCEAMENTO DE FASES
	
    
    Ordem de execução:
	0. Leitura do medidor e ajuste dos valores para unidades corretas 
	Lê registradores Modbus, converte e armazena como variáveis Globais
	
	Dentro de FB_Controle
	1. FB_Scheduler - Define limite de exportação baseado em datas, dias de semana e horário
    2. FB_PowertController
		2.1. PI → P_cmd_raw
    	2.2. Safety Margin → P_cmd_with_margin
    	2.3. Limitador de Fase → P_cmd_limited 
    3. FB_FFQ - Feedforward de Q (estimativa inicial)
    4. FB_PIQ - Controlador PI de fator de potência
	5. FB_PAlloc - Aloca P pelos inversores 
    6. FB_QAlloc - Aloca Q pelos inversores 
	7. FB_Diagnostico
	8. STATUS DE PF
*)
FUNCTION_BLOCK FB_Controle
VAR_INPUT
    bReset : BOOL;
END_VAR

VAR
    // ════════════════════════════════════════════════════════════
    // SUBSISTEMAS (Function Blocks)
    // ════════════════════════════════════════════════════════════
    fbScheduler 			: FB_Scheduler;
    fbPowerCtrl 			: FB_PowerController;   // ✅ NOVO: Substitui fbPI + fbSafetyMargin + fbFLimiter
    fbFFQ 					: FB_FFQ;
    fbPIQ 					: FB_PIQ;
    fbPAlloc 				: FB_PAlloc;
    fbQAlloc 				: FB_QAlloc;
    fbDiagnostico 			: FB_Diagnostico;
    
    // ════════════════════════════════════════════════════════════
    // VARIÁVEIS DE TRABALHO
    // ════════════════════════════════════════════════════════════
    PF_measured 			: REAL;
    Q_cmd_kvar 				: REAL;
    Q_feedforward_kvar 		: REAL;
    bQ_limit_reached 		: BOOL := FALSE;
    bP_limit_reached 		: BOOL := FALSE;
	rPcmd_kW				: REAL;
	rPallocSum_kW			: REAL;
END_VAR

    // ════════════════════════════════════════════════════════════════
    // 0. VERIFICAÇÕES INICIAIS E INICIALIZAÇÃO
    // ════════════════════════════════════════════════════════════════
    
    // Fator de potência medido (valor absoluto)
    PF_measured := ABS(GVL_Main.PFt);
    
    // ════════════════════════════════════════════════════════════════
    // 1. FB_SCHEDULER - Define Limite de Exportação
    // ════════════════════════════════════════════════════════════════
    
    IF GVL_Persis.OperationMode THEN
    	GVL_Main.MaxExportLimit:=0;				// TRUE = Zero Grid (exportação zero)
    ELSE
    	fbScheduler();   						// Global.MaxExportLimit definido a partir das agendas de horarios no Scheduller
    END_IF
    
    // ────────────────────────────────────────────────────────────────
    // 2. CONTROLADOR DE POTÊNCIA ATIVA (PI + Safety + Limites)
    // ────────────────────────────────────────────────────────────────
    
    fbPowerCtrl(
        ExportLimit_kW := GVL_Main.MaxExportLimit,
        Feedback_kW := GVL_Main.Pt,
        bReset := bReset
    );
    
    bP_limit_reached := fbPowerCtrl.bPhase_limited OR fbPowerCtrl.bSaturated;
    // ════════════════════════════════════════════════════════════════
    // 3. FB_FFQ - Feedforward de Q 
    // ════════════════════════════════════════════════════════════════
    
    // Calcula Q necessário para manter PF = 0.92 com a potência comandada
    fbFFQ(
        P_active_kW := fbPowerCtrl.P_cmd_kW, 
        PF_target_abs := GVL_Persis.PF_target,
        PF_sign := -1.0                              // capacitivo (negativo)
    );
    
    Q_feedforward_kvar := fbFFQ.Q_reactive_kvar;  	
    
    // ════════════════════════════════════════════════════════════════
    // 4. FB_PIQ - Controle de Fator de Potência
    // ════════════════════════════════════════════════════════════════
    
    // Controlador PI de fator de potência
    fbPIQ(
        SP := GVL_Persis.PF_target,         							// Setpoint de PF (0.92)
        PV := PF_measured,              							// PF medido (absoluto)
    	Kp:= GVL_Persis.Kp_Q,
    	Ki:= GVL_Persis.Ki_Q,
    	CycleTime:= GVL_Main.ControlCycle,
        P_cmd := fbPowerCtrl.P_cmd_kW,     							// Comando de P (para referência)
        RampUp := GVL_Persis.RampUp_Q,      							// Rampa de subida (kvar/s)
        RampDown := GVL_Persis.RampDown_Q,  							// Rampa de descida (kvar/s)
        DeadbandAbs := GVL_Persis.Deadband_Q, 							// Zona morta de PF
        Reset := bReset,                 							// Reset
    	bExternal_Saturated := bQ_limit_reached OR bP_limit_reached // FEEDBACK do ciclo anterior - calculado em fbQAlloc.
    );
    
    Q_cmd_kvar := Q_feedforward_kvar + fbPIQ.MV;  // Comando de Q em kvar
    
    // Clamp superior: não pode exceder Q máximo dos inversores
    IF Q_cmd_kvar > GVL_Main.Q_max_permitido THEN
        Q_cmd_kvar := GVL_Main.Q_max_permitido;
    END_IF
    // Clamp inferior: se PF_sign = indutivo, Q não pode ser negativo
    IF Q_cmd_kvar < 0.0 THEN
        Q_cmd_kvar := 0.0;  // Não permite Q negativo (capacitivo) se não desejado
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 5. FB_PAlloc - Aloca P (PRIORIDADE MÁXIMA)
    // ══════════���═════════════════════════════════════════════════════
    
    fbPAlloc(
        P_total_cmd_kW := fbPowerCtrl.P_cmd_kW
    );
    // WARN_P_ALLOC_SATURATED = P alocado < P comandado
    rPcmd_kW:= ABS(fbPowerCtrl.P_cmd_kW);
    rPallocSum_kW:= ABS(fbPowerCtrl.P_cmd_kW);
    IF rPcmd_kW < rPallocSum_kW THEN
    	FC_LogEvent(eCode:=E_EventCode.WARN_P_ALLOC_SATURATED,bRaised:=TRUE,rParam1:=rPcmd_kW,rParam2:=rPallocSum_kW,uMachState := GVL_Main.MachineState);
    END_IF
    GVL_Main.P_allocated_kW := fbPAlloc.P_allocated_kW;
    
    // ════════════════════════════════════════════════════════════════
    // 6. FB_QAlloc - Aloca Q 
    // ════════════════════════════════════════════════════════════════
    
    fbQAlloc(
        Q_total_cmd_kvar := Q_cmd_kvar
    );
    
    GVL_Main.Q_allocated_kvar := fbQAlloc.Q_allocated_kvar;
    
    // Armazena flag de saturação para próximo ciclo
    bQ_limit_reached := fbQAlloc.bQ_limit_reached;
    
    GVL_ALARM_MANAGER.ALARM_Q_LIMITED_BY_SMAX := bQ_limit_reached;
    IF GVL_ALARM_MANAGER.ALARM_Q_LIMITED_BY_SMAX THEN
    	FC_LogEvent(eCode:=E_EventCode.WARN_Q_LIMITED_BY_SMAX,bRaised:=TRUE,rParam1:=Q_cmd_kvar,rParam2:=fbQAlloc.Q_allocated_kvar,uMachState := GVL_Main.MachineState);
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 7. FB_Diagnostico - Gera diagnóstico completo
    // ════════════════════════════════════════════════════════════════
    
    fbDiagnostico(
        P_allocated_kW := fbPAlloc.P_allocated_kW,
        Q_commanded_kvar := Q_cmd_kvar,
        Q_allocated_kvar := fbQAlloc.Q_allocated_kvar,
        Q_capacity_kvar := fbQAlloc.Q_capacity_total,
        PF_measured := PF_measured,
        PF_achieved := fbQAlloc.PF_effective,
        bQ_limited := fbQAlloc.bQ_limit_reached
    );
    
    // ────────────────────────────────────────────────────────────────
    // 8. STATUS DE PF
    // ────────────────────────────────────────────────────────────────
    GVL_ALARM_MANAGER.ALARM_PF_BELOW_TARGET:= (fbQAlloc.PF_effective < GVL_Persis.PF_target);
    IF GVL_ALARM_MANAGER.ALARM_PF_BELOW_TARGET THEN
    	FC_LogEvent(
    		eCode:=E_EventCode.WARN_PF_BELOW_TARGET,
    		bRaised:=TRUE,
    		rParam1:=fbQAlloc.PF_effective,
    		rParam2:=GVL_Persis.PF_target,
    		uMachState := GVL_Main.MachineState
    		);
    END_IF
    
END_FUNCTION_BLOCK
