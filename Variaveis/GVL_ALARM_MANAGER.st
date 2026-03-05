{attribute 'qualified_only'}
VAR_GLOBAL
    // ─────────────────────────────────────────────────────────
    // ALARM MANAGER FLAGS (condições booleanas)
    // ─────────────────────────────────────────────────────────

	// Falhas na inicialização 
	CRIT_SERIAL_INIT_FAIL			: BOOL := FALSE;	// Critico - Falha para iniciar as seriais
	CRIT_K1_TIMEOUT 				: BOOL := FALSE;    // Critico - falha na inicialização de K1 - falta detectar fechamento
	CRIT_K2_TIMEOUT 				: BOOL := FALSE;    // Critico - falha na inicialização de K2 - falta detectar fechamento

    // Medição / Medidor
    ALARM_MEAS_MODBUS_TIMEOUT      	: BOOL := FALSE;  	// timeout de leitura (READ)
    ALARM_MEAS_MODBUS_ERRO       	: BOOL := FALSE;  	// xError do medidor (READ)
    ALARM_MEAS_FROZEN	            : BOOL := FALSE;  	// diagnosticCode = A900 (se aplicável)
    ALARM_MEAS_USING_LAST_VALUEU	: BOOL := FALSE;  	// bPoucosErros=TRUE e bDadosOK=FALSE
	ALARM_MEAS_RANGE_ERROR    		: BOOL := FALSE;    // Warning: Valor fora de faixa
    ALARM_MEAS_XCHECK_FAIL   		: BOOL := FALSE;    // Warning: Validação cruzada 
    CRIT_MEAS_PERSISTENT_FAIL		: BOOL := FALSE;  	// bPoucosErros = FALSE	
    CRIT_MEAS_MODBUS_TIMEOUT      	: BOOL := FALSE;  	// timeout de leitura (READ) repeticao fora da tolerancia
    CRIT_MEAS_MODBUS_ERRO       	: BOOL := FALSE;  	// xError do medidor (READ)  repeticao fora da tolerancia

    // Comunicação inversores
    CRIT_COM_CHANNEL_FAIL           : BOOL := FALSE;  	// falha geral de comunicação → FAIL/STOP
	CRIT_CH1_MODBUS_TIMEOUT        	: BOOL := FALSE; 	// Canal COM1 TIMEOUT 3x
    CRIT_CH2_MODBUS_TIMEOUT        	: BOOL := FALSE; 	// Canal COM2 TIMEOUT 3x
	CRIT_CH1_MODBUS_ERRO	       	: BOOL := FALSE;  	// >50% falhas COM1 no ciclo
    CRIT_CH2_MODBUS_ERRO        	: BOOL := FALSE;  	// >50% falhas COM2 no ciclo

    // Sistema
	ALARM_SCAN_OVERRUN        		: BOOL := FALSE;    // Warning: Watchdog de ciclo
    CRIT_TC_POWER_NOT_SET           : BOOL := FALSE;    // TC_Power_kW = 0 na inicialização
    CRIT_NO_INVERTERS        		: BOOL := FALSE;    // Error: Nenhum inversor configurado
    CRIT_RTC_FAIL            		: BOOL := FALSE;    // Error: Falha RTC
    CRIT_INSTALLED_PWR_ZERO  		: BOOL := FALSE;    // Error: Potência instalada = 0
	CRIT_INSTALLED_SMAX_ZERO  		: BOOL := FALSE;    // Error: Potência reativa instalada = 0
	CRIT_SCAN_OVERRUN        		: BOOL := FALSE;    // CRITICO: Watchdog de ciclo 3x	

	
    // Proteções normativas
    CRIT_HARDLIMIT_15S       		: BOOL := FALSE;    // Error: P > LPI+10% por >15s
    CRIT_EXPORT_OVER_LPI_30S   		: BOOL := FALSE;    // Error: P > LPI por >30s
    CRIT_K2_NOT_OPENED       		: BOOL := FALSE;    // Error: K2 não abriu após trip
	CRIT_MEAS_TIMEOUT_IN_FAIL    	: BOOL := FALSE;	// 5s sem medição válida em FAIL → STOP
	CRIT_FAIL_ENTRY                 : BOOL := FALSE;    // Entrada no estado FAIL		

	
	// Status do sistema
	ALARM_FAIL_ACTIVE				: BOOL := FALSE;  	// MachineState=FAIL
    CRIT_STOP_ACTIVE	            : BOOL := FALSE;  	// MachineState=STOP
	CRIT_SCHEDULE_INDEX_INVALID		: BOOL := FALSE;    // Dia ou hora da semana inválido (CRITICAL)
	
    // ── Controle / PF ──
    ALARM_PF_BELOW_TARGET     		: BOOL := FALSE;    // Warning: PF < 0.92
    ALARM_PF_CRITICAL         		: BOOL := FALSE;    // Error: PF < 0.92 + Q saturado
    ALARM_Q_LIMITED_BY_SMAX    		: BOOL := FALSE;    // Info: Q limitado por S
	
	// FAIL-SAFE avançado
	ALARM_FAIL_RECOVERY_STARTED     : BOOL := FALSE;    // Timer de recuperação iniciou
	CRIT_FAIL_WRITE_FAILED          : BOOL := FALSE;    // Escrita zero falhou (inversores não responderam)
	CRIT_FAIL_WRITE_EXHAUSTED       : BOOL := FALSE;    // Esgotou retentativas de escrita zero → STOP
	CRIT_FAIL_GLOBAL_TIMEOUT        : BOOL := FALSE;    // Permaneceu em FAIL além do máximo permitido
	
	    // ── TURNOFF ──
    ALARM_TURNOFF_ACTIVE            : BOOL := FALSE;    // MachineState = TURNOFF
    CRIT_TURNOFF_WRITE_EXHAUSTED    : BOOL := FALSE;    // Escrita zero esgotou tentativas
    CRIT_TURNOFF_VERIFY_TIMEOUT     : BOOL := FALSE;    // Timeout verificação geração
    CRIT_TURNOFF_K2_NOT_OPENED      : BOOL := FALSE;    // K2 não abriu após trip controlado
	CRIT_TURNOFF_K1_NOT_OPENED      : BOOL := FALSE;    // K1 não abriu após comando

END_VAR
