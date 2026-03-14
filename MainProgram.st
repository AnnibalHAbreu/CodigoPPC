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
    FAIL    -> 		   (coloca o sistema em condição segura, tenta restabelecer sozinho, caso contrário vai para STOP)
    STOP    ->         (parada controlada, permanece travado - resetado pelo operador por botão ou ihm)
	TURNOFF ->		   (desligamento comandado pelo operador)
	ERRO    ->         (situação de erro devido a configuração incorreta - f
*)

VAR
    // ══════════════════════════════════════════════════════════════════
    // BLOCO 1 — INSTÂNCIAS DE FUNCTION BLOCKS
    // Todos os FBs instanciados neste programa, agrupados por função.
    // Ordem reflete a sequência lógica do ciclo de controle.
    // ══════════════════════════════════════════════════════════════════

    // Inicialização
    fbStart         : FB_Startup;

    // Ciclo READ → CONTROL → WRITE
    fbValidaDados   : FB_ValidaDados;
    fbControle      : FB_Controle;

    // Estados especiais
    fbTurnOff       : FB_TurnOff;
    fbFailSafe      : FB_FailSafe;          // encapsula lógica completa do estado FAIL

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 2 — MÁQUINA DE ESTADOS
    // Variáveis que controlam o fluxo de estados do MainProgram.
    // NextState é a única variável gravável do ciclo corrente;
    // GVL_Main.MachineState é atualizado ao final do ciclo.
    // ══════════════════════════════════════════════════════════════════

    CurrentState    : E_MachineState := E_MachineState.START;
    NextState       : E_MachineState := E_MachineState.START;
    PrevState       : E_MachineState := E_MachineState.START;   // detecta transições de estado

    StopState       : E_StopState    := E_StopState.STOP_INIT;

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 3 — INTERFACE COM A IHM (Botões e Comandos do Operador)
    // Detecção de borda dos botões da IHM. As flags xEdge são
    // consumidas uma única vez por ciclo pela máquina de estados.
    // ══════════════════════════════════════════════════════════════════

    rTrigStartReset : R_TRIG;
    rTrigTurnOff    : R_TRIG;
    xStartResetEdge : BOOL;     // borda de subida: botão Start/Reset
    xTurnOffEdge    : BOOL;     // borda de subida: botão TurnOff
    StopResetCmd    : BOOL := FALSE;    // flag de confirmação de reset em STOP

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 4 — LIMITES OPERACIONAIS E GRANDEZAS DE SUPERVISÃO
    // Valores calculados a cada ciclo READ/CONTROL usados nas
    // verificações normativas (DIS-NOR-033) e no estado FAIL.
    // Unidade: kW e kvar (sistema interno do controlador).
    // ══════════════════════════════════════════════════════════════════

    LPI_mag             : REAL;             // Limite de Potência de Importação [kW] — trifásico
    LPI_per_phase_kW    : REAL := 0.0;      // LPI por fase [kW] — usado na alocação
    HardLimit_mag       : REAL := 0.0;      // Hard limit absoluto [kW] (110% do LPI)
    Export_mag          : REAL;             // Exportação medida no ponto de conexão [kW]

    // Validação cruzada medidor × inversores
    Pt_Lastatus         : REAL := 0.0;      // Potência do LA (status) [kW]
    P_inv_sum           : REAL := 0.0;      // Soma das potências dos inversores [kW]

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 5 — TIMERS NORMATIVOS (DIS-NOR-033)
    // Temporizadores que disparam transições para STOP conforme
    // os tempos máximos definidos pela norma de exportação.
    // ATENÇÃO: estes timers são críticos de segurança — não remover.
    // ══════════════════════════════════════════════════════════════════

    ton15s      : TON;  // Exportação acima do Hard Limit por > 15 s → STOP imediato
    ton30s      : TON;  // Exportação acima do LPI por > 30 s → STOP
    tonStopTrip : TON;  // Aguarda confirmação de abertura do K2 após trip (2 s)

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 6 — ESTADO FAIL: TIMERS, CONTADORES E FLAGS DE RECUPERAÇÃO
    // Variáveis internas do estado FAIL (FS_WRITE_ZERO → FS_VALIDATE).
    // NOTA ARQUITETURAL: idealmente devem migrar para dentro de FB_FailSafe.
    // Permanecem aqui enquanto a lógica FAIL estiver inline no MainProgram.
    // ══════════════════════════════════════════════════════════════════

    // Timers
    tonStopWrite        	: TON;              // timeout para escrita de zeros em FAIL
    tStopWrite          	: TIME := T#2S;     // duração do timeout acima
    tonFailSafeRecovery 	: TON;              // janela de tempo para aprovação de recuperação (10 s)
    tonMedidorTimeout   	: TON;              // detecta medidor ausente dentro de FAIL (5 s → STOP)
    tonFailGlobalTimeout	: TON;              // permanência máxima em FAIL antes de forçar STOP

    // Contadores e limiares (limiares deveriam ser VAR CONSTANT ou GVL_Persis)
    FailWriteRetryCount     : UINT := 0;
    MAX_FAIL_WRITE_RETRIES  : UINT := 3;    	// TODO: mover para VAR CONSTANT
    RecoveryCycleCount      : UINT := 0;
    RECOVERY_CYCLES         : UINT := 10;   	// TODO: mover para VAR CONSTANT
    FAIL_MAX_DURATION       : TIME := T#120S; 	// TODO: mover para VAR CONSTANT

    // Flags de critério de recuperação (avaliadas em FS_VALIDATE)
    bMeasRecovered  		: BOOL := FALSE;    // leitura Modbus do medidor OK
    bExportOK       		: BOOL := FALSE;    // exportação dentro do LPI
    bComRecovered   		: BOOL := FALSE;    // escrita nos inversores sem crítico
    bAllRecoveryOK  		: BOOL := FALSE;    // AND dos três critérios acima
    bRecoveryApproved 		: BOOL := FALSE;  	// critérios sustentados por RECOVERY_CYCLES + 10 s
    bFailInitDone   		: BOOL := FALSE;    // guarda de re-execução de FS_INIT

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 7 — HEALTH MONITORING (Saúde do Sistema)
    // Flags e contadores de diagnóstico em tempo real, usados pela
    // máquina de estados e expostos à IHM/SCADA.
    // ══════════════════════════════════════════════════════════════════

    // Status de comunicação
    MedidorOK           	: BOOL := FALSE;    // Modbus do medidor respondeu no ciclo atual
    ComOK               	: BOOL := FALSE;    // COM1 e COM2 sem falha crítica
    Com1OK              	: BOOL := TRUE;
    Com2OK              	: BOOL := TRUE;
    InvOnlineCount      	: UINT := 0;        // inversores que responderam no último WRITE

    // Contadores de erro de leitura (medidor)
    ContaMeasModBusErros    : UINT := 0;
    ContaMeasModBusTimeOut  : UINT := 0;

    // Contadores de anomalia de ciclo
    ScanOverrunCount        : UINT := 0;    	// ciclos com tempo acima do limite

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 8 — WATCHDOG E TEMPORIZAÇÃO DO CICLO
    // Medição de tempo de execução do ciclo de scan para detectar
    // overruns. Expõe MaxCycleTime e CycleTimeOverrunCount à IHM.
    // ══════════════════════════════════════════════════════════════════

    tCycleStart         	: UDINT := 0;   	// timestamp início do ciclo [ms]
    tCycleEnd           	: UDINT;        	// timestamp fim do ciclo [ms]
    tCycle              	: UDINT;        	// duração do ciclo corrente [ms]
    tElapsed            	: UDINT;        	// tempo decorrido desde última leitura [ms]
    bFirstScanRead      	: BOOL := TRUE; 	// flag de primeiro scan após entrada em WRITE
    MaxCycleTime        	: UDINT := 0;   	// pico histórico de tempo de ciclo [ms]
    CycleTimeOverrunCount 	: UDINT := 0; 		// número de overruns acumulados
	
	// ══════════════════════════════════════════════════════════════════
    // BLOCO 9 — índice de loop e debug
    // ══════════════════════════════════════════════════════════════════

    i                   : UINT;             // índice genérico de loop

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 10 — DEBUG E INSTRUMENTAÇÃO
    // ══════════════════════════════════════════════════════════════════

    stStart, stEnd, stCiclo : SYSTIME;
    tStartCom, tCom, tEndCom : SYSTIME;
    tMax                : SYSTIME := 0;
    stCicloMax          : SYSTIME := 0;
    valor               : UN_Convert_Word_To_Real;
    auxvalor            : REAL := 0;
    Gatilho             : BOOL := TRUE;
    rTrigOn             : R_TRIG;
    fTrigOff            : F_TRIG;
    Primeiravez         : BOOL := TRUE;

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
    
    GVL_Main.ControlCycle := UDINT_TO_REAL(GVL_Main.CYCLE_TIME_MS) / 1000.0;
    GVL_Main.CYCLE_TIME_TOLERANCE := TO_UDINT(TO_REAL(GVL_Main.CYCLE_TIME_MS) * 1.2);
    
    CASE CurrentState OF
    	
    // ============================================================================
    // ============================================================================
    // START: Inicialização (fbStart + K1/K2)
    E_MachineState.START:
        fbStart();  // Chamada do bloco de inicialização
    	
    	CASE fbStart.stState OF
    		E_StartupStatus.stInit,
    		E_StartupStatus.stCheck_COM,
    		E_StartupStatus.stCheck_Medidor,
    		E_StartupStatus.stCheck_Inversores,
            E_StartupStatus.stWait_K1,
            E_StartupStatus.stWait_K2:
            	// Permanece em START
            E_StartupStatus.stDone:
                (* Inicialização concluída – segue para leitura *)		
                NextState := E_MachineState.READ;
    		E_StartupStatus.stError:
    			NextState := E_MachineState.ERRO;					// ocorreu erro na inicialização do sistema
    		
    {#ifdef DEBUG_MODE}			
    NextState := E_MachineState.CONTROL;
    auxvalor:=0;
    {#endif}
    	END_CASE;
    
    // ============================================================================
    // ============================================================================
    // READ: Leitura do Medidor
    E_MachineState.READ:
    
        // Marca início do ciclo apenas uma vez ao entrar em READ
        IF bFirstScanRead THEN
            tCycleStart := SysTimeCore.SysTimeGetMs();
            bFirstScanRead := FALSE;
        END_IF;	
    	
    	// Leitura é feita pela Task_ModbusComm — verificar resultado
    
    	MedidorOK:=FALSE;
    	
        // Copiar dados raw do medidor para o FB_ValidaDados
        // (o FB_ValidaDados usa UN_chint internamente — copiar os dados raw do GVL_Comm para o word array da union)
    	
    	IF GVL_Comm.bMeterReadDone THEN
    		
    		CASE GVL_Comm.eMeterResult OF
    			
    			E_ModbusResult.DONE:
    				ContaMeasModBusErros:= 0;
    				ContaMeasModBusTimeOut:= 0;
    				
    				fbValidaDados(Meas_Device:=GVL_Pers.MeasDeviceType);
    				MedidorOK:=fbValidaDados.bDadosOK;
    				
    				GVL_Alarm.ALARM_MEAS_USING_LAST_VALUEU:=fbValidaDados.bPoucosErros;
    				GVL_Alarm.CRIT_MEAS_PERSISTENT_FAIL:=(NOT MedidorOK AND NOT fbValidaDados.bPoucosErros);
    				
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
    				GVL_Alarm.CRIT_MEAS_MODBUS_ERRO:=(ContaMeasModBusErros > GVL_Main.MAX_Meas_MODBUS_ERROS);
    				
    				IF GVL_Alarm.CRIT_MEAS_MODBUS_ERRO THEN					// permite seguir sem parar se acontecerem erros abaixo do maximo
    					NextState := E_MachineState.FAIL;
    					FC_LogEvent(eCode:= E_EventCode.CRIT_MEAS_MODBUS_ERRO,bRaised:= TRUE,rParam1:=TO_REAL(ContaMeasModBusErros),rParam2:= 0.0,uMachState:=CurrentState);
    				ELSE
    					NextState := E_MachineState.IDLE;
    					FC_LogEvent(eCode:= E_EventCode.ALARM_MEAS_MODBUS_ERROR,bRaised:= TRUE,rParam1:=TO_REAL(ContaMeasModBusErros),rParam2:= 0.0,uMachState:=CurrentState);
    				END_IF
    				
    			E_ModbusResult.TIMEOUT: 
    				ContaMeasModBusTimeOut:= ContaMeasModBusTimeOut + 1;
    				GVL_Alarm.CRIT_MEAS_MODBUS_TIMEOUT:=(ContaMeasModBusTimeOut > GVL_Main.MAX_Meas_MODBUS_TIMEOUTS);
    				
    				IF GVL_Alarm.CRIT_MEAS_MODBUS_TIMEOUT THEN				// permite seguir sem parar se acontecerem TimeOut abaixo do maximo
    					NextState := E_MachineState.FAIL;
    					FC_LogEvent(eCode:=E_EventCode.CRIT_MEAS_MODBUS_TIMEOUT,bRaised:=TRUE,rParam1:=TO_REAL(ContaMeasModBusTimeOut),rParam2:=0.0,uMachState := CurrentState);
    				ELSE
    					NextState := E_MachineState.IDLE;
    					FC_LogEvent(eCode:=E_EventCode.ALARM_MEAS_MODBUS_TIMEOUT,bRaised:=TRUE,rParam1:=TO_REAL(ContaMeasModBusTimeOut),rParam2:=0.0,uMachState := CurrentState);
    				END_IF
    		END_CASE
    		GVL_Comm.bMeterReadDone := FALSE;								// reset do flag de leitura sempre que há uma leitura
    	END_IF
    	// Se bMeterReadDone=FALSE, permanece em READ (aguarda próxima leitura)
    	// GVL_Comm.bMeterReadDone é resetado para que ocorra uma nova leitura
    
    // ============================================================================
    // ============================================================================
    // CONTROL: Cálculo de Setpoints
    E_MachineState.CONTROL:
    
    	fbControle(bReset:=FALSE);  
    	
    	// Preenche valores físicos em GVL_Comm (sem conversão — FB_ModbusRTU_Write converte via profile)
        // P_inv_Percent: 0.0..100.0 (% da nominal) — range validado pelo LIMIT no FB
        // PF_inv_Percent: 1.0..100.0 (valor Modbus Goodwe já calculado em FB_QAlloc)
        FOR i := 1 TO GVL_Main.NInversoresCOM01 DO
            GVL_Comm.arWriteValuesCOM1[i, 0] := GVL_Main.P_inv_Percent[i];     // 0..100%
            GVL_Comm.arWriteValuesCOM1[i, 1] := GVL_Main.PF_inv_Percent[i];    // 1..100 (Goodwe)
        END_FOR
    
        FOR i := 1 TO GVL_Main.NInversoresCOM02 DO
            GVL_Comm.arWriteValuesCOM2[i, 0] := GVL_Main.P_inv_Percent[i + 15];
            GVL_Comm.arWriteValuesCOM2[i, 1] := GVL_Main.PF_inv_Percent[i + 15];
        END_FOR
    
        // Sinaliza pending — Task_ModbusComm detecta borda e inicia varredura
        GVL_Comm.bWritePendingCOM1 := TRUE;
        GVL_Comm.bWritePendingCOM2 := TRUE;
    
        // Garante que Done esteja limpo antes de entrar em WRITE
        GVL_Comm.bWriteDoneCOM1 := FALSE;
        GVL_Comm.bWriteDoneCOM2 := FALSE;
    
        NextState := E_MachineState.WRITE;
    	
    // ============================================================================
    // ============================================================================
    // WRITE: Envia comandos aos Inversores (1 registro por vez / até 5 canais)
    // - COM1 e COM2 são orquestrados por FB_WriteCom (um por COM)
    // - Cada FB varre inversores 1..15 e canais 0..(nChannelsToWrite-1)
    // - Em falha não-crítica: pula inversor e continua
    // - Em falha crítica: sinaliza bCritical -> MainProgram vai para FAIL
    
    E_MachineState.WRITE:
    
    	// MainProgram não acessa ClientSerial — apenas monitora flags de GVL_Comm.
    	// A varredura é executada inteiramente em PRG_ModbusComm (Task_ModbusComm).
    
    	// ── Falha crítica COM1 ───────────────────────────────────────
    	IF GVL_Comm.bWriteDoneCOM1 AND GVL_Comm.bWriteCriticalCOM1 THEN
    		GVL_Alarm.CRIT_CH1_MODBUS_TIMEOUT :=
    			(GVL_Comm.eWriteLastFailResCOM1 = E_ModbusResult.TIMEOUT);
    		GVL_Alarm.CRIT_CH1_MODBUS_ERRO :=
    			(GVL_Comm.eWriteLastFailResCOM1 = E_ModbusResult.ERRO);
    
    		IF GVL_Alarm.CRIT_CH1_MODBUS_TIMEOUT THEN
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_CH1_MODBUS_TIMEOUT,
    				bRaised    := TRUE,
    				rParam1    := TO_REAL(GVL_Comm.uiWriteTmoCOM1),
    				rParam2    := TO_REAL(GVL_Comm.uiWriteLastFailInvCOM1),
    				uMachState := CurrentState
    			);
    		END_IF
    		IF GVL_Alarm.CRIT_CH1_MODBUS_ERRO THEN
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_CH1_MODBUS_ERRO,
    				bRaised    := TRUE,
    				rParam1    := TO_REAL(GVL_Comm.uiWriteErrCOM1),
    				rParam2    := TO_REAL(GVL_Comm.uiWriteLastFailInvCOM1),
    				uMachState := CurrentState
    			);
    		END_IF
    		NextState := E_MachineState.FAIL;
    	END_IF
    
    	// ── Falha crítica COM2 ───────────────────────────────────────
    	IF GVL_Comm.bWriteDoneCOM2 AND GVL_Comm.bWriteCriticalCOM2 THEN
    		GVL_Alarm.CRIT_CH2_MODBUS_TIMEOUT :=
    			(GVL_Comm.eWriteLastFailResCOM2 = E_ModbusResult.TIMEOUT);
    		GVL_Alarm.CRIT_CH2_MODBUS_ERRO :=
    			(GVL_Comm.eWriteLastFailResCOM2 = E_ModbusResult.ERRO);
    
    		IF GVL_Alarm.CRIT_CH2_MODBUS_TIMEOUT THEN
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_CH2_MODBUS_TIMEOUT,
    				bRaised    := TRUE,
    				rParam1    := TO_REAL(GVL_Comm.uiWriteTmoCOM2),
    				rParam2    := TO_REAL(GVL_Comm.uiWriteLastFailInvCOM2),
    				uMachState := CurrentState
    			);
    		END_IF
    		IF GVL_Alarm.CRIT_CH2_MODBUS_ERRO THEN
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_CH2_MODBUS_ERRO,
    				bRaised    := TRUE,
    				rParam1    := TO_REAL(GVL_Comm.uiWriteErrCOM2),
    				rParam2    := TO_REAL(GVL_Comm.uiWriteLastFailInvCOM2),
    				uMachState := CurrentState
    			);
    		END_IF
    		NextState := E_MachineState.FAIL;
    	END_IF
    
    	// ── Varredura completa (ambas as COMs) ───────────────────────
    	IF GVL_Comm.bWriteDoneCOM1 AND GVL_Comm.bWriteDoneCOM2 THEN
    		GVL_Comm.bWriteDoneCOM1 := FALSE;   // limpa para próximo ciclo
    		GVL_Comm.bWriteDoneCOM2 := FALSE;
    		NextState := E_MachineState.IDLE;
    	END_IF
    
    // ============================================================================
    // ============================================================================
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
    
    	GVL_Alarm.ALARM_SCAN_OVERRUN:=(tElapsed > GVL_Main.CYCLE_TIME_TOLERANCE);
    	IF GVL_Alarm.ALARM_SCAN_OVERRUN THEN
    		
    		ScanOverrunCount := ScanOverrunCount + 1;
    		
    		FC_LogEvent(eCode:=E_EventCode.ALARM_SCAN_OVERRUN,bRaised:=TRUE,
    							rParam1:=0.0,rParam2:=0.0,uMachState := CurrentState);
    							
    		GVL_Alarm.CRIT_SCAN_OVERRUN:=(ScanOverrunCount >= 3);
    		IF GVL_Alarm.CRIT_SCAN_OVERRUN THEN
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
    
    // ============================================================================
    // ============================================================================
    E_MachineState.TURNOFF:
    
        // 0) Mantém medição viva durante TURNOFF
    	// Leitura do medidor é contínua na Task_ModbusComm.
    	// Aqui apenas verificamos o resultado mais recente.
    	IF GVL_Comm.bMeterReadDone THEN
    		IF GVL_Comm.eMeterResult = E_ModbusResult.DONE THEN
    			fbValidaDados(Meas_Device := GVL_Pers.MeasDeviceType);
    		END_IF
    	END_IF
    
    	// 1) Chama o FB_TurnOff
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
    		xCom1Done        := GVL_Comm.bWriteDoneCOM1,      // via GVL — sem tocar no ClientSerial
    		xCom1Critical    := GVL_Comm.bWriteCriticalCOM1,
    		xCom2Done        := GVL_Comm.bWriteDoneCOM2,
    		xCom2Critical    := GVL_Comm.bWriteCriticalCOM2
    	);
    
    	// 2) Ações pedidas pelo FB
    	// (idêntico ao original — sem alteração)
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
    
    	// 3) Escrita de zeros via GVL quando habilitada pelo FB
    	// xWriteZeroEnable e xReqResetCOM substituídos por pending único.
    	// Nota: no design anterior havia distinção entre xWriteZeroEnable
    	// (escreve zeros) e o branch ELSE (reset do FB sem escrever).
    	// No novo design o reset é implícito: quando bWritePendingCOMx sobe,
    	// PRG_ModbusComm inicia nova varredura do zero. Não há estado "reset
    	// sem escrita" porque o FB vive na outra task e é controlado por trigger.
    	IF fbTurnOff.xWriteZeroEnable THEN
    		FOR i := 1 TO GVL_Main.NInversoresCOM01 DO
    			GVL_Comm.arWriteValuesCOM1[i, 0] := 0.0;    // P = 0%
    			GVL_Comm.arWriteValuesCOM1[i, 1] := 100.0;  // PF = 1.0 indutivo (reg=100)
    		END_FOR
    		FOR i := 1 TO GVL_Main.NInversoresCOM02 DO
    			GVL_Comm.arWriteValuesCOM2[i, 0] := 0.0;
    			GVL_Comm.arWriteValuesCOM2[i, 1] := 100.0;
    		END_FOR
    		GVL_Comm.bWriteDoneCOM1    := FALSE;
    		GVL_Comm.bWriteDoneCOM2    := FALSE;
    		GVL_Comm.bWritePendingCOM1 := TRUE;
    		GVL_Comm.bWritePendingCOM2 := TRUE;
    	END_IF
    	// ELSE (xWriteZeroEnable = FALSE): não faz nada — o FB_TurnOff
    	// controla o ritmo via uMaxWriteRetries e xCom1Done/xCom2Done.
    
        // 4) Log (1 por transição)
        IF fbTurnOff.xLogEvent THEN
            FC_LogEvent(
                eCode      := fbTurnOff.eLogCode,
                bRaised    := TRUE,
                rParam1    := fbTurnOff.rLogParam1,
                rParam2    := fbTurnOff.rLogParam2,
                uMachState := CurrentState
            );
        END_IF
    
        // 5) Aplica saídas físicas
        GVL_Main.K1_out       := fbTurnOff.xK1_out;
        GVL_Main.K2_out       := fbTurnOff.xK2_out;
        GVL_Main.LedRedOut    := fbTurnOff.xLedRed;
        GVL_Main.LedYellowOut := fbTurnOff.xLedYellow;
        GVL_Main.LedGreenOut  := fbTurnOff.xLedGreen;
    
        // 6) Transições solicitadas pelo FB
        IF fbTurnOff.xRequestStop THEN
            NextState := E_MachineState.STOP;
        ELSIF fbTurnOff.xRequestStart THEN
            NextState := E_MachineState.START;
        ELSE
            NextState := E_MachineState.TURNOFF;
        END_IF
    
    // ============================================================================
    // ============================================================================
    E_MachineState.FAIL:
    // ESTADO FAIL — Redução forçada (norma DIS-NOR-033)
    // Fluxo: FS_INIT → FS_FORCE_ZERO → FS_VALIDATE → (recupera ou STOP)
    // Toda a lógica reside em FB_FailSafe.
    // MainProgram delega e aplica as saídas solicitadas pelo FB.
    // ton15s: P > LPI + 10% Pnom por >15s → STOP
    // ton30s: P > LPI por >30s → STOP
    
    	// ────────────────────────────────────────────────────────────────
    	// A. CÁLCULOS INDEPENDENTES DE SUB-ESTADO (executam TODO ciclo)
    
        // ── Cálculos de limite (necessários para alimentar o FB) ─────
    	LPI_mag := ABS(GVL_Main.MaxExportLimit);
    	Export_mag := MAX(0, -GVL_Main.Pt);
        HardLimit_mag := LPI_mag + (GVL_Main.InstalledPower * 0.1);
    	
    	// Leitura do medidor é contínua na Task_ModbusComm
    	// Aqui apenas verificamos o resultado mais recente
    	IF GVL_Comm.bMeterReadDone AND (GVL_Comm.eMeterResult = E_ModbusResult.DONE) THEN
    		fbValidaDados(Meas_Device := GVL_Pers.MeasDeviceType);
    		MedidorOK := fbValidaDados.bDadosOK;
    	ELSE
    		MedidorOK := FALSE;
    	END_IF
    	
            // ── Chama FB_FailSafe ────────────────────────────────────────
            fbFailSafe(
        		xEnable         := TRUE,
        		xMeasDone       := GVL_Comm.bMeterReadDone,
        		xMeasOK         := MedidorOK,
                xCom1Done       := GVL_Comm.bWriteDoneCOM1,       // via GVL — sem tocar no ClientSerial
                xCom1Critical   := GVL_Comm.bWriteCriticalCOM1,
                xCom2Done       := GVL_Comm.bWriteDoneCOM2,
                xCom2Critical   := GVL_Comm.bWriteCriticalCOM2,
                rExport_mag     := Export_mag,
                rLPI_mag        := LPI_mag,
                rHardLimit_mag  := HardLimit_mag,
                uCurrentState   := CurrentState
                );
            
            // ── Aplica setpoints zero se solicitado ──────────────────────
            // (idêntico ao original — sem alteração)
            IF fbFailSafe.xReqZeroSetpoints THEN
        		FOR i := 1 TO GVL_Main.NMAXINVERSORES DO
            		GVL_Main.P_inv_kW[i]      := 0.0;
                    GVL_Main.P_inv_Percent[i] := 0.0;
                    GVL_Main.Q_inv_kvar[i]    := 0.0;
               END_FOR
            END_IF
            
            // ── Reset do controlador PI se solicitado ────────────────────
            // (idêntico ao original — sem alteração)
            IF fbFailSafe.xReqResetPI THEN
                 fbControle(bReset := TRUE);
            END_IF
    
            // ── Solicita escrita de zeros via GVL (Task_ModbusComm executa) ──
            // Substituí as chamadas diretas a fbWriteCOM1/2 por escrita nos arrays
            // e sinalização de pending. A Task_ModbusComm detecta a borda e executa.
            IF fbFailSafe.xReqWriteCOM_Reset THEN
                // Zerar potência ativa; manter PF = 1.0 (valor Modbus Goodwe = 100)
                FOR i := 1 TO GVL_Main.NInversoresCOM01 DO
                    GVL_Comm.arWriteValuesCOM1[i, 0] := 0.0;    // P = 0%
                    GVL_Comm.arWriteValuesCOM1[i, 1] := 100.0;  // PF = 1.0 indutivo (reg=100)
                END_FOR
                FOR i := 1 TO GVL_Main.NInversoresCOM02 DO
                    GVL_Comm.arWriteValuesCOM2[i, 0] := 0.0;
                    GVL_Comm.arWriteValuesCOM2[i, 1] := 100.0;
                END_FOR
                // Limpa Done anterior para detectar conclusão da nova varredura
                GVL_Comm.bWriteDoneCOM1    := FALSE;
                GVL_Comm.bWriteDoneCOM2    := FALSE;
                // Sinaliza pending — PRG_ModbusComm detecta borda e inicia varredura
                GVL_Comm.bWritePendingCOM1 := TRUE;
                GVL_Comm.bWritePendingCOM2 := TRUE;
            END_IF
    
        	// ── Transições de estado ─────────────────────────────────────
        	// (idêntico ao original — sem alteração)
        	IF fbFailSafe.xRequestStop THEN
        		NextState := E_MachineState.STOP;
        	ELSIF fbFailSafe.xRequestRead THEN
        		// Recuperação aprovada: desabilita FB antes de sair
        		fbFailSafe(xEnable := FALSE,
        			xMeasDone := FALSE, xMeasOK := FALSE,
        			xCom1Done := FALSE, xCom1Critical := FALSE,
        			xCom2Done := FALSE, xCom2Critical := FALSE,
        			rExport_mag := 0.0, rLPI_mag := 0.0, rHardLimit_mag := 0.0,
        			uCurrentState := CurrentState);
        		NextState := E_MachineState.READ;
        	END_IF 
    
    // ============================================================================
    // ============================================================================
    E_MachineState.STOP:
    
        // ────────────────────────────────────────────────────────────────
        // A. ENTRADA EM STOP (primeira execução)
    	
    	NextState := E_MachineState.STOP;
    	
    	CASE StopState OF 
    	// Sinaliza entrada em STOP
        E_StopState.STOP_INIT:
    				
            tonStopTrip(IN := FALSE);                  						// garante timer resetado
            StopResetCmd := FALSE;               							// evita saída imediata por comando antigo
    		
            // Trip imediato
            GVL_Main.K2_out := TRUE;										// aciona K2 - trip do disjuntor
            GVL_Main.K1_out := FALSE;										// desliga K1 bobina de minima tensão ou contator se existente
    		
    		// Sinalização
            GVL_Main.LedRedOut := TRUE;										// indica disjuntor desligado e houve trip
            GVL_Main.LedYellowOut := FALSE;
            GVL_Main.LedGreenOut := FALSE;
    		
    		GVL_Alarm.CRIT_K2_NOT_OPENED :=FALSE;
    					
    		StopState:= E_StopState.STOP_TRIP;
    	   
    	// ────────────────────────────────────────────────────────────────
        // B. Aguarda 2 segundos para verificar acionamento de K2 (executa apenas 1 vez)
    
        E_StopState.STOP_TRIP: 
    	
            tonStopTrip(IN := TRUE, PT := T#2S);
            
            IF tonStopTrip.Q THEN
                tonStopTrip(IN := FALSE);
                
    			GVL_Alarm.CRIT_K2_NOT_OPENED := GVL_Main.K2_in;		// se K2=TRUE => K2 não tripou
    			
                IF (GVL_Alarm.CRIT_K2_NOT_OPENED) THEN
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
    	
    
    // ============================================================================
    // ============================================================================
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
    
    
    // ============================================================================
    // ============================================================================
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
    
    
    IF (NextState = E_MachineState.TURNOFF) AND (CurrentState <> E_MachineState.TURNOFF) THEN
        GVL_Comm.bWriteDoneCOM1 := FALSE;
        GVL_Comm.bWriteDoneCOM2 := FALSE;
        GVL_Comm.bWriteCriticalCOM1 := FALSE;
        GVL_Comm.bWriteCriticalCOM2 := FALSE;
    END_IF
    
    // ── Guarda para STOP  ──
    IF (NextState = E_MachineState.STOP) AND (CurrentState <> E_MachineState.STOP) THEN
    	StopState := E_StopState.STOP_INIT;
    	// Garante reset do FB_FailSafe ao sair do estado FAIL via STOP
    	IF CurrentState = E_MachineState.FAIL THEN
    		fbFailSafe(xEnable := FALSE,
    			xMeasDone := FALSE, xMeasOK := FALSE,
    			xCom1Done := FALSE, xCom1Critical := FALSE,
    			xCom2Done := FALSE, xCom2Critical := FALSE,
    			rExport_mag := 0.0, rLPI_mag := 0.0, rHardLimit_mag := 0.0,
    			uCurrentState := CurrentState);
    	END_IF
    END_IF
    
    // limpa Done ao entrar em FAIL para evitar leitura de resultado antigo
    IF (NextState = E_MachineState.FAIL) AND (CurrentState <> E_MachineState.FAIL) THEN
        GVL_Comm.bWriteDoneCOM1 := FALSE;
        GVL_Comm.bWriteDoneCOM2 := FALSE;
        GVL_Comm.bWriteCriticalCOM1 := FALSE;
        GVL_Comm.bWriteCriticalCOM2 := FALSE;
    END_IF
    
    // Atualiza flag de status
    GVL_Alarm.ALARM_TURNOFF_ACTIVE := (NextState = E_MachineState.TURNOFF);
    
    PrevState := CurrentState;
    GVL_Main.MachineState := NextState;
END_PROGRAM
