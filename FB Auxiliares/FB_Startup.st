(* FB: fbStartup
   1) Ativa K1_out
   2) Aguarda 400 ms antes de verificar se K1_in está ativo
      -> Se K1_in NÃO estiver ativo depois deste tempo, sinaliza erro e sai da fbStartup
   3) Monitorar K2_in com debounce até ficar ativo 
   4) Enquanto aguarda K2_in ativar, mantém K4_out ativo
   5) Quando K2_in ativar (após debounced), desativa K4_out e ativa K5_out
   6) O controlador aguarda até K2_in = TRUE
   Notas:
   	- IMPORTANTE: se não forem usados contados auxiliares nos disjuntores, K1_in e K2_in precisam ser conectados a 24V
	- Este FB apenas sinaliza os outputs K1_out, K3_out, K4_out e K5_out.
   	- Implementado com máquina de estados e TONs (tDelay e tDebounce). TON deve ser chamado toda iteração.  *)
   
FUNCTION_BLOCK FB_Startup
VAR_OUTPUT
  stState			: E_StartupStatus:= E_StartupStatus.stInit;
END_VAR

VAR
  fbChannel       	: ModbusChannel;
  debouncedK1     	: BOOL := FALSE;   														// flag auxiliar informando que K1_in está estável em 1 
  TonDebounceK1     : TON;                          				// Novo timer debounce K1_in
  TimeDebounceK1    : TIME := T#500MS;              				// Tempo de debounce para K1
  TonK1Timeout		: TON;											// Timeout para acionamento de K1
  TimeK1Timeout		: TIME := T#5S;
  
  debouncedK2 		: BOOL := FALSE; 								// flag auxiliar informando que K2_in está estável em 1 
  TonDebounceK2 	: TON;   										// timer para debounce de bk2 
  TimeDebounceK2    : TIME := T#500MS;     							// tempo de debounce para leitura de K2_in 
  TonK2Timeout		: TON;											// Timeout para acionamento de K2
  TimeK2Timeout		: TIME := T#5S;
  
  cmdK01     		: BOOL := FALSE;  								// comandos calculados por ciclo e aplicados no final 
  auxRed     		: BOOL := FALSE;
  auxYellow     	: BOOL := FALSE;
  auxGreen     		: BOOL := FALSE;
  auxK1_in  		: BOOL;											// entradas digitais lidas no inicio da função 
  auxK2_in			: BOOL;
  indice			: UINT;
  
  // Variáveis para o Master 01 (COM1)
  eDeviceState01     		: DED.DEVICE_STATE; 					// Para guardar o estado retornado
  xDiagInfoIsAvailable01 	: BOOL;            						// Para guardar a saída xDiagnosisInfoAvailable
  eError01	      	    	: DED.ERROR;        					// Para guardar o código de erro
  xMaster01IsReady   		: BOOL;            						// Nosso booleano final de "pronto"
  
  // Variáveis para o Master 02 (COM2)
  eDeviceState02     		: DED.DEVICE_STATE; 					// Para guardar o estado retornado
  xDiagInfoIsAvailable02 	: BOOL;            						// Para guardar a saída xDiagnosisInfoAvailable
  eError02	           		: DED.ERROR;        					// Para guardar o código de erro
  xMaster02IsReady   		: BOOL;            						// Nosso booleano final de "pronto"
 
END_VAR

    // INICIA AQUI
    
    auxK1_in := GVL_Main.K1_in;
    auxK2_in := GVL_Main.K2_in;
    
    CASE stState OF 																				// Máquina de estados
    
    	E_StartupStatus.stInit:																		// Inicialização única
    	   
    		cmdK01 			:= FALSE;
    		auxRed  		:= FALSE;
    		auxYellow 		:= FALSE;
    		auxGreen  		:= FALSE;
    		debouncedK1 	:= FALSE;
    		debouncedK2 	:= FALSE;
    		
    		// Testa leitura do relógio do sistema na inicialização
    		GVL_Main.timestampUTC := TO_UDINT(SysTimeRtcGet(GVL_Main.Result)); 							// UDINT#1528268918
    		GVL_ALARM_MANAGER.CRIT_RTC_FAIL:=(GVL_Main.Result <> eResultCode.OK);                        // Em caso de erro de leitura do relógio, vai para STOP
    		IF GVL_ALARM_MANAGER.CRIT_RTC_FAIL THEN 														
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
    		// Testa seriais
    
    		eDeviceState01 := Master_01.GetDeviceState(
    			xDiagnosisInfoAvailable => xDiagInfoIsAvailable01,
    			eError                  => eError01
    			);
    		eDeviceState02 := Master_02.GetDeviceState(
    			xDiagnosisInfoAvailable => xDiagInfoIsAvailable02,
    			eError                  => eError02
    			);
      		xMaster01IsReady := (eDeviceState01 = DED.DEVICE_STATE.RUNNING); 
       		xMaster02IsReady := (eDeviceState02 = DED.DEVICE_STATE.RUNNING); 
    		
    		GVL_ALARM_MANAGER.CRIT_SERIAL_INIT_FAIL:= NOT (xMaster01IsReady AND xMaster02IsReady);		
    		
    		IF GVL_ALARM_MANAGER.CRIT_SERIAL_INIT_FAIL THEN
    			GVL_Main.LedRedOut:=TRUE;
    			stState := E_StartupStatus.stError;
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_SERIAL_INIT_FAILED,
    				bRaised    := TRUE,
    				rParam1    := 0.0,
    				rParam2    := 0.0,
    				uMachState := GVL_Main.MachineState
    			);
    			stState := E_StartupStatus.stError;
    			RETURN;
    		END_IF
    	
    		// -----------------------------------------------------------------------------------------
    		// Porta de comunicação COM1
    		GVL_Main.pMedidor100   		:= ADR(Medidor100);
    		GVL_Main.pInversores100[1]  := ADR(Inversor101);
    		GVL_Main.pInversores100[2]  := ADR(Inversor102);
    		GVL_Main.pInversores100[3]	:= ADR(Inversor103);
    		GVL_Main.pInversores100[4] 	:= ADR(Inversor104);
    		GVL_Main.pInversores100[5]	:= ADR(Inversor105);
    		GVL_Main.pInversores100[6] 	:= ADR(Inversor106);
    		GVL_Main.pInversores100[7] 	:= ADR(Inversor107);
    		GVL_Main.pInversores100[8] 	:= ADR(Inversor108);
    		GVL_Main.pInversores100[9] 	:= ADR(Inversor109);
    		GVL_Main.pInversores100[10]	:= ADR(Inversor110);
    		GVL_Main.pInversores100[11]	:= ADR(Inversor111);
    		GVL_Main.pInversores100[12] := ADR(Inversor112);
    		GVL_Main.pInversores100[13] := ADR(Inversor113);
    		GVL_Main.pInversores100[14] := ADR(Inversor114);
    		GVL_Main.pInversores100[15] := ADR(Inversor115);
    		
    		// Porta de comunicação COM2
    		GVL_Main.pMedidor200   	  	:= ADR(Medidor200);
    		GVL_Main.pInversores200[1]  := ADR(Inversor201);
    		GVL_Main.pInversores200[2]  := ADR(Inversor202);
    		GVL_Main.pInversores200[3]  := ADR(Inversor203);
    		GVL_Main.pInversores200[4]  := ADR(Inversor204);
    		GVL_Main.pInversores200[5] 	:= ADR(Inversor205);
    		GVL_Main.pInversores200[6]  := ADR(Inversor206);
    		GVL_Main.pInversores200[7]  := ADR(Inversor207);
    		GVL_Main.pInversores200[8]  := ADR(Inversor208);
    		GVL_Main.pInversores200[9]  := ADR(Inversor209);
    		GVL_Main.pInversores200[10] := ADR(Inversor210);
    		GVL_Main.pInversores200[11] := ADR(Inversor211);
    		GVL_Main.pInversores200[12] := ADR(Inversor212);
    		GVL_Main.pInversores200[13] := ADR(Inversor213);
    		GVL_Main.pInversores200[14] := ADR(Inversor214);
    		GVL_Main.pInversores200[15] := ADR(Inversor215);
    		
    		FOR indice := 1 TO 15 DO														// inicialização dos canais de comunicação
    			fbChannel(Slave := GVL_Main.pInversores100[indice]^,xExecute := FALSE,xAbort := FALSE,iChannelIndex := 0);
    			fbChannel(Slave := GVL_Main.pInversores200[indice]^,xExecute := FALSE,xAbort := FALSE,iChannelIndex := 0); 
    		END_FOR
    	
    		// -----------------------------------------------------------------------------------------
    		// CONTAGEM AUTOMÁTICA DE INVERSORES (sequencial por potência)
    		
    		// COM1: índices 1..15
    		GVL_Main.NInversoresCOM01 := 0;
    		FOR indice := 1 TO 15 DO
    			IF GVL_Persis.InvActivePower[indice] > 0.0 THEN
    				GVL_Main.NInversoresCOM01 := indice;   // mantém maior índice válido
    			ELSE
    				EXIT;  // encontrou buraco -> encerra contagem
    			END_IF
    		END_FOR
    		
    		// COM2: índices 16..30
    		GVL_Main.NInversoresCOM02 := 0;
    		FOR indice := 16 TO 30 DO
    			IF GVL_Persis.InvActivePower[indice] > 0.0 THEN
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
    			GVL_Main.InstalledPower := GVL_Main.InstalledPower + GVL_Persis.InvActivePower[indice];
    			// Soma Potência Aparente Máxima (kVA)
    			GVL_Main.InstalledSmax := GVL_Main.InstalledSmax + GVL_Persis.InvSmaxPower[indice];
    		END_FOR
    
    		// Se não houver inversores ou potência válida, zera tudo e sai
    		
    		GVL_ALARM_MANAGER.CRIT_INSTALLED_PWR_ZERO:= (GVL_Main.InstalledPower <= 0.0);
    		IF GVL_ALARM_MANAGER.CRIT_INSTALLED_PWR_ZERO THEN
    			GVL_Main.TotalReactivePower := 0.0;
    			GVL_Main.LedRedOut:=TRUE;
    			stState := E_StartupStatus.stError;
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
    		
    		GVL_ALARM_MANAGER.CRIT_INSTALLED_SMAX_ZERO:= (GVL_Main.InstalledSmax <= 0.0);
    		IF GVL_ALARM_MANAGER.CRIT_INSTALLED_SMAX_ZERO THEN
    			GVL_Main.TotalReactivePower := 0.0;
    			GVL_Main.LedRedOut:=TRUE;
    			stState := E_StartupStatus.stError;
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
    		GVL_ALARM_MANAGER.CRIT_TC_POWER_NOT_SET:=(GVL_Persis.TC_Power_kW = 0.0);
    		IF GVL_ALARM_MANAGER.CRIT_TC_POWER_NOT_SET THEN
    			GVL_Persis.TC_Power_kW := GVL_Main.InstalledPower;  							// Aproximação conservadora
    			stState := E_StartupStatus.stError;
    			FC_LogEvent(
    				eCode      := E_EventCode.CRIT_TC_POWER_NOT_SET,
    				bRaised    := TRUE,
    				rParam1    := GVL_Persis.TC_Power_kW,
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
    		stState := E_StartupStatus.stWait_K1;
    
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
    		END_IF
    		
    		GVL_ALARM_MANAGER.CRIT_K1_TIMEOUT:=TonK1Timeout.Q;
    		
    		// Se estourou timeout antes de confirmar debounce, gera alarme + evento crítico (1x)
    		IF GVL_ALARM_MANAGER.CRIT_K1_TIMEOUT THEN
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
    		END_IF
    
    		GVL_ALARM_MANAGER.CRIT_K2_TIMEOUT:=TonK2Timeout.Q;
    		
    		// Se estourou timeout antes de confirmar debounce, gera alarme + evento crítico (1x)
    		IF GVL_ALARM_MANAGER.CRIT_K2_TIMEOUT THEN
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
    		
    	
    	E_StartupStatus.stDone:
    	
    		stState := E_StartupStatus.stDone;
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
    
    END_CASE;
    
    //   Aplicar comandos calculados às saídas físicas / públicas
    GVL_Main.K1_out 		:= cmdK01;
    GVL_Main.LedRedOut 		:= auxRed;
    GVL_Main.LedYellowOut 	:= auxYellow;
    GVL_Main.LedGreenOut 	:= auxGreen;
END_FUNCTION_BLOCK
