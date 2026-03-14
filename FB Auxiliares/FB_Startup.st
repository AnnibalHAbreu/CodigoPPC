(* ════════════════════════════════════════════════════════════════════
   FB_Startup — Sequência de inicialização do PPC-GD
   ════════════════════════════════════════════════════════════════════
   Sequência de estados:
     stInit             → cálculos iniciais: RTC, ciclo, ponteiros,
                          contagem de inversores, potência instalada
     stCheck_COM        → aguarda driver Modbus RTU atingir RUNNING
     stCheck_Medidor    → confirma ACK Modbus do medidor
     stCheck_Inversores → varredura de presença nos inversores
     stWait_K1          → fecha K1_out; aguarda K1_in com debounce
     stWait_K2          → aguarda K2_in com debounce
     stDone             → startup concluído → MainProgram vai para IDLE
     stError            → falha de startup  → MainProgram vai para STOP

   Notas:
     - K1_in e K2_in devem ser contatos auxiliares dos disjuntores.
       Se não forem usados contatos auxiliares, conectar a 24V.
     - Este FB controla K1_out e os LEDs. K2_out é controlado pelo
       MainProgram (estado STOP).
     - TONs devem ser chamados todo ciclo para acumular tempo
       corretamente — nunca instanciar dentro de IF.
   ════════════════════════════════════════════════════════════════════ *)
{attribute 'no_assign'}  
FUNCTION_BLOCK FB_Startup

VAR_OUTPUT
    stState             : E_StartupStatus := E_StartupStatus.stInit;
END_VAR

VAR
    // ── Entradas digitais (lidas no início de cada ciclo) ─────────
    auxK1_in            : BOOL;                     // espelho de GVL_Main.K1_in
    auxK2_in            : BOOL;                     // espelho de GVL_Main.K2_in

    // ── Saídas físicas (calculadas no corpo, aplicadas no final) ──
    cmdK01              : BOOL := FALSE;            // K1_out
    auxRed              : BOOL := FALSE;            // LedRedOut
    auxYellow           : BOOL := FALSE;            // LedYellowOut
    auxGreen            : BOOL := FALSE;            // LedGreenOut

    // ── Variável de loop (stInit) ─────────────────────────────────
    indice              : UINT;

    // ── stCheck_COM: aguarda driver Modbus RTU ────────────────────

    xMaster01IsReady    : BOOL;                     // TRUE quando Master_01 = RUNNING
    xMaster02IsReady    : BOOL;                     // TRUE quando Master_02 = RUNNING
	TonComTimeout       : TON;                      // timeout de espera pelo driver
    TimeComTimeout      : TIME := T#10S;            // 10s: conservador para boot do driver RTU
    bComLogSent         : BOOL := FALSE;            // evita log repetido de INFO_SERIAL_COM_OK

    // ── stCheck_Medidor: confirma ACK Modbus do medidor ───────────
    TonMedTimeout       : TON;                      // timeout global da verificação
    TimeMedTimeout      : TIME := T#10S;            // 10s: margem para medidor lento

    // ── stCheck_Inversores: varredura de presença ─────────────────
    fbCheckInv          : FB_CheckInversores;       // varredura sequencial por ACK Modbus
	uResponded  		: UINT;
	uConfigured 		: UINT;

    // ── stWait_K1: debounce e timeout de K1 ──────────────────────
    debouncedK1         : BOOL := FALSE;            // TRUE quando K1_in estável por TimeDebounceK1
    TonDebounceK1       : TON;                      // acumula tempo de estabilidade de K1_in
    TimeDebounceK1      : TIME := T#500MS;          // tempo mínimo de estabilidade para K1
    TonK1Timeout        : TON;                      // timeout máximo aguardando K1 fechar
    TimeK1Timeout       : TIME := T#5S;             // tempo máximo para K1 responder

    // ── stWait_K2: debounce e timeout de K2 ──────────────────────
    debouncedK2         : BOOL := FALSE;            // TRUE quando K2_in estável por TimeDebounceK2
    TonDebounceK2       : TON;                      // acumula tempo de estabilidade de K2_in
    TimeDebounceK2      : TIME := T#500MS;          // tempo mínimo de estabilidade para K2
    TonK2Timeout        : TON;                      // timeout máximo aguardando K2 fechar
    TimeK2Timeout       : TIME := T#5S;             // tempo máximo para K2 responder

END_VAR

    // INICIA AQUI
    
    auxK1_in := GVL_Main.K1_in;
    auxK2_in := GVL_Main.K2_in;
    
    IF stState = E_StartupStatus.stDone THEN
    	stState := E_StartupStatus.stInit;
    END_IF
    
    CASE stState OF 																				// Máquina de estados
    
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stInit:																		// Inicialização única
    	   
    		cmdK01 			:= FALSE;
    		auxRed  		:= FALSE;
    		auxYellow 		:= FALSE;
    		auxGreen  		:= FALSE;
    		debouncedK1 	:= FALSE;
    		debouncedK2 	:= FALSE;
    		
    		// Testa leitura do relógio do sistema na inicialização
    		GVL_Main.timestampUTC := TO_UDINT(SysTimeRtcGet(GVL_Main.Result)); 							// UDINT#1528268918
    		GVL_Alarm.CRIT_RTC_FAIL:=(GVL_Main.Result <> eResultCode.OK);                        // Em caso de erro de leitura do relógio, vai para STOP
    		IF GVL_Alarm.CRIT_RTC_FAIL THEN 														
    			GVL_Main.LedRedOut:=TRUE;																// sinalizar que houve erro para ler o relógio
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_RTC_FAILED,
    				bRaised    := TRUE,
    				rParam1    := 0.0,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    			stState := E_StartupStatus.stError;
    			RETURN;
    		END_IF
    		
    		// -----------------------------------------------------------------------------------------
    		// PREPARAÇÃO DO TEMPO DE CICLO - feito na inicialização
    
    		// Converte TIME (ex: T#500ms) para REAL (0.5 segundos) para uso nos PIDs
    		GVL_Main.ControlCycle := UDINT_TO_REAL(GVL_Main.CYCLE_TIME_MS)/1000;  				// converte para segundos
    		GVL_Main.CYCLE_TIME_TOLERANCE:=TO_UDINT(TO_REAL(GVL_Main.CYCLE_TIME_MS)*1.2);
    		
    		// -----------------------------------------------------------------------------------------
    		// ################## Parâmetros inicialmente hardcoded, depois do CSV #####################
    		// Porta de comunicação COM1
    		// Medidor COM1
    		GVL_Comm.uiMeterSlaveId := 100;    							// Slave address do medidor
    		GVL_Comm.uiMeterStartReg:= 16#2006;
    		GVL_Comm.uiMeterRegCount:= 44;
    		GVL_Comm.uiMeterPollMs  := 800;
    		GVL_Comm.udiMeterTimeout:= 2_000_000;
    
    		// Inversores COM1 (slave addresses 101..115)
    		FOR indice := 1 TO 15 DO
    			GVL_Comm.auiInvSlaveIdsCOM1[indice] := 100 + indice;   // 101, 102, ..., 115
    		END_FOR
    
    		// Inversores COM2 (slave addresses 201..215)
    		FOR indice := 1 TO 15 DO
    			GVL_Comm.auiInvSlaveIdsCOM2[indice] := 200 + indice;   // 201, 202, ..., 215
    		END_FOR
    		
    		// Endereços de registro por canal: definidos em GVL_ModbusProfiles
        	// (Profile_Goodwe_GW50K.WriteMap[0].Address = 16#0100, [1].Address = 16#0101)
        	// Não inicializar aqui — os endereços estão no profile como CONSTANT.
    			
    		// -----------------------------------------------------------------------------------------
    		// CONTAGEM AUTOMÁTICA DE INVERSORES (sequencial por potência)
    		
    		// COM1: índices 1..15
    		GVL_Main.NInversoresCOM01 := 0;
    		FOR indice := 1 TO 15 DO
    			IF GVL_Pers.InvActivePower[indice] > 0.0 THEN
    				GVL_Main.NInversoresCOM01 := indice;   // mantém maior índice válido
    			ELSE
    				EXIT;  // encontrou buraco -> encerra contagem
    			END_IF
    		END_FOR
    		
    		// COM2: índices 16..30
    		GVL_Main.NInversoresCOM02 := 0;
    		FOR indice := 16 TO 30 DO
    			IF GVL_Pers.InvActivePower[indice] > 0.0 THEN
    				GVL_Main.NInversoresCOM02 := indice - 15;   // converte para faixa 1..15
    			ELSE
    				EXIT;  // encontrou buraco -> encerra contagem
    			END_IF
    		END_FOR		
    		
    		GVL_Main.MAX_CH1_MODBUS_ERROS		:= GVL_Main.NInversoresCOM01 / 2;					// permite < 50% da quantidade de inversores sem ir para FAIL
    		GVL_Main.MAX_CH1_MODBUS_TIMEOUTS	:= GVL_Main.NInversoresCOM01 / 2;					// permite < 50% da quantidade de inversores sem ir para FAIL
    		GVL_Main.MAX_CH2_MODBUS_ERROS		:= GVL_Main.NInversoresCOM02 / 2;					// permite < 50% da quantidade de inversores sem ir para FAIL
    		GVL_Main.MAX_CH2_MODBUS_TIMEOUTS	:= GVL_Main.NInversoresCOM02 / 2;					// permite < 50% da quantidade de inversores sem ir para FAIL
    		
    		// -----------------------------------------------------------------------------------------
    		// CÁLCULO DA POTÊNCIA INSTALADA TOTAL (Ativa e Aparente)  - feito na inicialização
    
    		// Soma a capacidade nominal de todos os inversores configurados.
    		// Isso permite mudar a planta dinamicamente sem recompilar.
    		
    		GVL_Main.InstalledPower := 0.0;
    		GVL_Main.InstalledSmax  := 0.0;
    		
    		FOR indice := 1 TO GVL_Main.NMAXINVERSORES DO
    			// Soma Potência Ativa Máxima (kW)
    			GVL_Main.InstalledPower := GVL_Main.InstalledPower + GVL_Pers.InvActivePower[indice];
    			// Soma Potência Aparente Máxima (kVA)
    			GVL_Main.InstalledSmax := GVL_Main.InstalledSmax + GVL_Pers.InvSmaxPower[indice];
    		END_FOR
    
    		// Se não houver inversores ou potência válida, zera tudo e sai
    		
    		GVL_Alarm.CRIT_INSTALLED_PWR_ZERO:= (GVL_Main.InstalledPower <= 0.0);
    		IF GVL_Alarm.CRIT_INSTALLED_PWR_ZERO THEN
    			GVL_Main.TotalReactivePower := 0.0;
    			GVL_Main.LedRedOut:=TRUE;
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_INSTALLED_PWR_ZERO,
    				bRaised    := TRUE,
    				rParam1    := GVL_Main.TotalReactivePower,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    			stState := E_StartupStatus.stError;
    			RETURN;
    		END_IF
    		
    		GVL_Alarm.CRIT_INSTALLED_SMAX_ZERO:= (GVL_Main.InstalledSmax <= 0.0);
    		IF GVL_Alarm.CRIT_INSTALLED_SMAX_ZERO THEN
    			GVL_Main.TotalReactivePower := 0.0;
    			GVL_Main.LedRedOut:=TRUE;
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_INSTALLED_SMAX_ZERO,
    				bRaised    := TRUE,
    				rParam1    := GVL_Main.TotalReactivePower,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    			stState := E_StartupStatus.stError;
    			RETURN;
    		END_IF
    		
    		// Calcula Q_max_permitido 
    	    GVL_Main.Q_max_permitido := GVL_Main.InstalledPower * 0.4256;  						// tan(acos(0.92))
    			
    		// Configura TC_Power_kW se não foi configurado
    		GVL_Alarm.CRIT_TC_POWER_NOT_SET:=(GVL_Pers.TC_Power_kW = 0.0);
    		IF GVL_Alarm.CRIT_TC_POWER_NOT_SET THEN
    			GVL_Pers.TC_Power_kW := GVL_Main.InstalledPower;  							// Aproximação conservadora
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_TC_POWER_NOT_SET,
    				bRaised    := TRUE,
    				rParam1    := GVL_Pers.TC_Power_kW,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    			stState := E_StartupStatus.stError;
    			RETURN;
    		END_IF
    		
    		// zera setpoints por segurança
            FOR indice := 1 TO GVL_Main.NMAXINVERSORES DO
                GVL_Main.P_inv_kW[indice] := 0.0;
                GVL_Main.P_inv_Percent[indice] := 0.0;
                GVL_Main.Q_inv_kvar[indice] := 0.0;
            END_FOR
    
    		// Muda para próximo estado	
    		stState := E_StartupStatus.stCheck_COM;
    		
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stCheck_COM:
    	    // ────────────────────────────────────────────────────────────
            // Aguarda o driver Modbus RTU atingir RUNNING em COM1 e COM2.
            // Necessário porque no boot o driver passa por INITIALIZING
            // antes de ficar pronto — verificação única em stInit falharia
            // sistematicamente em power cycles.
            //
            // Permanece aqui até:
            //   a) Ambos RUNNING            → avança para stWait_K1
            //   b) TonComTimeout.Q          → stError (driver não inicializou)
            //
            // LEDs: vermelho piscante não disponível (sem saída PWM).
            // Mantém vermelho sólido durante a espera — estado não operacional.
            // ────────────────────────────────────────────────────────────
    
            auxRed    := TRUE;
            auxYellow := FALSE;
            auxGreen  := FALSE;
            cmdK01    := FALSE;    // K1 permanece aberto durante verificação
    
            TonComTimeout(IN := TRUE, PT := TimeComTimeout);
    
            xMaster01IsReady := GVL_Comm.bCOM1Connected;
            xMaster02IsReady := GVL_Comm.bCOM2Connected;
    
            IF xMaster01IsReady AND xMaster02IsReady THEN
                // Sucesso: driver pronto em ambas as COMs
                TonComTimeout(IN := FALSE);
                GVL_Alarm.CRIT_SERIAL_INIT_FAIL := FALSE;
                IF NOT bComLogSent THEN
                    FC_LogEvent(
                        eCode      := E_EventCode.INFO_SERIAL_COM_OK,
                        bRaised    := TRUE,
                        rParam1    := 0.0,
                        rParam2    := 0.0,
                        uMachState := GVL_Main.MachineState
                    );
                    bComLogSent := TRUE;
                END_IF
                stState := E_StartupStatus.stCheck_Medidor;
    
            ELSIF TonComTimeout.Q THEN
                // Falha: driver não atingiu RUNNING dentro do tempo limite
                TonComTimeout(IN := FALSE);
                GVL_Alarm.CRIT_SERIAL_INIT_FAIL := TRUE;
                GVL_Main.LedRedOut := TRUE;
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_SERIAL_INIT_FAILED,
                    bRaised    := TRUE,
                    rParam1    := BOOL_TO_REAL(NOT xMaster01IsReady),  // 1.0 = COM1 falhou
                    rParam2    := BOOL_TO_REAL(NOT xMaster02IsReady),  // 1.0 = COM2 falhou
                    uMachState := GVL_Main.MachineState
                );
                stState := E_StartupStatus.stError;
    
            // ELSE: driver ainda em INITIALIZING — permanece neste estado,
            //       TonComTimeout acumulando. Sem ação, sem transição.
            END_IF
    
    		(* Nota sobre `rParam1`/`rParam2`:** 
    		passar `BOOL_TO_REAL(NOT xMaster01IsReady)` codifica qual COM falhou diretamente no evento
    		 — `rParam1=1.0` significa COM1 não subiu, `rParam2=1.0` significa COM2 não subiu. 
    		Isso permite diagnóstico imediato sem precisar de outro evento.
    		*)
    		
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stCheck_Medidor:
    
        TonMedTimeout(IN := TRUE, PT := TimeMedTimeout);
    
        // A leitura do medidor é feita pela Task_ModbusComm (PRG_ModbusComm)
        // Verificamos aqui se uma leitura bem-sucedida já ocorreu
        IF GVL_Comm.bMeterReadDone AND (GVL_Comm.eMeterResult = E_ModbusResult.DONE) THEN
            TonMedTimeout(IN := FALSE);
            GVL_Alarm.CRIT_MEAS_INIC_ERRO_TIMEOUT := FALSE;
            stState := E_StartupStatus.stCheck_Inversores;
    
        ELSIF GVL_Comm.bMeterReadDone AND 
              (GVL_Comm.eMeterResult = E_ModbusResult.ERRO OR 
               GVL_Comm.eMeterResult = E_ModbusResult.TIMEOUT) THEN
            GVL_Alarm.CRIT_MEAS_INIC_ERRO_TIMEOUT := TRUE;
            FC_LogEvent(
                eCode      := E_EventCode.CRIT_MEAS_INIC_ERRO_TIMEOUT,
                bRaised    := TRUE,
                rParam1    := 0.0,
                rParam2    := 0.0,
                uMachState := GVL_Main.MachineState
            );
            stState := E_StartupStatus.stError;
        END_IF
    
        IF TonMedTimeout.Q THEN
            FC_LogEvent(
                eCode      := E_EventCode.CRIT_MEAS_INIC_FAIL,
                bRaised    := TRUE,
                rParam1    := 0.0,
                rParam2    := 0.0,
                uMachState := GVL_Main.MachineState
            );
            stState := E_StartupStatus.stError;
        END_IF
    
    
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────	
    	E_StartupStatus.stCheck_Inversores:
    	// testa comunicação com inversores
    
            auxRed    := TRUE;
            auxYellow := FALSE;
            auxGreen  := FALSE;
            cmdK01    := FALSE;
    
    		fbCheckInv(
    			xEnable      := TRUE,
    			rClientCOM1  := PRG_ModbusComm.clientCOM1,    			// Referência ao client
    			rClientCOM2  := PRG_ModbusComm.clientCOM2,
    			auiSlaveIdsCOM1 := GVL_Comm.auiInvSlaveIdsCOM1,        // Preenchidos no stInit
    			auiSlaveIdsCOM2 := GVL_Comm.auiInvSlaveIdsCOM2
    		);
    
            IF fbCheckInv.xDone THEN
    			
    			uResponded  := fbCheckInv.uRespondedTotal;
    			uConfigured := fbCheckInv.uConfiguredTotal;
    
    			fbCheckInv(
    				xEnable      := FALSE,
    				rClientCOM1  := PRG_ModbusComm.clientCOM1,    // Referência ao client
    				rClientCOM2  := PRG_ModbusComm.clientCOM2,
    				auiSlaveIdsCOM1 := GVL_Comm.auiInvSlaveIdsCOM1,        // Preenchidos no stInit
    				auiSlaveIdsCOM2 := GVL_Comm.auiInvSlaveIdsCOM2
    			);
    
                IF uResponded < uConfigured THEN
                    // Passou no limiar mas com ausências — warning
                    GVL_Alarm.WARN_INV_CHECK_PARTIAL := TRUE;
                    FC_LogEvent(
                        eCode      := E_EventCode.WARN_INV_CHECK_PARTIAL,
                        bRaised    := TRUE,
                        rParam1    := TO_REAL(fbCheckInv.uRespondedTotal),
                        rParam2    := TO_REAL(fbCheckInv.uConfiguredTotal),
                        uMachState := GVL_Main.MachineState
                    );
                ELSE
                    FC_LogEvent(
                        eCode      := E_EventCode.INFO_INV_CHECK_OK,
                        bRaised    := TRUE,
                        rParam1    := TO_REAL(fbCheckInv.uRespondedTotal),
                        rParam2    := TO_REAL(fbCheckInv.uConfiguredTotal),
                        uMachState := GVL_Main.MachineState
                    );
    				GVL_Alarm.WARN_INV_CHECK_PARTIAL := FALSE;
                	GVL_Alarm.CRIT_INV_CHECK_BELOW_THRESHOLD := FALSE;
                END_IF
                stState := E_StartupStatus.stWait_K1;
    
            ELSIF fbCheckInv.xFailed THEN
    			fbCheckInv(
    				xEnable      := FALSE,
    				rClientCOM1  := PRG_ModbusComm.clientCOM1,    // Referência ao client
    				rClientCOM2  := PRG_ModbusComm.clientCOM2,
    				auiSlaveIdsCOM1 := GVL_Comm.auiInvSlaveIdsCOM1,        // Preenchidos no stInit
    				auiSlaveIdsCOM2 := GVL_Comm.auiInvSlaveIdsCOM2
    			);
    
                GVL_Alarm.CRIT_INV_CHECK_BELOW_THRESHOLD := TRUE;
                FC_LogEvent(
                    eCode      := E_EventCode.CRIT_INV_CHECK_BELOW_THRESHOLD,
                    bRaised    := TRUE,
                    rParam1    := TO_REAL(fbCheckInv.uRespondedTotal),
                    rParam2    := TO_REAL(fbCheckInv.uConfiguredTotal),
                    uMachState := GVL_Main.MachineState
                );
                stState := E_StartupStatus.stError;
            END_IF
            // BUSY: fbCheckInv ainda varrendo — permanece no estado	
    	
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stWait_K1:																// DEBOUNCE K1
            
    		cmdK01 := TRUE;
    		auxRed := TRUE;																		// Status: aguardando K1 com debounce
    		auxYellow := FALSE;
    		auxGreen := FALSE;
    		
    		TonDebounceK1(IN := auxK1_in, PT := TimeDebounceK1);
    		TonK1Timeout (IN := TRUE, PT := TimeK1Timeout);   
    
    		IF TonDebounceK1.Q THEN
    		  debouncedK1 := TRUE;
    		ELSE
    		  debouncedK1 := FALSE;
    		END_IF
    	
    		IF debouncedK1 AND (auxK1_in=TRUE) THEN
    		  // Para o timeout (não é mais necessário)
    		  TonK1Timeout(IN := FALSE);
    		  stState := E_StartupStatus.stWait_K2;												// Somente avança se K1 está estabilizado
    		  debouncedK2 := FALSE;
    		  TonDebounceK1(IN := FALSE, PT := TimeDebounceK1); 								// (Opcional) reseta timer
    		  auxRed := FALSE;																	// Status: aguardando K1 com debounce
    		  auxYellow := TRUE;
    		  auxGreen := FALSE;
    		  FC_LogEvent(
    			eCode      := E_EventCode.INFO_K1_CONFIRMED,
    			bRaised    := TRUE,
    			rParam1    := 0.0,
    			rParam2    := 0.0,
    			uMachState := GVL_Main.MachineState
    		  );
    		ELSIF TonK1Timeout.Q THEN															   // Se estourou timeout antes de confirmar debounce, gera alarme + evento crítico (1x)
    			GVL_Alarm.CRIT_K1_TIMEOUT:=TonK1Timeout.Q;
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_K1_TIMEOUT,
    				bRaised    := TRUE,
    				rParam1    := 0.0,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    		 	TonK1Timeout(IN := FALSE);
    			stState := E_StartupStatus.stError;
    		END_IF
    
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stWait_K2:	
      
      		TonDebounceK2(IN := auxK2_in, PT := TimeDebounceK2);  								// debounce para K2_in
    		TonK2Timeout (IN := TRUE, PT := TimeK2Timeout);   
    		
    		IF TonDebounceK2.Q THEN																// tDebounce.Q será TRUE se K2_in estável
    		  debouncedK2 := TRUE;
    		ELSE     																					
    		  debouncedK2 := FALSE;																// se K2_in voltar a false, reseta timer
    		END_IF
    	
    		IF debouncedK2 AND (auxK2_in=TRUE) THEN
    		  TonK2Timeout(IN := FALSE);
    		  stState := E_StartupStatus.stDone;												// K2_ok e estável, processo de startup completo
    		  TonDebounceK2(IN := FALSE, PT := TimeDebounceK2); 								// (Opcional) reseta timer
    		  auxRed := FALSE;																	
    		  auxYellow := FALSE;
    		  auxGreen := TRUE;
    		  FC_LogEvent(
    			eCode      := E_EventCode.INFO_K2_CONFIRMED,
    			bRaised    := TRUE,
    			rParam1    := 0.0,
    			rParam2    := 0.0,
    			uMachState := GVL_Main.MachineState
    		  );
    		ELSIF TonK2Timeout.Q THEN 							// Se estourou timeout antes de confirmar debounce, gera alarme + evento crítico (1x)
    			GVL_Alarm.CRIT_K2_TIMEOUT:=TonK2Timeout.Q;
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_K2_TIMEOUT,
    				bRaised    := TRUE,
    				rParam1    := 0.0,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    		 	TonK2Timeout(IN := FALSE);
    			stState := E_StartupStatus.stError;
    		END_IF		
    	
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stDone:
    	
    		auxRed := FALSE;		
    		auxYellow := FALSE;
    		auxGreen := TRUE;
    		FC_LogEvent(
    			eCode      := E_EventCode.INFO_STARTUP_DONE,
    			bRaised    := TRUE,
    			rParam1    := 0.0,
    			rParam2    := 0.0,
    			uMachState := GVL_Main.MachineState
    		);
            // Permanece em stDone — MainProgram transitará para READ neste ciclo.
            // A guarda acima garante reset para stInit na próxima vez que
            // fbStart() for chamado (retorno ao estado START pelo operador).
    		
    	// ────────────────────────────────────────────────────────────
    	// ────────────────────────────────────────────────────────────
    	E_StartupStatus.stError:
    		auxRed    := TRUE;
    		auxYellow := FALSE;
    		auxGreen  := FALSE;
    		// sai do case e no MainProgam vai para o estado ERRO
    		
    END_CASE;
    
    //   Aplicar comandos calculados às saídas físicas / públicas
    GVL_Main.K1_out 		:= cmdK01;
    GVL_Main.LedRedOut 		:= auxRed;
    GVL_Main.LedYellowOut 	:= auxYellow;
    GVL_Main.LedGreenOut 	:= auxGreen;
END_FUNCTION_BLOCK
