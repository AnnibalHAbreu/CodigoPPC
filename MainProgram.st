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
    fbChannel       : ModbusChannel;
    fbReadMeas      : FB_ModBus;
    fbValidaDados   : FB_ValidaDados;
    fbControle      : FB_Controle;
    fbWriteCOM1     : FB_WriteCom;
    fbWriteCOM2     : FB_WriteCom;

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
    // BLOCO 4 — CONTROLE DE FLUXO WRITE (Sincronismo COM1/COM2)
    // Flags de reset geradas na detecção de entrada nos estados
    // WRITE e FAIL, usadas para reinicializar FB_WriteCom a cada ciclo.
    // ══════════════════════════════════════════════════════════════════

    ResetCOM_Write    : BOOL;   // pulso ao entrar em WRITE
    ResetCOM_FailSafe : BOOL;   // pulso ao entrar em FAIL (escrita de zeros)

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 5 — LIMITES OPERACIONAIS E GRANDEZAS DE SUPERVISÃO
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
    // BLOCO 6 — TIMERS NORMATIVOS (DIS-NOR-033)
    // Temporizadores que disparam transições para STOP conforme
    // os tempos máximos definidos pela norma de exportação.
    // ATENÇÃO: estes timers são críticos de segurança — não remover.
    // ══════════════════════════════════════════════════════════════════

    ton15s      : TON;  // Exportação acima do Hard Limit por > 15 s → STOP imediato
    ton30s      : TON;  // Exportação acima do LPI por > 30 s → STOP
    tonStopTrip : TON;  // Aguarda confirmação de abertura do K2 após trip (2 s)

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 7 — ESTADO FAIL: TIMERS, CONTADORES E FLAGS DE RECUPERAÇÃO
    // Variáveis internas do estado FAIL (FS_WRITE_ZERO → FS_VALIDATE).
    // NOTA ARQUITETURAL: idealmente devem migrar para dentro de FB_FailSafe.
    // Permanecem aqui enquanto a lógica FAIL estiver inline no MainProgram.
    // ══════════════════════════════════════════════════════════════════

    // Timers
    tonStopWrite        : TON;              // timeout para escrita de zeros em FAIL
    tStopWrite          : TIME := T#2S;     // duração do timeout acima
    tonFailSafeRecovery : TON;              // janela de tempo para aprovação de recuperação (10 s)
    tonMedidorTimeout   : TON;              // detecta medidor ausente dentro de FAIL (5 s → STOP)
    tonFailGlobalTimeout: TON;              // permanência máxima em FAIL antes de forçar STOP

    // Contadores e limiares (limiares deveriam ser VAR CONSTANT ou GVL_Persis)
    FailWriteRetryCount     : UINT := 0;
    MAX_FAIL_WRITE_RETRIES  : UINT := 3;    // TODO: mover para VAR CONSTANT
    RecoveryCycleCount      : UINT := 0;
    RECOVERY_CYCLES         : UINT := 10;   // TODO: mover para VAR CONSTANT
    FAIL_MAX_DURATION       : TIME := T#120S; // TODO: mover para VAR CONSTANT

    // Flags de critério de recuperação (avaliadas em FS_VALIDATE)
    bMeasRecovered  : BOOL := FALSE;    // leitura Modbus do medidor OK
    bExportOK       : BOOL := FALSE;    // exportação dentro do LPI
    bComRecovered   : BOOL := FALSE;    // escrita nos inversores sem crítico
    bAllRecoveryOK  : BOOL := FALSE;    // AND dos três critérios acima
    bRecoveryApproved : BOOL := FALSE;  // critérios sustentados por RECOVERY_CYCLES + 10 s
    bFailInitDone   : BOOL := FALSE;    // guarda de re-execução de FS_INIT

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 8 — HEALTH MONITORING (Saúde do Sistema)
    // Flags e contadores de diagnóstico em tempo real, usados pela
    // máquina de estados e expostos à IHM/SCADA.
    // ══════════════════════════════════════════════════════════════════

    // Status de comunicação
    MedidorOK           : BOOL := FALSE;    // Modbus do medidor respondeu no ciclo atual
    ComOK               : BOOL := FALSE;    // COM1 e COM2 sem falha crítica
    Com1OK              : BOOL := TRUE;
    Com2OK              : BOOL := TRUE;
    InvOnlineCount      : UINT := 0;        // inversores que responderam no último WRITE

    // Contadores de erro de leitura (medidor)
    ContaMeasModBusErros    : UINT := 0;
    ContaMeasModBusTimeOut  : UINT := 0;

    // Contadores de anomalia de ciclo
    ScanOverrunCount        : UINT := 0;    // ciclos com tempo acima do limite

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 9 — WATCHDOG E TEMPORIZAÇÃO DO CICLO
    // Medição de tempo de execução do ciclo de scan para detectar
    // overruns. Expõe MaxCycleTime e CycleTimeOverrunCount à IHM.
    // ══════════════════════════════════════════════════════════════════

    tCycleStart         : UDINT := 0;   // timestamp início do ciclo [ms]
    tCycleEnd           : UDINT;        // timestamp fim do ciclo [ms]
    tCycle              : UDINT;        // duração do ciclo corrente [ms]
    tElapsed            : UDINT;        // tempo decorrido desde última leitura [ms]
    bFirstScanRead      : BOOL := TRUE; // flag de primeiro scan após entrada em WRITE
    MaxCycleTime        : UDINT := 0;   // pico histórico de tempo de ciclo [ms]
    CycleTimeOverrunCount : UDINT := 0; // número de overruns acumulados

    // ══════════════════════════════════════════════════════════════════
    // BLOCO 10 — DEBUG E INSTRUMENTAÇÃO (remover antes de produção)
    // Variáveis usadas exclusivamente durante desenvolvimento e
    // comissionamento. NÃO devem influenciar lógica de controle.
    // Proteger com {#ifdef DEBUG_MODE} onde aplicável.
    // ══════════════════════════════════════════════════════════════════

    stStart, stEnd, stCiclo : SYSTIME;      // timestamps de ciclo (debug)
    tStartCom, tCom, tEndCom : SYSTIME;     // timestamps de comunicação (debug)
    tMax                : SYSTIME := 0;
    stCicloMax          : SYSTIME := 0;     // pico de tempo de ciclo (debug)
    i                   : UINT;             // índice genérico de loop (debug)

    // REVISAR — uso não identificado no MainProgram; candidatos a remoção:
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
    	
      	fbReadMeas(tTimeout := T#250MS,trigInv := GVL_Main.trigMedidor100,pSlave  := GVL_Main.pMedidor100^);
    	
    	// avalia estado do Medidor a cada ciclo
    	MedidorOK:=FALSE;
    	
    	CASE fbReadMeas.result OF
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
    
    // ============================================================================
    // ============================================================================
    // CONTROL: Cálculo de Setpoints
    E_MachineState.CONTROL:
    
    	fbControle(bReset:=FALSE);  
    
        NextState := E_MachineState.WRITE;
    {#ifdef DEBUG_MODE}	
    NextState := E_MachineState.CONTROL;
    {#endif}
    
    // ============================================================================
    // ============================================================================
    // WRITE: Envia comandos aos Inversores (1 registro por vez / até 5 canais)
    // - COM1 e COM2 são orquestrados por FB_WriteCom (um por COM)
    // - Cada FB varre inversores 1..15 e canais 0..(nChannelsToWrite-1)
    // - Em falha não-crítica: pula inversor e continua
    // - Em falha crítica: sinaliza bCritical -> MainProgram vai para FAIL
    
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
            tTimeout         := T#150MS,
            nInverters       := GVL_Main.NInversoresCOM01,
            nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM1,
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
    
    		GVL_Alarm.CRIT_CH1_MODBUS_TIMEOUT:=(fbWriteCOM1.FailRes = E_ModbusResult.TIMEOUT);
    		GVL_Alarm.CRIT_CH1_MODBUS_ERRO :=(fbWriteCOM1.FailRes = E_ModbusResult.ERRO);
    		
            IF GVL_Alarm.CRIT_CH1_MODBUS_TIMEOUT THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH1_MODBUS_TIMEOUT,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM1.TmoCount),
                    rParam2    := TO_REAL(fbWriteCOM1.LastFailInv),
                    uMachState := CurrentState
                );
    		END_IF
            IF GVL_Alarm.CRIT_CH1_MODBUS_ERRO THEN 
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
            tTimeout         := T#150MS,
            nInverters       := GVL_Main.NInversoresCOM02,
            nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM2,
            maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
            maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
            trigInv          := GVL_Main.trigInvCOM200,
            pInvPtr          := GVL_Main.pInversores200
        );
    
        IF fbWriteCOM2.bCritical THEN
    
    		GVL_Alarm.CRIT_CH2_MODBUS_TIMEOUT:=(fbWriteCOM2.FailRes = E_ModbusResult.TIMEOUT);
    		GVL_Alarm.CRIT_CH2_MODBUS_ERRO :=(fbWriteCOM2.FailRes = E_ModbusResult.ERRO);
    		
            IF GVL_Alarm.CRIT_CH2_MODBUS_TIMEOUT THEN
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_CH2_MODBUS_TIMEOUT,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbWriteCOM2.TmoCount),
                    rParam2    := TO_REAL(fbWriteCOM2.LastFailInv),
                    uMachState := CurrentState
                );
    		END_IF
            IF GVL_Alarm.CRIT_CH2_MODBUS_ERRO THEN
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
        fbReadMeas(
            tTimeout := T#250MS,
            trigInv  := GVL_Main.trigMedidor100,
            pSlave   := GVL_Main.pMedidor100^
        );
    
        IF fbReadMeas.result = E_ModbusResult.DONE THEN
            fbValidaDados(Meas_Device := GVL_Pers.MeasDeviceType);
        END_IF
    
        // 1) Chama o FB_TurnOff (Opção B + Modo 1)
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
    
        // 2) Ações pedidas pelo FB (Opção B)
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
    
        // 3) MODO 1: escrever zero só quando habilitado pelo FB
        IF fbTurnOff.xWriteZeroEnable THEN
            fbWriteCOM1(
                Reset            := fbTurnOff.xReqResetCOM,
                tTimeout         := T#150MS,
                nInverters       := GVL_Main.NInversoresCOM01,
                nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM1,
                maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
                maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
                trigInv          := GVL_Main.trigInvCOM100,
                pInvPtr          := GVL_Main.pInversores100
            );
    
            fbWriteCOM2(
                Reset            := fbTurnOff.xReqResetCOM,
                tTimeout         := T#150MS,
                nInverters       := GVL_Main.NInversoresCOM02,
                nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM2,
                maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
                maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
                trigInv          := GVL_Main.trigInvCOM200,
                pInvPtr          := GVL_Main.pInversores200
            );
        ELSE
            // Reset COM — DEVE passar os VAR_IN_OUT obrigatórios
            fbWriteCOM1(
                Reset            := TRUE,
                tTimeout         := T#150MS,
                nInverters       := GVL_Main.NInversoresCOM01,
                nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM1,
                maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
                maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
                trigInv          := GVL_Main.trigInvCOM100,
                pInvPtr          := GVL_Main.pInversores100
            );
    
            fbWriteCOM2(
                Reset            := TRUE,
                tTimeout         := T#150MS,
                nInverters       := GVL_Main.NInversoresCOM02,
                nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM2,
                maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
                maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
                trigInv          := GVL_Main.trigInvCOM200,
                pInvPtr          := GVL_Main.pInversores200
            );
        END_IF
    
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
    	
        // Mantém leitura do medidor (diagnóstico)
      	fbReadMeas(tTimeout := T#250MS,trigInv:=GVL_Main.trigMedidor100,pSlave:=GVL_Main.pMedidor100^);
    	
    	// Atualiza MedidorOK
    	IF fbReadMeas.result = E_ModbusResult.DONE THEN
    		fbValidaDados(Meas_Device := GVL_Pers.MeasDeviceType);
    		MedidorOK := fbValidaDados.bDadosOK;
    	ELSE
    		MedidorOK := FALSE; 
    	END_IF;
    	
        // ── Chama FB_FailSafe ────────────────────────────────────────
        fbFailSafe(
            xEnable         := TRUE,
            xMeasDone       := (fbReadMeas.result = E_ModbusResult.DONE),
            xMeasOK         := MedidorOK,
            xCom1Done       := fbWriteCOM1.Done,
            xCom1Critical   := fbWriteCOM1.bCritical,
            xCom2Done       := fbWriteCOM2.Done,
            xCom2Critical   := fbWriteCOM2.bCritical,
            rExport_mag     := Export_mag,
            rLPI_mag        := LPI_mag,
            rHardLimit_mag  := HardLimit_mag,
            uCurrentState   := CurrentState
            );
        
        // ── Aplica setpoints zero se solicitado ──────────────────────
        IF fbFailSafe.xReqZeroSetpoints THEN
    		FOR i := 1 TO GVL_Main.NMAXINVERSORES DO
        		GVL_Main.P_inv_kW[i]      := 0.0;
                GVL_Main.P_inv_Percent[i] := 0.0;
                GVL_Main.Q_inv_kvar[i]    := 0.0;
           END_FOR
        END_IF
        
        // ── Reset do controlador PI se solicitado ────────────────────
        IF fbFailSafe.xReqResetPI THEN
             fbControle(bReset := TRUE);
        END_IF
        
         // ── Escrita Modbus zero (habilitada pelo FB) ─────────────────
        fbWriteCOM1(
             Reset            := fbFailSafe.xReqWriteCOM_Reset,
             tTimeout         := T#100MS,
             nInverters       := GVL_Main.NInversoresCOM01,
             nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM1,
             maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
             maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
             trigInv          := GVL_Main.trigInvCOM100,
             pInvPtr          := GVL_Main.pInversores100
             );
        
    	fbWriteCOM2(
    		Reset            := fbFailSafe.xReqWriteCOM_Reset,
    		tTimeout         := T#100MS,
    		nInverters       := GVL_Main.NInversoresCOM02,
    		nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM2,
    		maxErrors        := GVL_Main.MAX_CH2_MODBUS_ERROS,
    		maxTimeouts      := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
    		trigInv          := GVL_Main.trigInvCOM200,
    		pInvPtr          := GVL_Main.pInversores200
    	);
    
    	// ── Transições de estado ─────────────────────────────────────
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
    
    // ── Guarda existente para STOP (manter inalterada) ──
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
    
    // Atualiza flag de status
    GVL_Alarm.ALARM_TURNOFF_ACTIVE := (NextState = E_MachineState.TURNOFF);
    
    PrevState := CurrentState;
    GVL_Main.MachineState := NextState;
    
    
END_PROGRAM
