{attribute 'qualified_only'}
// ════════════════════════════════════════════════════════════════════════════
// E_EventCode — Código unificado de eventos do PPC-GD
// Revisão: 2026-03 — reorganização estrutural e correção de inconsistências
// ════════════════════════════════════════════════════════════════════════════
//
// POLÍTICA DE SEVERIDADE POR FAIXA (bits superiores):
//
//   0x0000          = EVT_NONE — nenhum evento ativo
//   0x1xxx          = INFO     — registro operacional; sem ação de controle
//   0x2xxx          = WARNING  — desvio tolerável; sem ação de potência imediata
//   0x4xxx          = ALARM    — falha que requer atenção; pode degradar operação
//   0x8xxx          = CRITICAL — ação de segurança obrigatória: FAIL_SAFE ou STOP
//
//   INVARIANTE: para qualquer EVT, nibble superior define severidade sem exceção.
//   Nenhum código INFO deve aparecer fisicamente fora da seção 0x1xxx.
//
// MÓDULOS (2º nibble — x0xx a xAxx):
//
//   x0xx = Sistema / Geral
//   x1xx = Startup              (FB_Startup)
//   x2xx = Medição              (FB_ValidaDados, FB_ModBus — medidor)
//   x3xx = Comunicação inv.     (FB_WriteCom, FB_CheckInversores)
//   x4xx = Controle             (FB_Controle, FB_PowerController, FB_PIQ)
//   x5xx = Scheduler / Agenda   (FB_Scheduler)
//   x6xx = Máquina de Estados   (MainProgram)
//   x7xx = Proteção normativa   (timers 15 s / 30 s, hard-limit)
//   x8xx = STOP / Trip          (FB_TurnOff, FB_FailSafe)
//   x9xx = TURNOFF              (desligamento controlado)
//   xAxx = Driver Modbus        (códigos nativos Codesys mapeados)
//   xBxx = Reservado
//
// REGRAS PARA EXTENSÃO:
//   1. Nunca insira um código fora da faixa do seu nível de severidade.
//   2. Todo código novo deve ter comentário descritivo na mesma linha.
//   3. Gaps intencionais (ex: 16#4A07) devem ser documentados explicitamente.
//   4. Duplicatas semânticas são proibidas — verifique antes de adicionar.
// ════════════════════════════════════════════════════════════════════════════
TYPE E_EventCode :
(
    EVT_NONE                        := 16#0000,   // Nenhum evento ativo

    // ════════════════════════════════════════════════════════════════════════
    // INFO (0x1xxx) — registro operacional; sem ação de controle
    // ════════════════════════════════════════════════════════════════════════

    // ── 0x11xx : Startup (FB_Startup) / IHM ─────────────────────────────────
    INFO_STARTUP_BEGIN              := 16#1100,   // Sequência de inicialização iniciada
    INFO_SERIAL_COM_OK              := 16#1101,   // COM1 e COM2 inicializadas com sucesso
    INFO_RTC_OK                     := 16#1102,   // Relógio RTC lido com sucesso
    INFO_INVERTER_COUNT             := 16#1103,   // Contagem de inversores concluída
    INFO_INSTALLED_POWER            := 16#1104,   // Potência instalada calculada
    INFO_K1_CONFIRMED               := 16#1105,   // K1_in confirmado após debounce
    INFO_K2_CONFIRMED               := 16#1106,   // K2_in confirmado após debounce
    INFO_STARTUP_DONE               := 16#1107,   // Startup concluído → transição para OPERAÇÃO
    INFO_INV_CHECK_OK               := 16#1108,   // Todos os inversores configurados responderam
    INFO_RTC_SET_OK                	:= 16#1109,   // RTC corrigido pela IHM com sucesso

    // ── 0x12xx : Medição (FB_ValidaDados, FB_ModBus) ───────────────────────
    INFO_MEAS_READ_OK               := 16#1200,   // Leitura Modbus do medidor OK
    INFO_MEAS_DATA_VALID            := 16#1201,   // Dados validados e filtro aplicado
    INFO_MEAS_RECOVERING            := 16#1202,   // Contador nErrors em redução (recuperação)

    // ── 0x13xx : Comunicação inversores (FB_WriteCom) ──────────────────────
    INFO_CH1_WRITE_OK               := 16#1300,   // Escrita Modbus no canal COM1 OK
    INFO_CH2_WRITE_OK               := 16#1301,   // Escrita Modbus no canal COM2 OK

    // ── 0x15xx : Scheduler (FB_Scheduler) ──────────────────────────────────
    INFO_SPECIAL_DATE_ACTIVE        := 16#1500,   // Data especial ativa na agenda
    INFO_ZERO_GRID_MODE             := 16#1501,   // Modo Zero Grid ativo (exportação = 0)

    // ── 0x16xx : Máquina de Estados / Geral (MainProgram) ──────────────────
    INFO_CYCLE_COMPLETE             := 16#1600,   // Ciclo READ→CONTROL→WRITE→IDLE concluído OK
    INFO_FAIL_RECOVERY              := 16#1601,   // Recuperação automática do estado FAIL
    INFO_STATE_CHANGE               := 16#1610,   // Transição de MachineState registrada
    INFO_FAIL_RECOVERY_STARTED      := 16#1611,   // Condições de recuperação de FAIL detectadas
    INFO_FAIL_STATE_CHANGE          := 16#1612,   // Mudança de sub-estado interno em FAIL

    // ── 0x18xx : STOP / Reset ──────────────────────────────────────────────
    INFO_STOP_K2_OPEN_CONFIRMED     := 16#1800,   // K2 confirmado aberto durante STOP
    INFO_STOP_RESET_APPROVED        := 16#1801,   // Reset manual aprovado
    INFO_STOP_RESET_WAITING         := 16#1802,   // Aguardando Pt estável para autorizar reset

    // ── 0x19xx : TURNOFF — Desligamento controlado ─────────────────────────
    INFO_TURNOFF_ENTRY              := 16#1900,   // Entrada no estado TURNOFF
    INFO_TURNOFF_ZERO_SENT          := 16#1901,   // Setpoints zero enviados com sucesso
    INFO_TURNOFF_EXPORT_CONFIRMED   := 16#1902,   // Geração confirmada próxima de zero
    INFO_TURNOFF_K1_DISABLED        := 16#1903,   // K1 desativado
    INFO_TURNOFF_K2_TRIPPED         := 16#1904,   // K2 acionado (trip controlado)
    INFO_TURNOFF_K2_CONFIRMED       := 16#1905,   // K2: abertura confirmada por contato auxiliar
    INFO_TURNOFF_DONE               := 16#1906,   // Desligamento controlado concluído

    // ════════════════════════════════════════════════════════════════════════
    // WARNING (0x2xxx) — desvio tolerável; sem ação de potência imediata
    // ════════════════════════════════════════════════════════════════════════

    // ── 0x21xx : Startup ───────────────────────────────────────────────────
    WARN_NO_INVERSORES_COM02        := 16#2101,   // COM2 sem inversores detectados (pode ser intencional)
    WARN_INV_CHECK_PARTIAL          := 16#2102,   // Inversor(es) ausentes, mas acima do limiar mínimo
    WARN_RTC_SET_INVALID_INPUT     	:= 16#2103,   // Tentativa de set RTC com campo inválido (IHM)
    WARN_RTC_SET_HW_FAIL           	:= 16#2104,   // SysTimeRtcSet() retornou erro de hardware	

    // ── 0x22xx : Medição ───────────────────────────────────────────────────
    // NOTA: WARN = 1º erro de medição isolado (1–4 ocorrências);
    //       ALARM_MEAS_USING_LAST_VALUE (0x4220) = limiar superior atingido.
    //       A distinção entre WARN e ALARM é definida pelo contador nErrors em FB_ValidaDados.
    WARN_MEAS_USING_LAST_VALID      := 16#2200,   // Usando última medição válida (erro isolado, nErrors < limiar)
    WARN_MEAS_CROSS_CHECK_PA        := 16#2201,   // Validação cruzada: Pa inconsistente
    WARN_MEAS_CROSS_CHECK_PB        := 16#2202,   // Validação cruzada: Pb inconsistente
    WARN_MEAS_CROSS_CHECK_PC        := 16#2203,   // Validação cruzada: Pc inconsistente
    WARN_MEAS_CROSS_CHECK_PT_SUM    := 16#2204,   // Validação cruzada: Pt ≠ Pa+Pb+Pc
    WARN_MEAS_CROSS_CHECK_PF        := 16#2205,   // Validação cruzada: PFt inconsistente com P/S
    WARN_MEAS_ERROR_ISOLATED        := 16#2206,   // Erro de medição isolado (nErrors entre 1 e limiar-1)

    // ── 0x23xx : Comunicação inversores ────────────────────────────────────
    WARN_WRITE_INV_ERROR            := 16#2300,   // Erro de escrita em inversor individual
    WARN_WRITE_INV_TIMEOUT          := 16#2301,   // Timeout de escrita em inversor individual

    // ── 0x24xx : Controle ──────────────────────────────────────────────────
    WARN_P_ALLOC_SATURATED          := 16#2400,   // P alocado < P comandado (saturação de alocação)
    WARN_Q_LIMITED_BY_SMAX          := 16#2401,   // Q limitado por Smax dos inversores
    WARN_PF_BELOW_TARGET            := 16#2402,   // FP < 0,92, mas não por limite de S
    WARN_PF_NOT_ACHIEVABLE          := 16#2403,   // FP impossível de atingir (provável banco de capacitores)
    WARN_PI_P_SATURATED             := 16#2404,   // Integrador PI de P saturado (anti-windup ativo)
    WARN_PI_Q_SATURATED             := 16#2405,   // Integrador PI de Q saturado (anti-windup ativo)
    WARN_PHASE_LIMITED              := 16#2406,   // Potência limitada por fase individual

    // ── 0x28xx : STOP / Reset ──────────────────────────────────────────────
    WARN_STOP_RESET_DENIED          := 16#2800,   // Reset manual negado (condições não satisfeitas)

    // ── 0x29xx : TURNOFF ───────────────────────────────────────────────────
    WARN_TURNOFF_WRITE_RETRY        := 16#2900,   // Tentativa de escrita de setpoint zero falhou (retry)

    // ════════════════════════════════════════════════════════════════════════
    // ALARM (0x4xxx) — falha que requer atenção; pode degradar operação
    // ════════════════════════════════════════════════════════════════════════

    // ── 0x42xx : Medição — Faixa de range ──────────────────────────────────
    ALARM_MEAS_VOLTAGE_A_RANGE      := 16#4200,   // Tensão fase A fora de faixa operacional
    ALARM_MEAS_VOLTAGE_B_RANGE      := 16#4201,   // Tensão fase B fora de faixa operacional
    ALARM_MEAS_VOLTAGE_C_RANGE      := 16#4202,   // Tensão fase C fora de faixa operacional
    ALARM_MEAS_CURRENT_A_RANGE      := 16#4203,   // Corrente fase A fora de faixa operacional
    ALARM_MEAS_CURRENT_B_RANGE      := 16#4204,   // Corrente fase B fora de faixa operacional
    ALARM_MEAS_CURRENT_C_RANGE      := 16#4205,   // Corrente fase C fora de faixa operacional
    ALARM_MEAS_PT_RANGE             := 16#4206,   // Potência ativa total fora de faixa
    ALARM_MEAS_PA_RANGE             := 16#4207,   // Potência ativa fase A fora de faixa
    ALARM_MEAS_PB_RANGE             := 16#4208,   // Potência ativa fase B fora de faixa
    ALARM_MEAS_PC_RANGE             := 16#4209,   // Potência ativa fase C fora de faixa
    ALARM_MEAS_QT_RANGE             := 16#420A,   // Potência reativa total fora de faixa
    ALARM_MEAS_QA_RANGE             := 16#420B,   // Potência reativa fase A fora de faixa
    ALARM_MEAS_QB_RANGE             := 16#420C,   // Potência reativa fase B fora de faixa
    ALARM_MEAS_QC_RANGE             := 16#420D,   // Potência reativa fase C fora de faixa
    ALARM_MEAS_PFT_RANGE            := 16#420E,   // Fator de potência total fora de faixa
    ALARM_MEAS_PFA_RANGE            := 16#420F,   // Fator de potência fase A fora de faixa
    ALARM_MEAS_PFB_RANGE            := 16#4210,   // Fator de potência fase B fora de faixa
    ALARM_MEAS_PFC_RANGE            := 16#4211,   // Fator de potência fase C fora de faixa
    ALARM_MEAS_FROZEN               := 16#4212,   // Medição congelada: Pt sem variação por N ciclos

    // ── 0x42xx : Medição — Validação cruzada ───────────────────────────────
    ALARM_MEAS_PT_XCHECK_FAIL       := 16#4213,   // Validação cruzada: Pt inconsistente
    ALARM_MEAS_PA_XCHECK_FAIL       := 16#4214,   // Validação cruzada: Pa inconsistente (limiar de alarme)
    ALARM_MEAS_PB_XCHECK_FAIL       := 16#4215,   // Validação cruzada: Pb inconsistente (limiar de alarme)
    ALARM_MEAS_PC_XCHECK_FAIL       := 16#4216,   // Validação cruzada: Pc inconsistente (limiar de alarme)
    ALARM_MEAS_PFT_XCHECK_FAIL      := 16#4217,   // Validação cruzada: PFt inconsistente (limiar de alarme)

    // ── 0x42xx : Medição — Dados degradados ────────────────────────────────
    // NOTA: Distinção em relação a WARN_MEAS_USING_LAST_VALID (0x2200):
    //       Este alarme é disparado quando nErrors atinge o limiar de degradação
    //       (ex: 5+ erros consecutivos), mas antes do CRITICAL de falha persistente.
    ALARM_MEAS_USING_LAST_VALUE     := 16#4220,   // Usando última medição válida: nErrors ≥ limiar de alarme
    ALARM_MEAS_MODBUS_ERROR         := 16#4221,   // Erro Modbus do medidor (não crítico ainda)
    ALARM_MEAS_MODBUS_TIMEOUT       := 16#4222,   // Timeout Modbus do medidor (não crítico ainda)

    // ── 0x42xx : Controle — Reativa ────────────────────────────────────────
    ALARM_Q_LIMITED_REACHED         := 16#4230,   // Q atingiu limite de S dos inversores
    ALARM_Q_LIMITED_SURPASS         := 16#4231,   // Déficit de Q > 20% — provável necessidade de banco de capacitores

    // ── 0x42xx : Ciclo / Tempo real ────────────────────────────────────────
    ALARM_SCAN_OVERRUN              := 16#4250,   // Ciclo excedeu tolerância (ocorrência isolada)

    // ── 0x43xx : Comunicação inversores ────────────────────────────────────
    ALARM_CH1_MODBUS_ERRO           := 16#4300,   // Canal COM1: taxa de falhas > 50%
    ALARM_CH2_MODBUS_ERRO           := 16#4301,   // Canal COM2: taxa de falhas > 50%
    ALARM_CH1_MODBUS_TIMEOUT        := 16#4302,   // Canal COM1: timeout < 3 ocorrências consecutivas
    ALARM_CH2_MODBUS_TIMEOUT        := 16#4303,   // Canal COM2: timeout < 3 ocorrências consecutivas

    // ── 0x4Axx : Driver Modbus Codesys — exceções do protocolo ────────────
    // Mapeamento direto dos códigos de exceção Modbus padrão (RFC/especificação)
    // e dos códigos internos do driver Codesys. Gaps documentados abaixo.
    ALARM_MB_ILLEGAL_FUNC           := 16#4A01,   // Código de função não suportado pelo escravo
    ALARM_MB_ILLEGAL_ADDR           := 16#4A02,   // Endereço de registrador não suportado pelo escravo
    ALARM_MB_ILLEGAL_VALUE          := 16#4A03,   // Valor a gravar inválido para o escravo
    ALARM_MB_SLAVE_FAILURE          := 16#4A04,   // Falha irrecuperável no escravo ao executar a solicitação
    ALARM_MB_ACKNOWLEDGE            := 16#4A05,   // Escravo aceitou operação longa: aguardando conclusão
    ALARM_MB_SLAVE_BUSY             := 16#4A06,   // Escravo ocupado com operação longa em andamento
    // 16#4A07 — não existe no padrão Modbus; gap intencional
    ALARM_MB_MEMORY_PARITY          := 16#4A08,   // Erro de paridade de memória (apenas FC 20/21)
    // 16#4A09 — não existe no padrão Modbus; gap intencional
    ALARM_MB_GW_PATH_UNAVAIL        := 16#4A0A,   // Gateway: caminho indisponível (mal configurado ou ocupado)
    ALARM_MB_GW_DEVICE_FAIL         := 16#4A0B,   // Gateway: dispositivo de destino não responde

    // Códigos internos do driver Modbus Codesys (0x4AA0–0x4AFF)
    ALARM_MB_RESPONSE_TIMEOUT       := 16#4AA1,   // Sem resposta dentro do tempo configurado (timeout)
    ALARM_MB_RESPONSE_CRC           := 16#4AA2,   // CRC da resposta incorreto
    ALARM_MB_WRONG_SLAVE            := 16#4AA3,   // Resposta não veio do escravo esperado
    ALARM_MB_WRONG_FC               := 16#4AA4,   // Código de função da resposta não corresponde à solicitação
    ALARM_MB_TCP_ERROR              := 16#4AA5,   // Erro na porta TCP; solicitação não enviada
    ALARM_MB_INVALID_DATA           := 16#4AA6,   // Resposta contém dados inválidos
    ALARM_MB_INVALID_PROTOCOL       := 16#4AA7,   // Resposta não está no protocolo Modbus
    ALARM_MB_INVALID_HEADER         := 16#4AA8,   // Campo do cabeçalho MBAP inválido (Protocolo ou Comprimento)
    ALARM_MB_INVALID_PARAM          := 16#4AA9,   // Parâmetro de entrada da operação inválido
    ALARM_MB_APP_ABORTED            := 16#4AB1,   // Operação abortada pela aplicação
    ALARM_MB_APP_TIMEOUT            := 16#4AB2,   // Timeout gerado pela aplicação (acima do driver)
    ALARM_MB_UNDEFINED              := 16#4AFF,   // Resultado indefinido ou estado inicial do driver

    // ════════════════════════════════════════════════════════════════════════
    // CRITICAL (0x8xxx) — ação de segurança obrigatória: FAIL_SAFE ou STOP
    // ════════════════════════════════════════════════════════════════════════

    // ── 0x81xx : Startup (FB_Startup) ──────────────────────────────────────
    CRIT_SERIAL_INIT_FAILED         := 16#8100,   // COM1 ou COM2 não inicializou → FAIL
    CRIT_RTC_FAILED                 := 16#8101,   // Falha na leitura do RTC → FAIL
    CRIT_INSTALLED_PWR_ZERO         := 16#8102,   // Potência instalada calculada = 0 → FAIL
    CRIT_K1_TIMEOUT                 := 16#8103,   // K1 não respondeu dentro do timeout → FAIL
    CRIT_K2_TIMEOUT                 := 16#8104,   // K2 não respondeu dentro do timeout → FAIL
    CRIT_TC_POWER_NOT_SET           := 16#8105,   // TC_Power_kW não configurado → FAIL
    CRIT_MEAS_INIC_ERRO_TIMEOUT     := 16#8106,   // Erro ou timeout no teste de comunicação do medidor na inicialização
    CRIT_MEAS_INIC_FAIL             := 16#8107,   // Falha no teste de comunicação do medidor: sem resposta conclusiva
    CRIT_INV_CHECK_BELOW_THRESHOLD  := 16#8108,   // Inversores respondentes < limiar mínimo no startup → FAIL

    // ── 0x82xx : Medição (FB_ValidaDados, FB_ModBus) ───────────────────────
    CRIT_MEAS_PERSISTENT_FAIL       := 16#8200,   // ex-16#C1 — Falha de medição persistente (≥ N erros consecutivos)
    CRIT_MEAS_COM_FAIL              := 16#8201,   // ex-16#C2 — Perda de comunicação com medidor → FAIL
    CRIT_MEAS_MODBUS_TIMEOUT        := 16#8202,   // Timeout Modbus do medidor atingiu limiar crítico → FAIL
    CRIT_MEAS_MODBUS_ERRO           := 16#8203,   // Erro Modbus do medidor atingiu limiar crítico → FAIL

    // ── 0x83xx : Comunicação inversores (FB_WriteCom) ──────────────────────
    CRIT_INV_CHANNEL_FAIL           := 16#8300,   // ex-16#C2 — Canal COM com falha total → FAIL
    CRIT_CH1_MODBUS_TIMEOUT         := 16#8301,   // Canal COM1: ≥ 3 timeouts consecutivos → FAIL
    CRIT_CH2_MODBUS_TIMEOUT         := 16#8302,   // Canal COM2: ≥ 3 timeouts consecutivos → FAIL
    CRIT_CH1_MODBUS_ERRO            := 16#8303,   // Canal COM1: taxa de falhas > limiar crítico → FAIL
    CRIT_CH2_MODBUS_ERRO            := 16#8304,   // Canal COM2: taxa de falhas > limiar crítico → FAIL

    // ── 0x84xx : Controle (FB_Controle, FB_PowerController) ────────────────
    CRIT_INSTALLED_POWER_ZERO       := 16#8400,   // InstalledPower = 0 detectado em runtime → STOP
    CRIT_INSTALLED_SMAX_ZERO        := 16#8401,   // Smax instalado = 0 detectado em runtime → STOP

    // ── 0x85xx : Scheduler (FB_Scheduler) ──────────────────────────────────
    CRIT_RTC_READ_FAIL              := 16#8500,   // RTC falhou durante operação normal → FAIL
    CRIT_SCHEDULE_INDEX_INVALID     := 16#8501,   // Índice de dia ou hora inválido detectado em runtime

    // ── 0x86xx : Watchdog / Tempo real ─────────────────────────────────────
    CRIT_SCAN_OVERRUN               := 16#8600,   // 3 overruns consecutivos de ciclo → FAIL
    CRIT_FAIL_WRITE_ZERO_FAILED     := 16#8601,   // Escrita de setpoint zero falhou durante FAIL
    CRIT_FAIL_WRITE_EXHAUSTED       := 16#8602,   // Esgotadas todas as tentativas de escrita zero → STOP
    CRIT_FAIL_GLOBAL_TIMEOUT        := 16#8603,   // Timeout global de permanência em FAIL → STOP

    // ── 0x87xx : Proteção normativa ────────────────────────────────────────
    CRIT_HARDLIMIT_15S              := 16#8700,   // P > LPI + 10% Pnom por > 15 s → STOP imediato
    CRIT_EXPORT_OVER_LPI_30S        := 16#8701,   // P > LPI por > 30 s → STOP
    CRIT_MEAS_TIMEOUT_IN_FAIL       := 16#8702,   // 5 s sem medição válida durante FAIL → STOP

    // ── 0x88xx : STOP / Trip / Integridade (FB_FailSafe, MainProgram) ──────
    CRIT_STOP_ENTRY                 := 16#8800,   // Entrada no estado STOP registrada
    CRIT_K2_NOT_OPENED              := 16#8801,   // K2 não abriu após 2 s → FaultLatch
    CRIT_STATE_CORRUPTION           := 16#8802,   // MachineState com valor inválido detectado
    CRIT_FAIL_ENTRY                 := 16#8803,   // Entrada no estado FAIL registrada

    // ── 0x89xx : TURNOFF — Desligamento controlado (FB_TurnOff) ───────────
    CRIT_TURNOFF_WRITE_EXHAUSTED    := 16#8900,   // Esgotadas tentativas de escrita de setpoint → STOP
    CRIT_TURNOFF_VERIFY_TIMEOUT     := 16#8901,   // Timeout na verificação de geração próxima de zero → STOP
    CRIT_TURNOFF_K2_NOT_OPENED      := 16#8902,   // K2 não abriu após trip controlado → FaultLatch
    CRIT_TURNOFF_K1_NOT_OPENED      := 16#8903    // K1 não abriu após comando de desligamento

) UINT;
END_TYPE
