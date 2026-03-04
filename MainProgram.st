// DEBUG
// {#define DEBUG_MODE}
PROGRAM MainProgram
(*
    Máquina de estados principal do controlador.
    Fluxo geral:
    START   -> READ    (quando fbStart termina com sucesso)
    READ    -> CONTROL (quando leitura Modbus do medidor conclui OK)
    READ    -> IDLE    (quando leitura falha, mas ainda não estourou RETRIES_READ)
    READ    -> FAIL    (quando leitura falha e estoura RETRIES_READ)
    CONTROL -> WRITE   (sempre, um ciclo de controle por leitura)
    WRITE   -> IDLE    (depois de tentar escrever em todos inversores, se não estourou RETRIES_WRITE)
    WRITE   -> FAIL    (se falhas de escrita estourarem RETRIES_WRITE)
    IDLE    -> READ    (quando completar 1 segundo de ciclo)
    FAIL    -> (aguarda ação do operador)
    STOP    -> (parada controlada, permanece travado)
*)

VAR
    fbStart         		: FB_Startup;        						// executa a inicialização
    fbControle      		: FB_Controle;		 						// módulo de controle
	fbChannel       		: ModbusChannel;
	fbReadMeas 				: FB_ModBus;
	fbValidaDados			: FB_ValidaDados;
    fbWriteCOM1 			: FB_WriteCom;
    fbWriteCOM2 			: FB_WriteCom;	
	
	// ══════════════════════════════════════════════════════════
    // Máquina de Estados
    // ══════════════════════════════════════════════════════════
	MachineState_Last 		: E_MachineState := E_MachineState.START;
    FailState     			: E_FailState := E_FailState.FS_INIT;
	PrevFail				: E_FailState := E_FailState.FS_INIT;
	StopState				: E_StopState := E_StopState.STOP_INIT;
	
    // ══════════════════════════════════════════════════════════
    // STOP: Trip e Reset Manual
    // ══════════════════════════════════════════════════════════
    StopInit         		: BOOL := FALSE;
    StopResetCmd      		: BOOL := FALSE;
    StopEntryTime     		: UDINT := 0;
    TripCheck      			: BOOL := TRUE;
    bResetConditionsOK		: BOOL := FALSE;
    rTrigReset        		: R_TRIG;
    tonResetWindow    		: TON;
    PrevState     			: E_MachineState := E_MachineState.START; 	// guarda o estado anterior
    ResetCOM	  			: BOOL;       								// pulso de detecção ao entrar em WRITE
    
    // ══════════════════════════════════════════════════════════
    // Timers Normativos (DIS-NOR-033)
    // ══════════════════════════════════════════════════════════
    ton15s  				: TON;   // Hard limit > 15s → STOP
    ton30s  				: TON;   // Exportação > LPI por > 30s → STOP
    tonStopTrip   				: TON;   // Confirmação K2 aberto

    // ══════════════════════════════════════════════════════════
    // Health Monitoring
    // ══════════════════════════════════════════════════════════
    MedidorOK         		: BOOL := FALSE;
    ComOK             		: BOOL := FALSE;
    Com1OK  	      		: BOOL := TRUE;
    Com2OK	        		: BOOL := TRUE;
    InvOnlineCount    		: UINT := 0;
    ScanOverrunCount  		: UINT := 0;
	TripOk        			: BOOL := FALSE;
	
    // ══════════════════════════════════════════════════════════
    // Limites Calculados
    // ══════════════════════════════════════════════════════════
    LPI_per_phase_kW  		: REAL := 0.0;
    HardLimit_mag     		: REAL := 0.0;
    LPI_mag			  		: REAL;
	Export_mag		  		: REAL;
    // ══════════════════════════════════════════════════════════
    // Validação Cruzada
    // ══════════════════════════════════════════════════════════
    Pt_Last           		: REAL := 0.0;
    P_inv_sum         		: REAL := 0.0;
    
    // ══════════════════════════════════════════════════════════
    // Leitura medidor
    // ══════════════════════════════════════════════════════════
	ContaMeasModBusErros  	: UINT := 0;
	ContaMeasModBusTimeOut	: UINT := 0;
    
    // ══════════════════════════════════════════════════════════
    // Temporização e Watchdog
    // ══════════════════════════════════════════════════════════
    tCycleStart       		: UDINT := 0;
    tCycleEnd         		: UDINT;
    tCycle            		: UDINT;
    tElapsed          		: UDINT;
    bFirstScanRead    		: BOOL := TRUE;
    MaxCycleTime      		: UDINT := 0;
    CycleTimeOverrunCount 	: UDINT := 0;

    // ══════════════════════════════════════════════════════════
    // FAIL_SAFE (STOP Timeout)
    // ══════════════════════════════════════════════════════════
    tonStopWrite      		: TON;
    tStopWrite        		: TIME := T#2S;
	tonFailSafeRecovery		: TON;   // tempo para recuperação ao normal
	tonMedidorTimeout		: TON;   // tempo que aguarda medidor sem leitura
	
    // ══════════════════════════════════════════════════════════
    // Debug/Monitor
    // ══════════════════════════════════════════════════════════
    valor             		: UN_Convert_Word_To_Real;
    auxvalor          		: REAL := 0;
    stStart, stEnd, stCiclo : SYSTIME;
    tStartCom, tCom, tEndCom: SYSTIME;
    tMax              		: SYSTIME := 0;
    Gatilho           		: BOOL := TRUE;
    rTrigOn           		: R_TRIG;
    fTrigOff          		: F_TRIG;
    Primeiravez       		: BOOL := TRUE;
    stCicloMax        		: SYSTIME := 0;
    i                 		: UINT;
    
END_VAR

    
    // ════════════════════════════════════════════════════════════════
    // MÁQUINA DE ESTADOS PRINCIPAL
    // ════════════════════════════════════════════════════════════════
    
    CASE GVL_Main.MachineState OF
    	
    // ────────────────────────────────────────────────────────────────
    // START: Inicialização (fbStart + K1/K2)
    E_MachineState.START:
        fbStart();  // Chamada do bloco de inicialização
    	
    	CASE fbStart.stState OF
    		E_StartupStatus.stInit,
            E_StartupStatus.stWait_K1,
            E_StartupStatus.stWait_K2:
            	// Permanece em START
            E_StartupStatus.stDone:
    			// Inicialização única (executada 1x após power-on)
    			FailState := E_FailState.FS_INIT;
    			TripOk := FALSE;
    			StopInit := FALSE;
    			ton15s(IN := FALSE);
    			ton30s(IN := FALSE);
    			tonStopTrip(IN := FALSE);
                (* Inicialização concluída – segue para leitura *)		
                GVL_Main.MachineState := E_MachineState.READ;
    		E_StartupStatus.stError:
    			GVL_Main.MachineState := E_MachineState.ERRO;					// ocorreu erro na inicialização do sistema
    		
    {#ifdef DEBUG_MODE}			
    GVL_Main.MachineState := E_MachineState.CONTROL;
    auxvalor:=0;
    {#endif}
    	END_CASE;
    
    // ────────────────────────────────────────────────────────────────
    // READ: Leitura do Medidor
    E_MachineState.READ:
    
        // Marca início do ciclo apenas uma vez ao entrar em READ
        IF bFirstScanRead THEN
            tCycleStart := SysTimeCore.SysTimeGetMs();
            bFirstScanRead := FALSE;
        END_IF;	
      	fbReadMeas(tTimeout := T#250MS,trigInv := GVL_Main.trigMedidor100,pSlave  := GVL_Main.pMedidor100^);
    	
    	// avalia estado do Medidor a cada ciclo
    	MedidorOK:=FALSE;
    	
    	CASE fbReadMeas.result OF
    		E_ModbusResult.DONE:
    			ContaMeasModBusErros:= 0;
    			ContaMeasModBusTimeOut:= 0;
    			fbValidaDados(Meas_Device:=GVL_Persis.MeasDeviceType);
    			MedidorOK:=fbValidaDados.bDadosOK;
    			
    			GVL_ALARM_MANAGER.ALARM_MEAS_USING_LAST_VALUEU:=fbValidaDados.bPoucosErros;
    			GVL_ALARM_MANAGER.CRIT_MEAS_PERSISTENT_FAIL:=(NOT MedidorOK AND NOT fbValidaDados.bPoucosErros);
    			
    			IF MedidorOK THEN
    				GVL_Main.MachineState := E_MachineState.CONTROL;
    			ELSE
    				// ❌ Dados inválidos
    				IF fbValidaDados.bPoucosErros THEN
    					// Erro isolado → continua sem mudar o controle - perde o ciclo de controle
    					GVL_Main.MachineState := E_MachineState.IDLE;
    					FC_LogEvent(eCode:= E_EventCode.ALARM_MEAS_USING_LAST_VALUE,bRaised:= TRUE,rParam1:= 0.0,rParam2:= 0.0,uMachState := GVL_Main.MachineState);
    				ELSE
    					// Muitos erros → degradado
    					GVL_Main.MachineState := E_MachineState.FAIL;
    					FC_LogEvent(eCode:= E_EventCode.CRIT_MEAS_PERSISTENT_FAIL,bRaised:= TRUE,rParam1:= 0.0,rParam2:= 0.0,uMachState := GVL_Main.MachineState);
    				END_IF
    			END_IF
    			
    		E_ModbusResult.ERRO:
    			ContaMeasModBusErros:= ContaMeasModBusErros + 1;
    			GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_ERRO:=(ContaMeasModBusErros > GVL_Main.MAX_Meas_MODBUS_ERROS);
    			IF GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_ERRO THEN					// permite seguir sem parar se acontecerem erros abaixo do maximo
    				GVL_Main.MachineState := E_MachineState.FAIL;
    				FC_LogEvent(eCode:= E_EventCode.CRIT_MEAS_MODBUS_ERRO,bRaised:= TRUE,rParam1:=TO_REAL(ContaMeasModBusErros),rParam2:= 0.0,uMachState:=GVL_Main.MachineState);
    			ELSE
    				GVL_Main.MachineState := E_MachineState.IDLE;
    				FC_LogEvent(eCode:= E_EventCode.ALARM_MEAS_MODBUS_ERROR,bRaised:= TRUE,rParam1:=TO_REAL(ContaMeasModBusErros),rParam2:= 0.0,uMachState:=GVL_Main.MachineState);
    			END_IF
    			
    		E_ModbusResult.TIMEOUT: 
    			ContaMeasModBusTimeOut:= ContaMeasModBusTimeOut + 1;
    			GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_TIMEOUT:=(ContaMeasModBusTimeOut > GVL_Main.MAX_Meas_MODBUS_TIMEOUTS);
    			IF GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_TIMEOUT THEN				// permite seguir sem parar se acontecerem TimeOut abaixo do maximo
    				GVL_Main.MachineState := E_MachineState.FAIL;
    				FC_LogEvent(eCode:=E_EventCode.CRIT_MEAS_MODBUS_TIMEOUT,bRaised:=TRUE,rParam1:=TO_REAL(ContaMeasModBusTimeOut),rParam2:=0.0,uMachState := GVL_Main.MachineState);
    			ELSE
    				GVL_Main.MachineState := E_MachineState.IDLE;
    				FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_MODBUS_TIMEOUT,bRaised:=TRUE,rParam1:=TO_REAL(ContaMeasModBusTimeOut),rParam2:=0.0,uMachState := GVL_Main.MachineState);
    			END_IF
    	
        END_CASE
    
    // ────────────────────────────────────────────────────────────────
    // CONTROL: Cálculo de Setpoints
    E_MachineState.CONTROL:
    
    	// Atualiza o estado anterior
    	PrevState := GVL_Main.MachineState;
    
    	fbControle(bReset:=FALSE);  
    
        GVL_Main.MachineState := E_MachineState.WRITE;
    {#ifdef DEBUG_MODE}	
    GVL_Main.MachineState := E_MachineState.CONTROL;
    {#endif}
    
    // ============================================================================
    // WRITE: Envia comandos aos Inversores (1 registro por vez / até 5 canais)
    // - COM1 e COM2 são orquestrados por FB_WriteCom (um por COM)
    // - Cada FB varre inversores 1..15 e canais 0..(nChannelsToWrite-1)
    // - Em falha não-crítica: pula inversor e continua
    // - Em falha crítica: sinaliza bCritical -> MainProgram vai para FAIL
    // ============================================================================
    
    E_MachineState.WRITE:
    
    	// Detecta borda de subida quando o estado muda PARA WRITE
    	ResetCOM := (PrevState <> E_MachineState.WRITE);
    	// Atualiza o estado anterior
    	PrevState := E_MachineState.WRITE;
    	
        // ───── DEBUG (mantido do seu padrão) ─────────────────────────────────────
        {#ifdef DEBUG_MODE}
        IF bFirstScanRead THEN
            tCycleStart := SysTimeCore.SysTimeGetMs();
            bFirstScanRead := FALSE;
        END_IF
        {#endif}
        // ─────────────────────────────────────────────────────────────────────────
    	
        // ------------------------------------------------------------------------
        // COM1 - escrever canais via triggers trigInvCOM100[inv, ch]
        // pInversores100[1..15] são POINTER TO ModbusSlaveComPort 
        // ------------------------------------------------------------------------
        fbWriteCOM1(
    		Reset		 	 := ResetCOM,
            tTimeout         := T#100MS,
            nInverters       := GVL_Main.NInversoresCOM01,
            nChannelsToWrite := GVL_Main.nChannelsToWriteCOM1,
            maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
            maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
            trigInv          := GVL_Main.trigInvCOM100, 
            pInvPtr          := GVL_Main.pInversores100
        );
    
        // ------------------------------------------------------------------------
        // COM2 - escrever canais via triggers trigInvCOM200[inv, ch]
        // pInversores200[1..15] são POINTER TO ModbusSlaveComPort
        // ------------------------------------------------------------------------
        fbWriteCOM2(
    		Reset		 	 := ResetCOM,
            tTimeout         := T#100MS,
            nInverters       := GVL_Main.NInversoresCOM02,
            nChannelsToWrite := GVL_Main.nChannelsToWriteCOM2,
            maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
            maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
            trigInv          := GVL_Main.trigInvCOM200,
            pInvPtr          := GVL_Main.pInversores200
        );
    
        // ------------------------------------------------------------------------
        // Escalada para FAIL (crítico)
        // Observação: aqui você decide quais flags/eventos setar para erro vs timeout.
        // O FB fornece LastFailRes (ERRO ou TIMEOUT) + LastFailInv + LastFailCh.
        // ------------------------------------------------------------------------
        IF fbWriteCOM1.bCritical THEN
    
    		GVL_ALARM_MANAGER.CRIT_CH1_MODBUS_TIMEOUT:=(fbWriteCOM1.FailRes = E_ModbusResult.TIMEOUT);
    		GVL_ALARM_MANAGER.CRIT_CH1_MODBUS_ERRO :=(fbWriteCOM1.FailRes = E_ModbusResult.ERRO);
    		
            IF GVL_ALARM_MANAGER.CRIT_CH1_MODBUS_TIMEOUT THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH1_MODBUS_TIMEOUT,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM1.TmoCount),
                    rParam2    := TO_REAL(fbWriteCOM1.LastFailInv),
                    uMachState := GVL_Main.MachineState
                );
    		END_IF
            IF GVL_ALARM_MANAGER.CRIT_CH1_MODBUS_ERRO THEN 
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH1_MODBUS_ERRO,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM1.ErrCount),
                    rParam2    := TO_REAL(fbWriteCOM1.LastFailInv),
                    uMachState := GVL_Main.MachineState
                );
            END_IF
            GVL_Main.MachineState := E_MachineState.FAIL;
    		RETURN;
        END_IF
    
        IF fbWriteCOM2.bCritical THEN
    
    		GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_TIMEOUT:=(fbWriteCOM2.FailRes = E_ModbusResult.TIMEOUT);
    		GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_ERRO :=(fbWriteCOM2.FailRes = E_ModbusResult.ERRO);
    		
            IF GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_TIMEOUT THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH2_MODBUS_TIMEOUT,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM2.TmoCount),
                    rParam2    := TO_REAL(fbWriteCOM2.LastFailInv),
                    uMachState := GVL_Main.MachineState
                );
    		END_IF
            IF GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_ERRO THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH2_MODBUS_ERRO,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM2.ErrCount),
                    rParam2    := TO_REAL(fbWriteCOM2.LastFailInv),
                    uMachState := GVL_Main.MachineState
                );
            END_IF
            GVL_Main.MachineState := E_MachineState.FAIL;
    		RETURN;
        END_IF
    
        // ------------------------------------------------------------------------
        // Conclusão do WRITE: ambos COM terminaram a varredura
        // ------------------------------------------------------------------------
        IF fbWriteCOM1.Done AND fbWriteCOM2.Done THEN
            GVL_Main.MachineState := E_MachineState.IDLE;
            RETURN;
        END_IF
    
    // ────────────────────────────────────────────────────────────────
    // IDLE: Aguarda Completar Ciclo (1s)			
    E_MachineState.IDLE:
    //  Aguarda completar período de ciclo (1 segundo) depois de
    	IF tCycleStart <> 0 THEN
        	tElapsed := SysTimeCore.SysTimeGetMs() - tCycleStart; 					// Calcula tempo desde início do ciclo
    	END_IF;
    	IF tElapsed >= GVL_Main.CYCLE_TIME_MS THEN
    		GVL_Main.MachineState := E_MachineState.READ;
    		bFirstScanRead := TRUE;
           	// Atualiza estatísticas
           	IF tElapsed > MaxCycleTime THEN
               MaxCycleTime := tElapsed;
           	END_IF;  
    
    	GVL_ALARM_MANAGER.ALARM_SCAN_OVERRUN:=(tElapsed > GVL_Main.CYCLE_TIME_TOLERANCE);
    	IF GVL_ALARM_MANAGER.ALARM_SCAN_OVERRUN THEN
    		ScanOverrunCount := ScanOverrunCount + 1;
    		FC_LogEvent(eCode:=E_EventCode.ALARM_SCAN_OVERRUN,bRaised:=TRUE,
    							rParam1:=0.0,rParam2:=0.0,uMachState := GVL_Main.MachineState);
    							
    		GVL_ALARM_MANAGER.CRIT_SCAN_OVERRUN:=(ScanOverrunCount >= 3);
    		IF GVL_ALARM_MANAGER.CRIT_SCAN_OVERRUN THEN
    		FC_LogEvent(eCode:=E_EventCode.CRIT_SCAN_OVERRUN,bRaised:=TRUE,
    							rParam1:=0.0,rParam2:=0.0,uMachState := GVL_Main.MachineState);
    			GVL_Main.MachineState := E_MachineState.FAIL;
    			ScanOverrunCount := 0;
    		END_IF
    	ELSE
    		ScanOverrunCount := 0;
    	END_IF
    {#ifdef DEBUG_MODE}
    		GVL_Main.MachineState := E_MachineState.CONTROL;
    {#endif}
    	END_IF;
    
    // ────────────────────────────────────────────────────────────────
    E_MachineState.FAIL:
    // ESTADO FAIL — Redução forçada (norma DIS-NOR-033)
    // ton15s: P > LPI + 10% Pnom por >15s → STOP
    // ton30s: P > LPI por >30s → STOP
    
        // ══════════════════════════════════════════════════════════
        // TIMERS NORMATIVOS (monitorados TODO CICLO)
        // Cálculo do hard limit
    	LPI_mag := ABS(GVL_Main.MaxExportLimit);
    	Export_mag := MAX(0, -GVL_Main.Pt);
        HardLimit_mag := LPI_mag + (GVL_Main.InstalledPower * 0.1);
    	
        // Mantém leitura do medidor (diagnóstico)
      	fbReadMeas(tTimeout := T#250MS,trigInv:=GVL_Main.trigMedidor100,pSlave:=GVL_Main.pMedidor100^);
    	
    	// ✅ CORREÇÃO: Atualiza MedidorOK dentro de FAIL
        MedidorOK:=fbValidaDados.bDadosOK;	
    	
        // ── TIMER 15s: hard limit (P > LPI + 10% Pnom) ──
    
        ton15s(IN := Export_mag > HardLimit_mag, PT := T#15S);
    
        // ── TIMER 30s: exportação persistente (P > LPI) ──
        ton30s(IN := (Export_mag > LPI_mag), PT := T#30S);
    	
        // ── Escalada para STOP ──
        IF ton15s.Q OR ton30s.Q THEN
    		IF ton15s.Q THEN
    			GVL_ALARM_MANAGER.CRIT_HARDLIMIT_15S:=ton15s.Q;
    			FC_LogEvent(eCode:=E_EventCode.CRIT_HARDLIMIT_15S,bRaised:=TRUE,
    				rParam1:=Export_mag,rParam2:=HardLimit_mag,uMachState := GVL_Main.MachineState);
    			// SINALIZA ERRO hard limit: P > LPI + 10% Pnom por >15s
    		ELSIF ton30s.Q THEN
    			GVL_ALARM_MANAGER.CRIT_EXPORT_OVER_LPI_30S:=ton30s.Q;
    			FC_LogEvent(eCode:=E_EventCode.CRIT_EXPORT_OVER_LPI_30S,bRaised:=TRUE,
    				rParam1:=Export_mag,rParam2:=LPI_mag,uMachState := GVL_Main.MachineState);
    			// SINALIZA ERRO exportação > LPI por >30s
    		END_IF
            GVL_Main.MachineState := E_MachineState.STOP;
            RETURN;
        END_IF
    
        // ══════════════════════════════════════════════════════════
        // SUB-ESTADOS SIMPLIFICADOS
        CASE FailState OF
    
            E_FailState.FS_INIT:
    		
    			// Sinalização
    			GVL_Main.LedYellowOut := TRUE;
    			GVL_Main.LedGreenOut := FALSE;
                // Reinicializa índices de escrita
    			tonFailSafeRecovery(IN := FALSE);
    			tonMedidorTimeout(IN := FALSE); 
                // Zera setpoints
                FOR i := 1 TO GVL_Main.NMAXINVERSORES DO
                    GVL_Main.P_inv_kW[i] := 0.0;
                    GVL_Main.P_inv_Percent[i] := 0.0;
                    GVL_Main.Q_inv_kvar[i] := 0.0;
                END_FOR
    			PrevFail := FailState;   
                FailState := E_FailState.FS_FORCE_ZERO;			
    
            E_FailState.FS_FORCE_ZERO:
                // Escreve zero em todos os inversores (mesmo código do WRITE, simplificado)
    		// Detecta borda de subida quando o estado muda PARA WRITE
    			ResetCOM := (PrevFail <> E_FailState.FS_FORCE_ZERO);
    			// Atualiza o estado anterior
    			PrevFail := FailState;   
    			fbWriteCOM1(
    				Reset		 	 := ResetCOM,
    				tTimeout         := T#100MS,
    				nInverters       := GVL_Main.NInversoresCOM01,
    				nChannelsToWrite := GVL_Main.nChannelsToWriteCOM1,
    				maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
    				maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
    				trigInv          := GVL_Main.trigInvCOM100, 
    				pInvPtr          := GVL_Main.pInversores100
    			);
    
    			fbWriteCOM2(
    				Reset		 	 := ResetCOM,
    				tTimeout         := T#100MS,
    				nInverters       := GVL_Main.NInversoresCOM02,
    				nChannelsToWrite := GVL_Main.nChannelsToWriteCOM2,
    				maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
    				maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
    				trigInv          := GVL_Main.trigInvCOM200,
    				pInvPtr          := GVL_Main.pInversores200
    			);          
    			IF fbWriteCOM1.Done AND fbWriteCOM2.Done THEN
                	FailState := E_FailState.FS_VALIDATE;	
    				RETURN;
    			END_IF
    
            E_FailState.FS_VALIDATE:
                // Recuperação: P dentro da zona de controle (≤ LPI + 10% Pnom)
    
                IF (fbReadMeas.result = E_ModbusResult.DONE) AND (Export_mag <= LPI_mag) AND MedidorOK THEN
    			   
    				// ✅ Condições OK: precisa manter a condição por 10 segundos para considerar recuperado
    				tonFailSafeRecovery(IN := TRUE, PT := T#10S);
                    IF tonFailSafeRecovery.Q THEN
                        // Recuperação automática
                        FailState := E_FailState.FS_INIT;
                        GVL_Main.MachineState := E_MachineState.READ;
                        ton15s(IN := FALSE);
                        ton30s(IN := FALSE);
    					tonMedidorTimeout(IN := FALSE);
                		tonFailSafeRecovery(IN := FALSE);
                        GVL_Main.LedYellowOut := FALSE;
                    END_IF				
                ELSE
            		// ❌ Condições NÃO OK: reseta recuperação e testa timeout
                    tonFailSafeRecovery(IN := FALSE);
    				// ❌ TIMEOUT de medidor (5s sem leitura válida)
                    tonMedidorTimeout(IN := (fbReadMeas.result <> E_ModbusResult.DONE), PT := T#5S);
    
                    IF tonMedidorTimeout.Q THEN
    					// ❌ STOP: Perda de visibilidade da planta
                        // Sinaliza  16#E3;
                        StopState := E_StopState.STOP_INIT;
    					GVL_Main.MachineState := E_MachineState.STOP;
    					tonMedidorTimeout(IN := FALSE);  // Reset timer
            			RETURN;
                    END_IF
                END_IF
        END_CASE
    
    // ────────────────────────────────────────────────────────────────
    E_MachineState.STOP:
    
        // ────────────────────────────────────────────────────────────────
        // A. ENTRADA EM STOP (primeira execução)
    	
    	CASE StopState OF 
    	// Sinaliza entrada em STOP
        E_StopState.STOP_INIT:
    
            tonStopTrip(IN := FALSE);                  // garante timer resetado
            StopResetCmd := FALSE;               // evita saída imediata por comando antigo
    		
            // Trip imediato
            GVL_Main.K2_out := TRUE;									// aciona K2 - trip do disjuntor
            GVL_Main.K1_out := FALSE;									// desliga K1 bobina de minima tensão ou contator se existente
    		
    		// Sinalização
            GVL_Main.LedRedOut := TRUE;									// indica disjuntor desligado e houve trip
            GVL_Main.LedYellowOut := FALSE;
            GVL_Main.LedGreenOut := FALSE;
    		
    		GVL_ALARM_MANAGER.CRIT_K2_NOT_OPENED :=FALSE;
    					
    		StopState:= E_StopState.STOP_TRIP;
    	   
    	// ────────────────────────────────────────────────────────────────
        // B. Aguarda 2 segundos para verificar acionamento de K2 (executa apenas 1 vez)
    
        E_StopState.STOP_TRIP: 
    	
            tonStopTrip(IN := TRUE, PT := T#2S);
            
            IF tonStopTrip.Q THEN
                tonStopTrip(IN := FALSE);
                
    			GVL_ALARM_MANAGER.CRIT_K2_NOT_OPENED := GVL_Main.K2_in;		// se K2=TRUE => K2 não tripou
    			
                IF (GVL_ALARM_MANAGER.CRIT_K2_NOT_OPENED) THEN
    				// Sinaliza Trip não aconteceu;
    				FC_LogEvent(eCode := E_EventCode.CRIT_K2_NOT_OPENED,bRaised := TRUE,rParam1 := 0.0,rParam2 := 0.0,uMachState := GVL_Main.MachineState);
                ELSE
                    // Sinaliza Trip aconteceu;
    				FC_LogEvent(eCode := E_EventCode.INFO_STOP_K2_OPEN_CONFIRMED,bRaised := TRUE,rParam1 := 0.0,rParam2 := 0.0,uMachState := GVL_Main.MachineState);
                END_IF
    			
    			StopState:= E_StopState.STOP_LATCHED;
    			
            END_IF
        
    	// ────────────────────────────────────────────────────────────────
        // C. AGUARDA RESET MANUAL PELO OPERADOR
    
        E_StopState.STOP_LATCHED:
     
    		rTrigReset(CLK := StopResetCmd OR GVL_Main.BotaoReset);									// comandado pela IHM ou por botão frontal
        	
    		IF rTrigReset.Q THEN																	// Borda de subida: avalia condições básicas UMA VEZ
    			StopResetCmd := FALSE;
    			StopState:= E_StopState.STOP_INIT;													// prepara próxima entrada
    			GVL_Main.MachineState := E_MachineState.START;
    		END_IF       
    
    // ────────────────────────────────────────────────────────────────
    E_MachineState.ERRO:
    	// não faz nada, fica aguardando reset geral
    	// mandar mensagem de erro para a IHM
    	GVL_Main.LedRedOut := TRUE;				// indica que houve falha
        GVL_Main.LedYellowOut := FALSE;
        GVL_Main.LedGreenOut := FALSE;
    	
    END_CASE
    
END_PROGRAM
