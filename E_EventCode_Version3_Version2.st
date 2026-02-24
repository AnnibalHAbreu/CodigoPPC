{attribute 'qualified_only'}
{attribute 'strict'}
// ════════════════════════════════════════════════════════════════════
// E_EventCode — Código unificado de eventos do PPC-GD
// Compatível com Alarm Manager (flags BOOL em GVL_Alarm) e comissionamento.
// ════════════════════════════════════════════════════════════════════
//
// FAIXAS (nibble alto define severidade):
//   0x0000 = NONE
//   0x1xxx = INFO     (registro operacional / transições)
//   0x2xxx = WARNING  (desvios toleráveis, sem ação de potência)
//   0x4xxx = ALARM    (falhas que requerem atenção / podem degradar)
//   0x8xxx = CRITICAL (ação de segurança: FAIL_SAFE ou STOP)
//
// 2º nibble = módulo:
//   x0xx = Sistema/Geral
//   x1xx = Startup
//   x2xx = Medição (medidor + validação)
//   x3xx = Comunicação inversores
//   x4xx = Controle (P/Q/PF)
//   x5xx = Scheduler/Agenda
//   x6xx = Máquina de Estados (MainProgram)
//   x7xx = Proteções normativas
//   x8xx = STOP/Trip
//   x9xx = Reservado
//
// Observação: códigos legados (ex-16#C1/C2/E1/E2/E3/F1) são referenciados
// por comentário e mapeados semanticamente, sem manter o mesmo valor numérico,
// para preservar a coerência de severidade por faixa.
// ════════════════════════════════════════════════════════════════════
TYPE E_EventCode :
(
    EVT_NONE                        := 16#0000,

    // =============================================================
    // INFO (0x1xxx)
    // =============================================================
    // ── Startup (0x11xx)
    INFO_STARTUP_BEGIN              := 16#1100,
    INFO_SERIAL_COM_OK              := 16#1101,
    INFO_RTC_OK                     := 16#1102,
    INFO_INVERTER_COUNT             := 16#1103,
    INFO_INSTALLED_POWER            := 16#1104,
    INFO_K1_CONFIRMED               := 16#1105,
    INFO_K2_CONFIRMED               := 16#1106,
    INFO_STARTUP_DONE               := 16#1107,

    // ── Medição / Operação (0x12xx)
    INFO_MEDIDOR_READ_OK            := 16#1200,
    INFO_MEDIDOR_DATA_VALID         := 16#1201,
    INFO_MEAS_RECOVERING            := 16#1202,  // contador nErrors reduzindo (opcional)

    // ── Escrita inversores (0x13xx)
    INFO_WRITE_INV_OK               := 16#1300,

    // ── Scheduler (0x15xx)
    INFO_SPECIAL_DATE_ACTIVE        := 16#1500,
    INFO_ZERO_GRID_MODE             := 16#1501,

    // ── Máquina de estados (0x16xx)
    INFO_STATE_CHANGE               := 16#1610,
    INFO_CYCLE_COMPLETE             := 16#1600,
    INFO_FAIL_RECOVERY              := 16#1601,

    // ── STOP/Reset (0x18xx)
    INFO_STOP_K2_OPEN_CONFIRMED     := 16#1800,
    INFO_STOP_RESET_APPROVED        := 16#1801,
    INFO_STOP_RESET_WAITING         := 16#1802,

    // =============================================================
    // WARNING (0x2xxx)
    // =============================================================
    // ── Startup
    WARN_TC_POWER_NOT_SET           := 16#2100,
    WARN_NO_INVERSORES_COM02        := 16#2101,

    // ── Medição
    WARN_MEAS_USING_LAST_VALID      := 16#2200,
    WARN_MEAS_ERROR_ISOLATED        := 16#2206,
    WARN_MEAS_CROSS_CHECK_PA        := 16#2201,
    WARN_MEAS_CROSS_CHECK_PB        := 16#2202,
    WARN_MEAS_CROSS_CHECK_PC        := 16#2203,
    WARN_MEAS_CROSS_CHECK_PT_SUM    := 16#2204,
    WARN_MEAS_CROSS_CHECK_PF        := 16#2205,

    // ── Comunicação inversores
    WARN_WRITE_INV_ERROR            := 16#2300,
    WARN_WRITE_INV_TIMEOUT          := 16#2301,

    // ── Controle
    WARN_P_ALLOC_SATURATED          := 16#2400,
    WARN_Q_LIMITED_BY_SMAX          := 16#2401,
    WARN_PF_BELOW_TARGET            := 16#2402,
    WARN_PF_NOT_ACHIEVABLE          := 16#2403,
    WARN_PI_P_SATURATED             := 16#2404,
    WARN_PI_Q_SATURATED             := 16#2405,
    WARN_PHASE_LIMITED              := 16#2406,

    // ── Ciclo / watchdog
    WARN_SCAN_OVERRUN               := 16#2600,

    // ── STOP/reset
    WARN_STOP_RESET_DENIED          := 16#2800,

    // =============================================================
    // ALARM (0x4xxx)
    // =============================================================
    // ── Medição — Range/Freeze
    ALARM_MEAS_VOLTAGE_A_RANGE      := 16#4200,
    ALARM_MEAS_VOLTAGE_B_RANGE      := 16#4201,
    ALARM_MEAS_VOLTAGE_C_RANGE      := 16#4202,
    ALARM_MEAS_CURRENT_A_RANGE      := 16#4203,
    ALARM_MEAS_CURRENT_B_RANGE      := 16#4204,
    ALARM_MEAS_CURRENT_C_RANGE      := 16#4205,
    ALARM_MEAS_PT_RANGE             := 16#4206,
    ALARM_MEAS_PA_RANGE             := 16#4207,
    ALARM_MEAS_PB_RANGE             := 16#4208,
    ALARM_MEAS_PC_RANGE             := 16#4209,
    ALARM_MEAS_QT_RANGE             := 16#420A,
    ALARM_MEAS_QA_RANGE             := 16#420B,
    ALARM_MEAS_QB_RANGE             := 16#420C,
    ALARM_MEAS_QC_RANGE             := 16#420D,
    ALARM_MEAS_PFT_RANGE            := 16#420E,
    ALARM_MEAS_PFA_RANGE            := 16#420F,
    ALARM_MEAS_PFB_RANGE            := 16#4210,
    ALARM_MEAS_PFC_RANGE            := 16#4211,
    ALARM_MEAS_FROZEN               := 16#4212,

    // ── Comunicação medidor
    ALARM_MEDIDOR_MODBUS_ERROR      := 16#4220,
    ALARM_MEDIDOR_TIMEOUT           := 16#4221,

    // ── Comunicação inversores (canal degradado)
    ALARM_COM_CH1_DEGRADED          := 16#4300,
    ALARM_COM_CH2_DEGRADED          := 16#4301,

    // =============================================================
    // CRITICAL (0x8xxx)
    // =============================================================
    // ── Startup
    CRIT_SERIAL_INIT_FAILED         := 16#8100,
    CRIT_RTC_FAILED                 := 16#8101,
    CRIT_NO_INSTALLED_POWER         := 16#8102,
    CRIT_K1_TIMEOUT                 := 16#8103,

    // ── Medição
    CRIT_MEAS_PERSISTENT_FAIL       := 16#8200,  // ex-16#C1 (medição falha persistente)
    CRIT_MEDIDOR_COM_FAIL           := 16#8201,  // ex-16#C2 (erro/timeout Modbus medidor)

    // ── Comunicação inversores
    CRIT_COM_CHANNEL_FAIL           := 16#8300,  // ex-16#C2 (falha canal inversores >50%)

    // ── Controle
    CRIT_INSTALLED_POWER_ZERO       := 16#8400,

    // ── Scheduler
    CRIT_RTC_READ_FAIL              := 16#8500,
    CRIT_SCHEDULE_INDEX_INVALID     := 16#8501,

    // ── Watchdog
    CRIT_SCAN_WATCHDOG              := 16#8600,  // ex-16#F1

    // ── Proteções normativas
    CRIT_HARD_LIMIT_15S             := 16#8700,  // ex-16#E1
    CRIT_EXPORT_OVER_LPI_30S        := 16#8701,  // ex-16#E2
    CRIT_MEDIDOR_TIMEOUT_IN_FAIL    := 16#8702,  // ex-16#E3

    // ── STOP / Trip
    CRIT_STOP_ENTRY                 := 16#8800,
    CRIT_K2_DID_NOT_OPEN            := 16#8801,  // corrige bug (não reutiliza ex-E2)
    CRIT_STATE_CORRUPTION           := 16#8802

) UINT;
END_TYPE