{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT

    // Parâmetros do sistema
    SOFTVERSION          		: UINT := 21;   					// Versão da aplicação
	DATAAPLICATION				: DATE := DATE#2025-12-05;			// Data da aplicação
	NMAXINVERSORES				: UINT := 30;						// Capacidade máxima de inversores
	TIPOSINVERSORES				: UINT := 8;						// total de inversores diferentes que podem estar presentes
	NDATASESPECIAIS 			: UINT := 48; 						// Quantidade de datas especiais disponíveis ao todo (para 10 anos)
	TIMEZONEOFFSET				: DINT := -3; 			
	MAX_Meas_MODBUS_ERROS		: UDINT := 3;						// quantidade de erros permitido na leitura do medidor
	MAX_Meas_MODBUS_TIMEOUTS	: UDINT := 3;						// quantidade de timeouts permitido na leitura do medidor

	
END_VAR

VAR_GLOBAL
	timestampUTC				: UDINT;
	Result 						: RTS_IEC_RESULT;
  	ControlCycle    			: REAL:=1;            					// Tempo de ciclo de controle em SEGUNDOS (ex: 1.0 = 1 segundo)
	MachineState				: E_MachineState:= E_MachineState.START;
	fbEventLog 					: FB_EventLog;						// Function Block de registro de eventos 
	
	CYCLE_TIME_MS				: UDINT := 1000;  					// tempo de ciclo de controle
	CYCLE_TIME_TOLERANCE		: UDINT := 1200;  					// tolerancia de ultrapassagem para tempo de ciclo de controle de 20%
	
	// Saidas digitais
  	K1_out  					: BOOL;   							// DI X5_1 - K1 - controle permissivo
	K2_out						: BOOL;								// DI X5_2 - K2 - controle trip
  	LedRedOut					: BOOL;								// DI X5_3 - nada pronto - K1 e K2 abertos
  	LedYellowOut  				: BOOL;   							// DI X5_4 - K1 fechou - permissivo ok
  	LedGreenOut  				: BOOL;   							// DI X5_5 - K2 fechou - acende verde -tudo pronto

	// Entredas digitais
	K1_in        				: BOOL;                				// DI X12_1 - contato auxliar de K1_in=1 => K1 fechado (permite gerar)
  	K2_in        				: BOOL;                				// DI X12_2 - contato auxliar de K2_in=1 => K2 fechado (permite gerar) trip desarmado

    // Comandos da IHM
    // ─────────────────────────────────────────────────────────────
  	HMI_StartResetButton     	: BOOL := FALSE;           			// DI X12_3 - botao frontal para comandar ligar/reset geral quando no estado STOP
    HMI_TurnOffButton    		: BOOL := FALSE;  					// DI X12_4 "Desligar controlado"


    //    Medições (REAL) - Tensões (V), Correntes (A), Potências Ativas (W), Potências Reativas (var), PF (adimensional, sinal: + indutivo, - capacitivo)
	
    Ua  						: REAL := 0.0; // Tensão de fase A   - 2006H - Tensão de fase A em Volts (x 0,1 V)
    Ub  						: REAL := 0.0; // Tensão de fase B   - 2008H - Tensão de fase B em Volts (x 0,1 V)
    Uc  						: REAL := 0.0; // Tensão de fase C   - 200AH - Tensão de fase C em Volts (x 0,1 V)
	
	Ia    						: REAL 	:= 0.0; // 200CH - Corrente de fase A em A (x 0,001 A) 
	Ib    						: REAL 	:= 0.0; // 200EH - Corrente de fase B em A (x 0,001 A) 
	Ic    						: REAL 	:= 0.0; // 2010H - Corrente de fase C em A (x 0,001 A) 
	
	Pt    						: REAL 	:= 0.0; // 2012H - Potencia ativa combinada em kW (x 0.1 para W, x 0.0001 para kW)
	Pa    						: REAL 	:= 0.0; // 2014H - Potencia ativa fase A 	em kW (x 0.1 para W, x 0.0001 para kW)
	Pb    						: REAL 	:= 0.0; // 2016H - Potencia ativa fase B 	em kW (x 0.1 para W, x 0.0001 para kW)
	Pc    						: REAL 	:= 0.0; // 2018H - Potencia ativa fase C    em kW (x 0.1 para W, x 0.0001 para kW)

	Qt    						: REAL 	:= 0.0; // 201AH - Potencia reativa combinada em kvar (x 0.1 para var, x 0.0001 para kvar)
	Qa    						: REAL 	:= 0.0; // 201CH - Potencia reativa fase A	 em kvar (x 0.1 para var, x 0.0001 para kvar)
	Qb    						: REAL 	:= 0.0; // 201EH - Potencia reativa fase B	 em kvar (x 0.1 para var, x 0.0001 para kvar)
	Qc    						: REAL 	:= 0.0; // 2020H - Potencia reativa fase C	 em kvar (x 0.1 para var, x 0.0001 para kvar)
	
	PFt    						: REAL 	:= 0.0; // 202AH - Fator de potência combinado (número positivo: indutivo, número negativo: capacitivo) (x0,001)
	PFa    						: REAL 	:= 0.0; // 202CH - Fator de potência de fase A (número positivo: indutivo, número negativo: capacitivo) (x0,001)
	PFb    						: REAL 	:= 0.0; // 202EH - Fator de potência de fase B (número positivo: indutivo, número negativo: capacitivo) (x0,001)
	PFc    						: REAL 	:= 0.0; // 2030H - Fator de potência de fase C (número positivo: indutivo, número negativo: capacitivo) (x0,001)	


	// definição dos inversores dos dois canais de comunicação
	MAX_CH1_MODBUS_ERROS		: UINT := 0;						// < 50% da quantidade de inversores sem ir para FAIL
	MAX_CH1_MODBUS_TIMEOUTS		: UINT := 0;						// < 50% da quantidade de inversores sem ir para FAIL
	MAX_CH2_MODBUS_ERROS		: UINT := 0;						// < 50% da quantidade de inversores sem ir para FAIL
	MAX_CH2_MODBUS_TIMEOUTS		: UINT := 0;						// < 50% da quantidade de inversores sem ir para FAIL
	NInversoresCOM01    		: UINT :=0;
	NInversoresCOM02    		: UINT :=0;
 	




    //   COMANDOS E TELEMETRIA - Saídas do Controle
	
	// Potencia Total instalada e potencia Aparente Total instalada
  	InstalledPower 				: REAL; 		// Soma da potência nominal de todos os inversores ativos
	Q_max_permitido 			: REAL := 0.0;  // Q máximo permitido (kvar)
	InstalledSmax   			: REAL; 		// NOVO: Potência Aparente Máxima Total (kVA)	
	
	// COMANDOS DE CONTROLE
	MaxExportLimit 	: REAL;              											// Limite de exportação do scheduler (kW)
	P_cmd_total_kW 	: REAL;              											// Comando total de P (kW)
	Q_cmd_total_kvar: REAL;            												// Comando total de Q (kvar)
	
    // Telemetria: Setpoint atual da agenda (antes das proteções)
    TotalPowerPercent : REAL;

    // Telemetria: Potência Reativa total desejada (kVA)
    TotalReactivePower : REAL;

    // Telemetria: Valores efetivos calculados para cada inversor
    P_inv_kW     	: ARRAY[1..NMAXINVERSORES] OF REAL; 							// valor de setpoint de potencia ativa em kW
	P_inv_Percent 	: ARRAY[1..NMAXINVERSORES] OF REAL; 							// valor de setpoint de potencia ativa em percentual do nominal
	P_inv_limit 	: ARRAY[1..NMAXINVERSORES] OF REAL; 							// valor limite de potencia ativa com base na SMAX de cada um
    Q_inv_kvar    	: ARRAY[1..NMAXINVERSORES] OF REAL; 							// valor de setpoint de potencia reativa em kVA
    PF_inv 			: ARRAY[1..NMAXINVERSORES] OF REAL; 							// valor do fator de potencia de cada inversor (deve ser 0,92 para todos)
	PF_inv_Percent	: ARRAY[1..NMAXINVERSORES] OF REAL; 							// valor de setpoint de fator de potencia em percentual
	
	// Margem de segurança para compensar erro de TC perto de zero, o sistema tentará manter importação mínima garantido que não haja exportação
	SafetyMargin_pct: REAL :=0.03;
	TC_Power_kW		: REAL := 0.0; // deve ser configurado como 3% da potencia total sob controle pelo TC
	
	// ════════════════════════════════════════════════════════════════
	// DIAGNÓSTICO DE FATOR DE POTÊNCIA
	// ════════════════════════════════════════════════════════════════
	Q_available_max : REAL;             											// Q máximo disponível (kvar)
	PF_effective 	: REAL;                											// PF efetivo resultante
	PFErro 			: BOOL;                   										// TRUE = PF < 0.92 não atingível (banco de capacitores)
    
	// ════════════════════════════════════════════════════════════════
    // DIAGNÓSTICO DE FATOR DE POTÊNCIA
    // ════════════════════════════════════════════════════════════════

    // Status geral
    PF_target : REAL := 0.92;                   									// PF alvo (mínimo aceitável)
    PF_measured : REAL;                         // PF medido no ponto de conexão
    PF_achieved : REAL;                         // PF efetivamente alcançado após compensação
    PF_OK : BOOL;                               // TRUE = PF ≥ 0.92
    
    // Potências
    P_generated_kW : REAL;                      // P total gerado pelos inversores
    P_allocated_kW : REAL;                      // P efetivamente alocado
    Q_measured_kvar : REAL;                     // Q medido no ponto de conexão (carga)
    Q_required_kvar : REAL;                     // Q necessário para atingir PF ≥ 0.92
    Q_commanded_kvar : REAL;                    // Q comandado pelo FB_PIQ
    Q_available_kvar : REAL;                    // Q que inversores conseguem fornecer
    Q_allocated_kvar : REAL;                    // Q efetivamente alocado
    Q_deficit_kvar : REAL;                      // Déficit de Q (se > 0, falta Q)
    
    // Capacidade dos inversores
    S_total_available_kVA : REAL;               // S total disponível (soma de todos inversores)
    S_total_used_kVA : REAL;                    // S total utilizado
    S_utilization_pct : REAL;                   // % de utilização de S
    Q_capacity_total_kvar : REAL;               // Capacidade total de Q dos inversores (atual)
    Q_utilization_pct : REAL;                   // % de utilização de Q
    
    // Diagnóstico e recomendações
    Q_deficit_percent : REAL;                   // Déficit de Q em % do necessário
    Capacitor_bank_size_kvar : REAL;            // Tamanho recomendado de banco de capacitores
    Capacitor_bank_recommended : BOOL;          // TRUE = Recomenda banco de capacitores
    PF_alarm_code : UINT;                       // Código de alarme (0=OK, 1=Aviso, 2=Crítico)
    
    // Histórico (opcional)
    PF_min_24h : REAL := 1.0;                   // PF mínimo nas últimas 24h
    PF_avg_24h : REAL := 1.0;                   // PF médio nas últimas 24h
    Q_deficit_max_24h : REAL;                   // Déficit máximo de Q nas últimas 24h
    PF_alarm_count_24h : UDINT;                 // Quantidade de alarmes nas últimas 24h
    
    // Inversores individuais (diagnóstico detalhado)
    Inv_S_utilization : ARRAY[1..NMAXINVERSORES] OF REAL;  // % S usado por inversor
    Inv_Q_available : ARRAY[1..NMAXINVERSORES] OF REAL;    // Q disponível por inversor (kvar)
    Inv_limited : ARRAY[1..NMAXINVERSORES] OF BOOL;        // TRUE = Inversor limitado por S	
END_VAR
    
