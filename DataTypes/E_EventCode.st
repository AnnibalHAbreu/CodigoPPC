{attribute 'qualified_only'}
// ════════════════════════════════════════════════════════════════════
// E_EventCode — Código unificado de eventos do PPC-GD
// ════════════════════════════════════════════════════════════════════
//
// FAIXAS DE CÓDIGOS:
//   0x0000          = Sem evento
//   0x1xxx          = INFO     (informações operacionais)
//   0x2xxx          = WARNING  (desvios toleráveis, sem ação de potência)
//   0x4xxx          = ALARM    (falhas que requerem atenção ou degradam)
//   0x8xxx          = CRITICAL (ações de segurança: FAIL_SAFE ou STOP)
//
// SUB-FAIXAS (2º nibble = módulo):
//   x0xx = Sistema / Geral
//   x1xx = Startup (FB_Startup)
//   x2xx = Medição (FB_ReadMedidor, FB_ValidaDadosRele)
//   x3xx = Comunicação inversores (FB_WriteInv)
//   x4xx = Controle (FB_Controle, FB_PowerController, FB_PIQ)
//   x5xx = Scheduler / Agenda
//   x6xx = Máquina de Estados (MainProgram)
//   x7xx = Proteção normativa (timers 15s/30s, hard-limit)
//   x8xx = STOP / Trip
//   x9xx = Reservado para expansão
//   xAxx = Erros gerados pelo Driver Modbus do Codesys
//
// Observação: códigos legados (ex-16#C1/C2/E1/E2/E3/F1) são referenciados
// por comentário e mapeados semanticamente, sem manter o mesmo valor numérico,
// para preservar a coerência de severidade por faixa.
// ════════════════════════════════════════════════════════════════════
TYPE E_EventCode :
(
    EVT_NONE                        := 16#0000,

    // ══════════════════════════════════════════════════════════════
    // INFO (0x1xxx) — registro operacional, sem ação
    // ══════════════════════════════════════════════════════════════

    // ── Startup ──
    INFO_STARTUP_BEGIN              := 16#1100,  // Inicialização iniciada
    INFO_SERIAL_COM_OK              := 16#1101,  // COM1 e COM2 prontos
    INFO_RTC_OK                     := 16#1102,  // Relógio lido com sucesso
    INFO_INVERTER_COUNT             := 16#1103,  // Contagem de inversores concluída
    INFO_INSTALLED_POWER            := 16#1104,  // Potência instalada calculada
    INFO_K1_CONFIRMED               := 16#1105,  // K1_in confirmado (debounce)
    INFO_K2_CONFIRMED               := 16#1106,  // K2_in confirmado (debounce)
    INFO_STARTUP_DONE               := 16#1107,  // Startup completo → operação

    // ── Operação normal ──
    INFO_MEAS_READ_OK            	:= 16#1200,  // Leitura do medidor OK
    INFO_MEAS_DATA_VALID         	:= 16#1201,  // Dados validados e filtro aplicado
    INFO_MEAS_RECOVERING            := 16#1202,  // contador nErrors reduzindo (opcional)

    // ── Escrita inversores (0x13xx)
    INFO_CH1_WRITE_OK               := 16#1300,  // Escrita no canal 01 OK
	INFO_CH2_WRITE_OK               := 16#1301,  // Escrita no canal 02 OK
	
    // ── Scheduler (0x15xx)
    INFO_SPECIAL_DATE_ACTIVE        := 16#1500,  // Data especial ativa na agenda
    INFO_ZERO_GRID_MODE             := 16#1501,  // Modo Zero Grid ativo

    // ── Recuperação / Reset ──
    INFO_CYCLE_COMPLETE             := 16#1600,  // Ciclo READ→CONTROL→WRITE→IDLE OK
    INFO_FAIL_RECOVERY              := 16#1601,  // Recuperação automática do FAIL
    INFO_STATE_CHANGE               := 16#1610,  // Transição de MachineState

    // ── STOP/Reset (0x18xx)
    INFO_STOP_K2_OPEN_CONFIRMED     := 16#1800,  // K2 confirmado aberto no STOP
    INFO_STOP_RESET_APPROVED        := 16#1801,  // Reset manual aprovado
    INFO_STOP_RESET_WAITING         := 16#1802,  // Aguardando Pt estável para reset

    // ══════════════════════════════════════════════════════════════
    // WARNING (0x2xxx) — desvio tolerável, sem ação de potência
    // ══════════════════════════════════════════════════════════════

    // ── Startup ──
    WARN_NO_INVERSORES_COM02        := 16#2101,  // COM2 sem inversores (pode ser intencional)

    // ── Medição ──

    WARN_MEAS_USING_LAST_VALID      := 16#2200,  // Usando última medição válida
    WARN_MEAS_CROSS_CHECK_PA        := 16#2201,  // Validação cruzada Pa inconsistente
    WARN_MEAS_CROSS_CHECK_PB        := 16#2202,  // Validação cruzada Pb inconsistente
    WARN_MEAS_CROSS_CHECK_PC        := 16#2203,  // Validação cruzada Pc inconsistente
    WARN_MEAS_CROSS_CHECK_PT_SUM    := 16#2204,  // Pt ≠ Pa+Pb+Pc
    WARN_MEAS_CROSS_CHECK_PF        := 16#2205,  // PFt inconsistente com P/S
    WARN_MEAS_ERROR_ISOLATED        := 16#2206,  // Erro de medição isolado (1-4 erros)

    // ── Comunicação inversores ──
    WARN_WRITE_INV_ERROR            := 16#2300,  // Erro escrita em inversor individual
    WARN_WRITE_INV_TIMEOUT          := 16#2301,  // Timeout escrita em inversor individual

    // ── Controle ──
    WARN_P_ALLOC_SATURATED          := 16#2400,  // P alocado < P comandado
    WARN_Q_LIMITED_BY_SMAX          := 16#2401,  // Q limitado por Smax dos inversores
    WARN_PF_BELOW_TARGET            := 16#2402,  // PF < 0.92 (mas não por limite de S)
    WARN_PF_NOT_ACHIEVABLE          := 16#2403,  // PF impossível (banco de capacitor)
    WARN_PI_P_SATURATED             := 16#2404,  // PI de P saturado
    WARN_PI_Q_SATURATED             := 16#2405,  // PI de Q saturado
    WARN_PHASE_LIMITED              := 16#2406,  // Potência limitada por fase

    // ── STOP/reset
    WARN_STOP_RESET_DENIED          := 16#2800,  // Reset manual negado

    // ══════════════════════════════════════════════════════════════
    // ALARM (0x4xxx) — falha que requer atenção, pode degradar
    // ══════════════════════════════════════════════════════════════

    // ── Medição — Range ──
    ALARM_MEAS_VOLTAGE_A_RANGE      := 16#4200,  // Tensão fase A fora de faixa
    ALARM_MEAS_VOLTAGE_B_RANGE      := 16#4201,  // Tens  o fase B fora de faixa
    ALARM_MEAS_VOLTAGE_C_RANGE      := 16#4202,  // Tensão fase C fora de faixa
    ALARM_MEAS_CURRENT_A_RANGE      := 16#4203,  // Corrente fase A fora de faixa
    ALARM_MEAS_CURRENT_B_RANGE      := 16#4204,  // Corrente fase B fora de faixa
    ALARM_MEAS_CURRENT_C_RANGE      := 16#4205,  // Corrente fase C fora de faixa
    ALARM_MEAS_PT_RANGE             := 16#4206,  // Potência total fora de faixa
    ALARM_MEAS_PA_RANGE             := 16#4207,  // Potência fase A fora de faixa
    ALARM_MEAS_PB_RANGE             := 16#4208,  // Potência fase B fora de faixa
    ALARM_MEAS_PC_RANGE             := 16#4209,  // Potência fase C fora de faixa
    ALARM_MEAS_QT_RANGE             := 16#420A,  // Reativa total fora de faixa
    ALARM_MEAS_QA_RANGE             := 16#420B,  // Reativa fase A fora de faixa
    ALARM_MEAS_QB_RANGE             := 16#420C,  // Reativa fase B fora de faixa
    ALARM_MEAS_QC_RANGE             := 16#420D,  // Reativa fase C fora de faixa
    ALARM_MEAS_PFT_RANGE            := 16#420E,  // PF total fora de faixa
    ALARM_MEAS_PFA_RANGE            := 16#420F,  // PF fase A fora de faixa
    ALARM_MEAS_PFB_RANGE            := 16#4210,  // PF fase B fora de faixa
    ALARM_MEAS_PFC_RANGE            := 16#4211,  // PF fase C fora de faixa
    ALARM_MEAS_FROZEN               := 16#4212,  // Medição congelada (Pt sem variação)
    ALARM_MEAS_PT_XCHECK_FAIL       := 16#4213,  // Potência total fora de faixa
    ALARM_MEAS_PA_XCHECK_FAIL       := 16#4214,  // Potência fase A fora de faixa
    ALARM_MEAS_PB_XCHECK_FAIL       := 16#4215,  // Potência fase B fora de faixa
    ALARM_MEAS_PC_XCHECK_FAIL       := 16#4216,  // Potência fase C fora de faixa	
	ALARM_MEAS_PFT_XCHECK_FAIL      := 16#4217,  // PF total fora de faixa
	ALARM_Q_LIMITED_SURPASS			:= 16#4218,  // Deficit de Q superior a 20 % - necessário banco de capacitores
	ALARM_Q_LIMITED_REACHED			:= 16#4219,  // Q atingiu limite- pode ser necessário banco de capacitores
	ALARM_MEAS_USING_LAST_VALUE 	:= 16#4220,  // Usando última medição válida

    // ── Comunicação medidor ──
    ALARM_MEAS_MODBUS_ERROR      	:= 16#4221,  // Erro Modbus do medidor
    ALARM_MEAS_MODBUS_TIMEOUT       := 16#4222,  // Timeout leitura medidor
	
	// ── Ciclo ──
    ALARM_SCAN_OVERRUN              := 16#4250,  // Ciclo excedeu tolerância (1x)

    // ── Comunicação inversores ──
    ALARM_CH1_MODBUS_ERRO           := 16#4300,  // Canal COM1 >50% falhas
    ALARM_CH2_MODBUS_ERRO           := 16#4301,  // Canal COM2 >50% falhas
    ALARM_CH1_MODBUS_TIMEOUT        := 16#4302,  // Canal COM1 TIMEOUT < 3x
    ALARM_CH2_MODBUS_TIMEOUT        := 16#4303,  // Canal COM2 TIMEOUT < 3x

	
	// Erros gerados pelo Driver Modbus do Codesys
    ALARM_MB_ILLEGAL_FUNC         	:= 16#4A01,  // O dispositivo escravo não suporta o código de função
    ALARM_MB_ILLEGAL_ADDR         	:= 16#4A02,  // O dispositivo escravo não suporta este deslocamento de registro
    ALARM_MB_ILLEGAL_VALUE        	:= 16#4A03,  // O valor a ser gravado não é válido
    ALARM_MB_SLAVE_FAILURE        	:= 16#4A04,  // Erro irrecuperável ao executar a solicitação
    ALARM_MB_ACKNOWLEDGE          	:= 16#4A05,  // Notificação de um dispositivo escravo de que uma operação demorada foi iniciada 
    ALARM_MB_SLAVE_BUSY           	:= 16#4A06,  // Notificação de um dispositivo escravo de que uma operação demorada está em andamento
    ALARM_MB_MEMORY_PARITY        	:= 16#4A08,  // Erro específico para os códigos de função 20 e 21
    ALARM_MB_GW_PATH_UNAVAIL      	:= 16#4A0A,  // Erro específico ao usar dispositivos atrás de um gateway (Gateway mal configurado/ocupado)
    ALARM_MB_GW_DEVICE_FAIL       	:= 16#4A0B,  // Erro específico ao usar dispositivos atrás de um gateway (Dispositivo não responde)
    ALARM_MB_RESPONSE_TIMEOUT     	:= 16#4AA1,  // Não houve resposta a tempo - timeout
    ALARM_MB_RESPONSE_CRC         	:= 16#4AA2,  // O checksum da resposta está incorreto
    ALARM_MB_WRONG_SLAVE          	:= 16#4AA3,  // A resposta não é do dispositivo escravo esperado
    ALARM_MB_WRONG_FC             	:= 16#4AA4,  // A resposta não corresponde ao código de função esperado
    ALARM_MB_TCP_WARMOR           	:= 16#4AA5,  // Erro na porta TCP. A solicitação não foi enviada.
    ALARM_MB_INVALID_DATA         	:= 16#4AA6,  // A resposta contém dados inválidos.
    ALARM_MB_INVALID_PROTOCOL     	:= 16#4AA7,  // A resposta não está no protocolo Modbus.
    ALARM_MB_INVALID_HEADER       	:= 16#4AA8,  // Algum campo do cabeçalho Modbus MBAP (Protocolo, Comprimento) é inválido.
    ALARM_MB_INVALID_PARAM        	:= 16#4AA9,  // Algum parâmetro de entrada da operação é inválido 
    ALARM_MB_UNDEFINED            	:= 16#4AFF,  // O resultado da solicitação é indefinido ou ainda desconhecido, por exemplo, o estado inicial.
	ALARM_MB_APP_ABORTED          	:= 16#4AB1,
    ALARM_MB_APP_TIMEOUT          	:= 16#4AB2,

    // ══════════════════════════════════════════════════════════════
    // CRITICAL (0x8xxx) — ação de segurança (FAIL_SAFE ou STOP)
    // ══════════════════════════════════════════════════════════════

    // ── Startup ──
    CRIT_SERIAL_INIT_FAILED         := 16#8100,  // COM1/COM2 não inicializou
    CRIT_RTC_FAILED                 := 16#8101,  // Falha leitura RTC
    CRIT_INSTALLED_PWR_ZERO         := 16#8102,  // Potência instalada = 0
    CRIT_K1_TIMEOUT                 := 16#8103,  // K1 não respondeu (timeout)
    CRIT_K2_TIMEOUT                 := 16#8104,  // K1 não respondeu (timeout)
    CRIT_TC_POWER_NOT_SET           := 16#8105,  // TC_Power_kW não configurado

    // ── Medição 8103
    CRIT_MEAS_PERSISTENT_FAIL       := 16#8200,  // ex-16#C1 Medição com falha persistente (≥5 erros)
    CRIT_MEAS_COM_FAIL           	:= 16#8201,  // ex-16#C2 Erro/Timeout Modbus medidor → FAIL
	CRIT_MEAS_MODBUS_TIMEOUT		:= 16#8202,  // Timeout Modbus medidor → FAIL
	CRIT_MEAS_MODBUS_ERRO			:= 16#8203,  // Erro Modbus medidor → FAIL

    // ── Comunicação inversores ──
    CRIT_INV_CHANNEL_FAIL           := 16#8300,  // ex-16#C2 Canal COM com falha total → FAIL
    CRIT_CH1_MODBUS_TIMEOUT        	:= 16#8301,  // Canal COM1 TIMEOUT 3x
    CRIT_CH2_MODBUS_TIMEOUT        	:= 16#8302,  // Canal COM2 TIMEOUT 3x
	CRIT_CH1_MODBUS_ERRO	       	:= 16#8303,  // Canal COM1 >50% falhas
    CRIT_CH2_MODBUS_ERRO        	:= 16#8304,  // Canal COM2 >50% falhas

    // ── Controle ──
    CRIT_INSTALLED_POWER_ZERO       := 16#8400,  // InstalledPower = 0 em runtime → STOP
	CRIT_INSTALLED_SMAX_ZERO  		:= 16#8401,    // Error: Potência reativa instalada = 0

    // ── Scheduller ──
    CRIT_RTC_READ_FAIL              := 16#8500,  // RTC falhou durante operação
    CRIT_SCHEDULE_INDEX_INVALID     := 16#8501,  // Índice dia/hora inválido

    // ── Watchdog ──
    CRIT_SCAN_OVERRUN               := 16#8600,  // ex-16#F1 3× overruns consecutivos → FAIL

    // ── Proteção normativa ──
    CRIT_HARDLIMIT_15S             	:= 16#8700,  // ex-16#E1 P > LPI+10%Pnom por >15s → STOP
    CRIT_EXPORT_OVER_LPI_30S        := 16#8701,  // ex-16#E2 P > LPI por >30s → STOP
    CRIT_MEDIDOR_TIMEOUT_IN_FAIL    := 16#8702,  // ex-16#E3 30s sem medição válida em FAIL → STOP

    // ── STOP / Trip ──
    CRIT_STOP_ENTRY                 := 16#8800,  // Entrada no estado STOP
    CRIT_K2_DID_NOT_OPEN            := 16#8801,  // K2 não abriu após 2s → FaultLatch
    CRIT_STATE_CORRUPTION           := 16#8802   // MachineState inválido

) UINT;
END_TYPE
