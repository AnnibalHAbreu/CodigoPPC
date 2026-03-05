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
  	fbTurnOff 				: FB_TurnOff;	
	
	// ══════════════════════════════════════════════════════════
    // Máquina de Estados
    // ══════════════════════════════════════════════════════════
	NextState		 		: E_MachineState := E_MachineState.START;
	CurrentState			: E_MachineState := E_MachineState.START;
    FailState     			: E_FailState := E_FailState.FS_INIT;
	PrevFail				: E_FailState := E_FailState.FS_INIT;
	StopState				: E_StopState := E_StopState.STOP_INIT;
	
    // ══════════════════════════════════════════════════════════
    // STOP: Trip e Reset Manual
    // ══════════════════════════════════════════════════════════
    StopResetCmd      		: BOOL := FALSE;
    PrevState     			: E_MachineState := E_MachineState.START; 	// guarda o estado anterior
    ResetCOM_Write   		: BOOL;       								// pulso de detecção ao entrar em WRITE
	ResetCOM_FailSafe   	: BOOL;       								// pulso de detecção ao entrar em WRITE
    
	// ══════════════════════════════════════════════════════════
	// IHM triggers
	// ══════════════════════════════════════════════════════════
    rTrigStartReset 		: R_TRIG;
    rTrigTurnOff    		: R_TRIG;
	xStartResetEdge  : BOOL;
	xTurnOffEdge     : BOOL;
	
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
    Pt_Lastatus          		: REAL := 0.0;
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
	FailWriteRetryCount    	: UINT := 0;           // Contador de tentativas de escrita zero
	MAX_FAIL_WRITE_RETRIES 	: UINT := 3;           // Máximo de tentativas (CONST)
	RecoveryCycleCount     	: UINT := 0;           // Ciclos consecutivos com recuperação OK
	RECOVERY_CYCLES        	: UINT := 10;          // Ciclos necessários (CONST)
	tonFailGlobalTimeout   	: TON;                 // Timer global de permanência em FAIL
	FAIL_MAX_DURATION      	: TIME := T#120S;      // Tempo máximo em FAIL (CONST)
	bMeasRecovered         	: BOOL := FALSE;
	bExportOK              	: BOOL := FALSE;  
	bComRecovered         	: BOOL := FALSE;
	bAllRecoveryOK         	: BOOL := FALSE;
	bRecoveryApproved      	: BOOL := FALSE;
	bFailInitDone          	: BOOL := FALSE;       // Evita re-execução de FS_INIT
	
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
    // IHM TRIGGERs dos botões
    // ════════════════════════════════════════════════════════════════
    
    // Start/Reset (IHM)
    rTrigStartReset(CLK := GVL_Main.HMI_StartResetButton);
    IF rTrigStartReset.Q THEN
        GVL_Main.HMI_StartResetButton := FALSE;   // consome IHM
    END_IF
    xStartResetEdge := rTrigStartReset.Q;
    
    // TurnOff (IHM)
    rTrigTurnOff(CLK := GVL_Main.HMI_TurnOffButton);
    IF rTrigTurnOff.Q THEN
        GVL_Main.HMI_TurnOffButton := FALSE;      // consome IHM
    END_IF
    xTurnOffEdge := rTrigTurnOff.Q;
    
    // ════════════════════════════════════════════════════════════════
    // MÁQUINA DE ESTADOS PRINCIPAL
    // ════════════════════════════════════════════════════════════════
    
    CurrentState := GVL_Main.MachineState;
    NextState := CurrentState;
    
    CASE CurrentState OF
    
    E_MachineState.TURNOFF:
    
        // mantém medição viva
        fbReadMeas(tTimeout := T#250MS,trigInv  := GVL_Main.trigMedidor100,pSlave:= GVL_Main.pMedidor100^);
    	
        IF fbReadMeas.result = E_ModbusResult.DONE THEN
            fbValidaDados(Meas_Device := GVL_Persis.MeasDeviceType);
        END_IF
    
        fbTurnOff(
            xEnable          := TRUE,
            xStartResetEdge  := xStartResetEdge,
            xK2_in           := GVL_Main.K2_in,
            rPt_kW           := GVL_Main.Pt,
            xMeasDataOK      := fbValidaDados.bDadosOK,
            rP_Threshold_kW  := REAL#0.5,
            tVerifyTimeout   := T#30S,
            tK2Timeout       := T#2S,
            uMaxWriteRetries := UINT#3,
            xCom1Done        := fbWriteCOM1.Done,
            xCom1Critical    := fbWriteCOM1.bCritical,
            xCom2Done        := fbWriteCOM2.Done,
            xCom2Critical    := fbWriteCOM2.bCritical
        );
    
        // ações (OPÇÃO B)
        IF fbTurnOff.xReqZeroSetpoints THEN
            FOR i := 1 TO GVL_Main.NMAXINVERSORES DO
                GVL_Main.P_inv_kW[i]      := 0.0;
                GVL_Main.P_inv_Percent[i] := 0.0;
                GVL_Main.Q_inv_kvar[i]    := 0.0;
            END_FOR
        END_IF
    
        IF fbTurnOff.xReqResetPI THEN
            fbControle(bReset := TRUE);
        END_IF
    
        // MODO 1: escrever zero só quando habilitado
        IF fbTurnOff.xWriteZeroEnable THEN
            fbWriteCOM1(
                Reset            := fbTurnOff.xReqResetCOM,
                tTimeout         := T#100MS,
                nInverters       := GVL_Main.NInversoresCOM01,
                nChannelsToWrite := GVL_Main.nChannelsToWriteCOM1,
                maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
                maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
                trigInv          := GVL_Main.trigInvCOM100,
                pInvPtr          := GVL_Main.pInversores100
            );
    
            fbWriteCOM2(
                Reset            := fbTurnOff.xReqResetCOM,
                tTimeout         := T#100MS,
                nInverters       := GVL_Main.NInversoresCOM02,
                nChannelsToWrite := GVL_Main.nChannelsToWriteCOM2,
                maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
                maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
                trigInv          := GVL_Main.trigInvCOM200,
                pInvPtr          := GVL_Main.pInversores200
            );
        ELSE
            fbWriteCOM1(Reset := TRUE);
            fbWriteCOM2(Reset := TRUE);
        END_IF
    
        IF fbTurnOff.xLogEvent THEN
            FC_LogEvent(
                eCode      := fbTurnOff.eLogCode,
                bRaised    := TRUE,
                rParam1    := fbTurnOff.rLogParam1,
                rParam2    := fbTurnOff.rLogParam2,
                uMachState := CurrentState
            );
        END_IF
    
        // aplica saídas
        GVL_Main.K1_out := fbTurnOff.xK1_out;
        GVL_Main.K2_out := fbTurnOff.xK2_out;
        GVL_Main.LedRedOut    := fbTurnOff.xLedRed;
        GVL_Main.LedYellowOut := fbTurnOff.xLedYellow;
        GVL_Main.LedGreenOut  := fbTurnOff.xLedGreen;
    
        IF fbTurnOff.xRequestStop THEN
            NextState := E_MachineState.STOP;
        ELSIF fbTurnOff.xRequestStart THEN
            NextState := E_MachineState.START;
        ELSE
            NextState := E_MachineState.TURNOFF;
        END_IF
    
    
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
    			ton15s(IN := FALSE);
    			ton30s(IN := FALSE);
    			tonStopTrip(IN := FALSE);
                (* Inicialização concluída – segue para leitura *)		
                NextState := E_MachineState.READ;
    		E_StartupStatus.stError:
    			NextState := E_MachineState.ERRO;					// ocorreu erro na inicialização do sistema
    		
    {#ifdef DEBUG_MODE}			
    NextState := E_MachineState.CONTROL;
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
    				NextState := E_MachineState.CONTROL;
    			ELSE
    				// ❌ Dados inválidos
    				IF fbValidaDados.bPoucosErros THEN
    					// Erro isolado → continua sem mudar o controle - perde o ciclo de controle
    					NextState := E_MachineState.IDLE;
    					FC_LogEvent(eCode:= E_EventCode.ALARM_MEAS_USING_LAST_VALUE,bRaised:= TRUE,rParam1:= 0.0,rParam2:= 0.0,uMachState := CurrentState);
    				ELSE
    					// Muitos erros → degradado
    					NextState := E_MachineState.FAIL;
    					FC_LogEvent(eCode:= E_EventCode.CRIT_MEAS_PERSISTENT_FAIL,bRaised:= TRUE,rParam1:= 0.0,rParam2:= 0.0,uMachState := CurrentState);
    				END_IF
    			END_IF
    			
    		E_ModbusResult.ERRO:
    			ContaMeasModBusErros:= ContaMeasModBusErros + 1;
    			GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_ERRO:=(ContaMeasModBusErros > GVL_Main.MAX_Meas_MODBUS_ERROS);
    			
    			IF GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_ERRO THEN					// permite seguir sem parar se acontecerem erros abaixo do maximo
    				NextState := E_MachineState.FAIL;
    				FC_LogEvent(eCode:= E_EventCode.CRIT_MEAS_MODBUS_ERRO,bRaised:= TRUE,rParam1:=TO_REAL(ContaMeasModBusErros),rParam2:= 0.0,uMachState:=CurrentState);
    			ELSE
    				NextState := E_MachineState.IDLE;
    				FC_LogEvent(eCode:= E_EventCode.ALARM_MEAS_MODBUS_ERROR,bRaised:= TRUE,rParam1:=TO_REAL(ContaMeasModBusErros),rParam2:= 0.0,uMachState:=CurrentState);
    			END_IF
    			
    		E_ModbusResult.TIMEOUT: 
    			ContaMeasModBusTimeOut:= ContaMeasModBusTimeOut + 1;
    			GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_TIMEOUT:=(ContaMeasModBusTimeOut > GVL_Main.MAX_Meas_MODBUS_TIMEOUTS);
    			
    			IF GVL_ALARM_MANAGER.CRIT_MEAS_MODBUS_TIMEOUT THEN				// permite seguir sem parar se acontecerem TimeOut abaixo do maximo
    				NextState := E_MachineState.FAIL;
    				FC_LogEvent(eCode:=E_EventCode.CRIT_MEAS_MODBUS_TIMEOUT,bRaised:=TRUE,rParam1:=TO_REAL(ContaMeasModBusTimeOut),rParam2:=0.0,uMachState := CurrentState);
    			ELSE
    				NextState := E_MachineState.IDLE;
    				FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_MODBUS_TIMEOUT,bRaised:=TRUE,rParam1:=TO_REAL(ContaMeasModBusTimeOut),rParam2:=0.0,uMachState := CurrentState);
    			END_IF
    	
        END_CASE
    
    // ────────────────────────────────────────────────────────────────
    // CONTROL: Cálculo de Setpoints
    E_MachineState.CONTROL:
    
    	fbControle(bReset:=FALSE);  
    
        NextState := E_MachineState.WRITE;
    {#ifdef DEBUG_MODE}	
    NextState := E_MachineState.CONTROL;
    {#endif}
    
    // ============================================================================
    // WRITE: Envia comandos aos Inversores (1 registro por vez / até 5 canais)
    // - COM1 e COM2 são orquestrados por FB_WriteCom (um por COM)
    // - Cada FB varre inversores 1..15 e canais 0..(nChannelsToWrite-1)
    // - Em falha não-crítica: pula inversor e continua
    // - Em falha crítica: sinaliza bCritical -> MainProgram vai para FAIL
    // ============================================================================
    
    E_MachineState.WRITE:
    	
        ResetCOM_Write := (PrevState <> E_MachineState.WRITE);
    	
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
    		Reset		 	 := ResetCOM_Write,
            tTimeout         := T#100MS,
            nInverters       := GVL_Main.NInversoresCOM01,
            nChannelsToWrite := GVL_Main.nChannelsToWriteCOM1,
            maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
            maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
            trigInv          := GVL_Main.trigInvCOM100, 
            pInvPtr          := GVL_Main.pInversores100
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
                    uMachState := CurrentState
                );
    		END_IF
            IF GVL_ALARM_MANAGER.CRIT_CH1_MODBUS_ERRO THEN 
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH1_MODBUS_ERRO,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM1.ErrCount),
                    rParam2    := TO_REAL(fbWriteCOM1.LastFailInv),
                    uMachState := CurrentState
                );
            END_IF
            NextState := E_MachineState.FAIL;
    		
        END_IF
    	
    	// ------------------------------------------------------------------------
        // COM2 - escrever canais via triggers trigInvCOM200[inv, ch]
        // pInversores200[1..15] são POINTER TO ModbusSlaveComPort
        // ------------------------------------------------------------------------
        fbWriteCOM2(
    		Reset		 	 := ResetCOM_Write,
            tTimeout         := T#100MS,
            nInverters       := GVL_Main.NInversoresCOM02,
            nChannelsToWrite := GVL_Main.nChannelsToWriteCOM2,
            maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
            maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
            trigInv          := GVL_Main.trigInvCOM200,
            pInvPtr          := GVL_Main.pInversores200
        );
    
        IF fbWriteCOM2.bCritical THEN
    
    		GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_TIMEOUT:=(fbWriteCOM2.FailRes = E_ModbusResult.TIMEOUT);
    		GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_ERRO :=(fbWriteCOM2.FailRes = E_ModbusResult.ERRO);
    		
            IF GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_TIMEOUT THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH2_MODBUS_TIMEOUT,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM2.TmoCount),
                    rParam2    := TO_REAL(fbWriteCOM2.LastFailInv),
                    uMachState := CurrentState
                );
    		END_IF
            IF GVL_ALARM_MANAGER.CRIT_CH2_MODBUS_ERRO THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH2_MODBUS_ERRO,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM2.ErrCount),
                    rParam2    := TO_REAL(fbWriteCOM2.LastFailInv),
                    uMachState := CurrentState
                );
            END_IF
            NextState := E_MachineState.FAIL;
    
        END_IF
    
        // ------------------------------------------------------------------------
        // Conclusão do WRITE: ambos COM terminaram a varredura
        // ------------------------------------------------------------------------
        IF fbWriteCOM1.Done AND fbWriteCOM2.Done THEN
            NextState := E_MachineState.IDLE;
    
        END_IF
    
    // ────────────────────────────────────────────────────────────────
    // IDLE: Aguarda Completar Ciclo (1s)			
    E_MachineState.IDLE:
    //  Aguarda completar período de ciclo (1 segundo) depois de
    	IF tCycleStart <> 0 THEN
        	tElapsed := SysTimeCore.SysTimeGetMs() - tCycleStart; 					// Calcula tempo desde início do ciclo
    	END_IF;
    	
    	IF tElapsed >= GVL_Main.CYCLE_TIME_MS THEN
    		NextState := E_MachineState.READ;
    		bFirstScanRead := TRUE;
           	// Atualiza estatísticas
           	IF tElapsed > MaxCycleTime THEN
               MaxCycleTime := tElapsed;
           	END_IF;  
    
    	GVL_ALARM_MANAGER.ALARM_SCAN_OVERRUN:=(tElapsed > GVL_Main.CYCLE_TIME_TOLERANCE);
    	IF GVL_ALARM_MANAGER.ALARM_SCAN_OVERRUN THEN
    		
    		ScanOverrunCount := ScanOverrunCount + 1;
    		
    		FC_LogEvent(eCode:=E_EventCode.ALARM_SCAN_OVERRUN,bRaised:=TRUE,
    							rParam1:=0.0,rParam2:=0.0,uMachState := CurrentState);
    							
    		GVL_ALARM_MANAGER.CRIT_SCAN_OVERRUN:=(ScanOverrunCount >= 3);
    		IF GVL_ALARM_MANAGER.CRIT_SCAN_OVERRUN THEN
    		FC_LogEvent(eCode:=E_EventCode.CRIT_SCAN_OVERRUN,bRaised:=TRUE,
    							rParam1:=0.0,rParam2:=0.0,uMachState := CurrentState);
    			NextState := E_MachineState.FAIL;
    			ScanOverrunCount := 0;
    		END_IF
    	ELSE
    		ScanOverrunCount := 0;
    	END_IF
    {#ifdef DEBUG_MODE}
    		NextState := E_MachineState.CONTROL;
    {#endif}
    	END_IF;
    
    // ────────────────────────────────────────────────────────────────
    E_MachineState.FAIL:
    // ESTADO FAIL — Redução forçada (norma DIS-NOR-033)
    // Fluxo: FS_INIT → FS_FORCE_ZERO → FS_VALIDATE → (recupera ou STOP)
    // ton15s: P > LPI + 10% Pnom por >15s → STOP
    // ton30s: P > LPI por >30s → STOP
    
        // ────────────────────────────────────────────────────────────────
    	// A. CÁLCULOS INDEPENDENTES DE SUB-ESTADO (executam TODO ciclo)
    
        // Cálculo do hard limit
    	LPI_mag := ABS(GVL_Main.MaxExportLimit);
    	Export_mag := MAX(0, -GVL_Main.Pt);
        HardLimit_mag := LPI_mag + (GVL_Main.InstalledPower * 0.1);
    	
        // Mantém leitura do medidor (diagnóstico)
      	fbReadMeas(tTimeout := T#250MS,trigInv:=GVL_Main.trigMedidor100,pSlave:=GVL_Main.pMedidor100^);
    	
    	// Atualiza MedidorOK
    	IF fbReadMeas.result = E_ModbusResult.DONE THEN
    		fbValidaDados(Meas_Device := GVL_Persis.MeasDeviceType);
    		MedidorOK := fbValidaDados.bDadosOK;
    	ELSE
    		MedidorOK := FALSE; 
    	END_IF;
    	
        // ────────────────────────────────────────────────────────────────
        // B. ATUALIZA TODOS OS TIMERS (executam TODO ciclo)
        //    Apenas atualiza — a DECISÃO é feita abaixo na cadeia IF
    
        tonFailGlobalTimeout(IN := TRUE, PT := FAIL_MAX_DURATION);
        ton15s(IN := MedidorOK AND (Export_mag > HardLimit_mag), PT := T#15S);
        ton30s(IN := MedidorOK AND (Export_mag > LPI_mag), PT := T#30S);	
    	
        // ────────────────────────────────────────────────────────────────
        // C. CADEIA DE DECISÃO COM PRIORIDADE EXPLÍCITA
        //    IF/ELSIF garante que apenas UMA decisão prevalece
        //    Prioridade: Global > HardLimit > Export30s > SubEstados
    
        // ── PRIORIDADE 1: Timeout global (preso em FAIL por tempo demais)
        IF tonFailGlobalTimeout.Q THEN
            FC_LogEvent(eCode:=E_EventCode.CRIT_FAIL_GLOBAL_TIMEOUT, bRaised:=TRUE,
                rParam1:=Export_mag, rParam2:=LPI_mag, uMachState := CurrentState);
            GVL_ALARM_MANAGER.CRIT_FAIL_GLOBAL_TIMEOUT := TRUE;
            tonFailGlobalTimeout(IN := FALSE);
            NextState := E_MachineState.STOP;										// Não processa o resto — sai imediatamente
    	
        // ── PRIORIDADE 2: Hard limit 15s (P > LPI + 10% Pnom)
        ELSIF ton15s.Q THEN
            GVL_ALARM_MANAGER.CRIT_HARDLIMIT_15S := TRUE;
            FC_LogEvent(eCode:=E_EventCode.CRIT_HARDLIMIT_15S, bRaised:=TRUE,
                rParam1:=Export_mag, rParam2:=HardLimit_mag, uMachState := CurrentState);
            NextState := E_MachineState.STOP;
    
        // ── PRIORIDADE 3: Exportação > LPI por > 30s
        ELSIF ton30s.Q THEN
            GVL_ALARM_MANAGER.CRIT_EXPORT_OVER_LPI_30S := TRUE;
            FC_LogEvent(eCode:=E_EventCode.CRIT_EXPORT_OVER_LPI_30S, bRaised:=TRUE,
                rParam1:=Export_mag, rParam2:=LPI_mag, uMachState := CurrentState);
            NextState := E_MachineState.STOP;
    	
        // ── PRIORIDADE 4: Sub-estados (nenhuma condição de STOP imediata) ──
    
        ELSE
    		// SUB-ESTADOS SIMPLIFICADOS
    		CASE FailState OF
    	
    			E_FailState.FS_INIT:
    			
    				GVL_Main.LedYellowOut := TRUE;										// Sinalização
    				GVL_Main.LedGreenOut := FALSE;
    
    				tonFailSafeRecovery(IN := FALSE);									// Reinicializa índices de escrita
    				tonMedidorTimeout(IN := FALSE); 
    				RecoveryCycleCount := 0;
    
                    IF NOT bFailInitDone THEN
                        FOR i := 1 TO GVL_Main.NMAXINVERSORES DO
                            GVL_Main.P_inv_kW[i] := 0.0;
                            GVL_Main.P_inv_Percent[i] := 0.0;
                            GVL_Main.Q_inv_kvar[i] := 0.0;
                        END_FOR
                        fbControle(bReset:=TRUE);
                        bFailInitDone := TRUE;
                    END_IF					
    				
    				PrevFail := FailState;   
    				FailState := E_FailState.FS_FORCE_ZERO;	
    				GVL_ALARM_MANAGER.CRIT_FAIL_ENTRY:=TRUE;	
    				FC_LogEvent(eCode:=E_EventCode.CRIT_FAIL_ENTRY,bRaised:=TRUE,
    					rParam1:=Export_mag,rParam2:=LPI_mag,uMachState := CurrentState);		
    	
    			E_FailState.FS_FORCE_ZERO:
    				
    				ResetCOM_FailSafe := (PrevFail = E_FailState.FS_INIT);			// Detecta borda de subida quando o estado para E_FailState.FS_FORCE_ZERO
    				PrevFail := FailState;   										// Atualiza o estado anterior
    
    				fbWriteCOM1(
    					Reset		 	 := ResetCOM_FailSafe,
    					tTimeout         := T#100MS,
    					nInverters       := GVL_Main.NInversoresCOM01,
    					nChannelsToWrite := GVL_Main.nChannelsToWriteCOM1,
    					maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
    					maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
    					trigInv          := GVL_Main.trigInvCOM100, 
    					pInvPtr          := GVL_Main.pInversores100
    				);
    	
    				fbWriteCOM2(
    					Reset		 	 := ResetCOM_FailSafe,
    					tTimeout         := T#100MS,
    					nInverters       := GVL_Main.NInversoresCOM02,
    					nChannelsToWrite := GVL_Main.nChannelsToWriteCOM2,
    					maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
    					maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
    					trigInv          := GVL_Main.trigInvCOM200,
    					pInvPtr          := GVL_Main.pInversores200
    				);          
                    IF fbWriteCOM1.Done AND fbWriteCOM2.Done THEN
                        IF fbWriteCOM1.bCritical OR fbWriteCOM2.bCritical THEN
                            // ❌ Escrita falhou
                            FailWriteRetryCount := FailWriteRetryCount + 1;
                            GVL_ALARM_MANAGER.CRIT_FAIL_WRITE_FAILED := TRUE;
                            FC_LogEvent(eCode:=E_EventCode.CRIT_FAIL_WRITE_ZERO_FAILED,
                                bRaised:=TRUE,
                                rParam1:=TO_REAL(FailWriteRetryCount), rParam2:=0.0,
                                uMachState := CurrentState);
    
                            IF FailWriteRetryCount >= MAX_FAIL_WRITE_RETRIES THEN
                                // ❌ Esgotou tentativas → STOP
                                FC_LogEvent(eCode:=E_EventCode.CRIT_FAIL_WRITE_EXHAUSTED,
                                    bRaised:=TRUE,
                                    rParam1:=TO_REAL(FailWriteRetryCount), rParam2:=0.0,
                                    uMachState := CurrentState);
                                NextState := E_MachineState.STOP;
                            ELSE
                                PrevFail := E_FailState.FS_INIT;
                            END_IF
                        ELSE
                            // ✅ Escrita OK
                            FailWriteRetryCount := 0;
                            GVL_ALARM_MANAGER.CRIT_FAIL_WRITE_FAILED := FALSE;
                            FailState := E_FailState.FS_VALIDATE;
                        END_IF
                    END_IF
    	
    			E_FailState.FS_VALIDATE:
        			// ────────────────────────────────────────────────────────────────
                    // CRITÉRIOS DE RECUPERAÇÃO EXPLÍCITOS
                    bMeasRecovered := (fbReadMeas.result = E_ModbusResult.DONE) AND MedidorOK;
                    bExportOK := (Export_mag <= LPI_mag);
                    bComRecovered := (NOT fbWriteCOM1.bCritical) AND (NOT fbWriteCOM2.bCritical);
                    bAllRecoveryOK := bMeasRecovered AND bExportOK AND bComRecovered;
    
                    IF bAllRecoveryOK THEN
                        IF RecoveryCycleCount < RECOVERY_CYCLES THEN
                            RecoveryCycleCount := RecoveryCycleCount + 1;
                        END_IF
    
                        tonFailSafeRecovery(IN := TRUE, PT := T#10S);
                        bRecoveryApproved := (RecoveryCycleCount >= RECOVERY_CYCLES) AND tonFailSafeRecovery.Q;
    
                        IF bRecoveryApproved THEN
                            // ✅ RECUPERAÇÃO APROVADA — limpa tudo
                            FailState := E_FailState.FS_INIT;
                            bFailInitDone := FALSE;
                            ton15s(IN := FALSE);
                            ton30s(IN := FALSE);
                            tonMedidorTimeout(IN := FALSE);
                            tonFailSafeRecovery(IN := FALSE);
                            tonFailGlobalTimeout(IN := FALSE);
                            RecoveryCycleCount := 0;
                            FailWriteRetryCount := 0;
                            ContaMeasModBusErros := 0;
                            ContaMeasModBusTimeOut := 0;
                            fbControle(bReset:=TRUE);
                            GVL_Main.LedYellowOut := FALSE;
                            GVL_ALARM_MANAGER.CRIT_FAIL_ENTRY := FALSE;
                            GVL_ALARM_MANAGER.CRIT_FAIL_WRITE_FAILED := FALSE;
                            GVL_ALARM_MANAGER.CRIT_FAIL_GLOBAL_TIMEOUT := FALSE;
                            FC_LogEvent(eCode:=E_EventCode.INFO_FAIL_RECOVERY, bRaised:=TRUE,
                                rParam1:=Export_mag, rParam2:=LPI_mag,
                                uMachState := CurrentState);
                            NextState := E_MachineState.READ;
                        END_IF
    
                    ELSE
                        // ❌ Condições NÃO OK
                        RecoveryCycleCount := 0;
                        tonFailSafeRecovery(IN := FALSE);
    
                        tonMedidorTimeout(IN := (NOT bMeasRecovered), PT := T#5S);
                        GVL_ALARM_MANAGER.CRIT_MEAS_TIMEOUT_IN_FAIL := tonMedidorTimeout.Q;
    
                        IF tonMedidorTimeout.Q THEN
                            FC_LogEvent(eCode:=E_EventCode.CRIT_MEAS_TIMEOUT_IN_FAIL,
                                bRaised:=TRUE,
                                rParam1:=Export_mag, rParam2:=LPI_mag,
                                uMachState := CurrentState);
                            tonMedidorTimeout(IN := FALSE);
                            NextState := E_MachineState.STOP;
                        END_IF
                    END_IF
    
            END_CASE
        END_IF
    
    // ────────────────────────────────────────────────────────────────
    E_MachineState.STOP:
    
        // ────────────────────────────────────────────────────────────────
        // A. ENTRADA EM STOP (primeira execução)
    	
    	NextState := E_MachineState.STOP;
    	
    	CASE StopState OF 
    	// Sinaliza entrada em STOP
        E_StopState.STOP_INIT:
    
    		ton15s(IN := FALSE);											// zera timers caso venha de FAIL
    		ton30s(IN := FALSE);
    						
            tonStopTrip(IN := FALSE);                  						// garante timer resetado
            StopResetCmd := FALSE;               							// evita saída imediata por comando antigo
    		
            // Trip imediato
            GVL_Main.K2_out := TRUE;										// aciona K2 - trip do disjuntor
            GVL_Main.K1_out := FALSE;										// desliga K1 bobina de minima tensão ou contator se existente
    		
    		// Sinalização
            GVL_Main.LedRedOut := TRUE;										// indica disjuntor desligado e houve trip
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
    				FC_LogEvent(eCode := E_EventCode.CRIT_K2_NOT_OPENED,bRaised := TRUE,rParam1 := 0.0,rParam2 := 0.0,uMachState := CurrentState);
                ELSE
                    // Sinaliza Trip aconteceu;
    				FC_LogEvent(eCode := E_EventCode.INFO_STOP_K2_OPEN_CONFIRMED,bRaised := TRUE,rParam1 := 0.0,rParam2 := 0.0,uMachState := CurrentState);
                END_IF
    			
    			StopState:= E_StopState.STOP_LATCHED;
    			
            END_IF
        
    	// ────────────────────────────────────────────────────────────────
        // C. AGUARDA RESET MANUAL PELO OPERADOR
    
        E_StopState.STOP_LATCHED:
        	
    		IF xStartResetEdge THEN																	// Borda de subida: avalia condições básicas UMA VEZ
    			StopResetCmd := FALSE;
    			StopState:= E_StopState.STOP_INIT;													// prepara próxima entrada
    			NextState := E_MachineState.START;
    		END_IF       
    	END_CASE
    	
    // ────────────────────────────────────────────────────────────────
    
    E_MachineState.ERRO:
        GVL_Main.LedRedOut := TRUE;
        GVL_Main.LedYellowOut := FALSE;
        GVL_Main.LedGreenOut := FALSE;
    
        IF xStartResetEdge THEN
            IF (NOT GVL_Main.K1_in) AND (NOT GVL_Main.K2_in) THEN
                NextState := E_MachineState.START;
            ELSE
                FC_LogEvent(eCode:=E_EventCode.WARN_STOP_RESET_DENIED,bRaised:=TRUE,rParam1:=0.0,rParam2:=0.0,uMachState := CurrentState);
            END_IF
        END_IF
    	
    END_CASE
    
    
    // ────────────────────────────────────────────────────────────────
    // Guarda de transição para TURNOFF (comando voluntário do operador)
    // Aceita TURNOFF apenas a partir de estados operacionais
    // Rejeita se já em FAIL/STOP/ERRO/START/TURNOFF
    // Aceita TURNOFF apenas a partir de estados operacionais
    IF xTurnOffEdge
       AND (CurrentState = E_MachineState.READ
            OR CurrentState = E_MachineState.CONTROL
            OR CurrentState = E_MachineState.WRITE
            OR CurrentState = E_MachineState.IDLE) THEN
        NextState := E_MachineState.TURNOFF;
    END_IF
    
    // ── Guarda existente para STOP (manter inalterada) ──
    IF (NextState = E_MachineState.STOP) AND (CurrentState <> E_MachineState.STOP) THEN
        StopState := E_StopState.STOP_INIT;
    END_IF
    
    // Atualiza flag de status
    GVL_ALARM_MANAGER.ALARM_TURNOFF_ACTIVE := (NextState = E_MachineState.TURNOFF);
    
    PrevState := CurrentState;
    GVL_Main.MachineState := NextState;
    
    
END_PROGRAM
