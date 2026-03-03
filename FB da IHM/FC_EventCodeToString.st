// ════════════════════════════════════════════════════════════════════
// FC_EventCodeToString — Mensagem legível para E_EventCode (PPC-GD)
// ════════════════════════════════════════════════════════════════════
// Uso: s := FC_EventCodeToString(E_EventCode.CRIT_HARD_LIMIT_15S);
// ════════════════════════════════════════════════════════════════════
FUNCTION FC_EventCodeToString : STRING(80)
VAR_INPUT
    eCode : E_EventCode;
END_VAR

    CASE eCode OF
        // =============================================================
        // NONE
        // =============================================================
        E_EventCode.EVT_NONE:
            FC_EventCodeToString := '';
    
        // =============================================================
        // INFO (0x1xxx)
        // =============================================================
        // Startup (0x11xx)
        E_EventCode.INFO_STARTUP_BEGIN:
            FC_EventCodeToString := 'Startup: inicio';
        E_EventCode.INFO_SERIAL_COM_OK:
            FC_EventCodeToString := 'Startup: comunicacao serial OK';
        E_EventCode.INFO_RTC_OK:
            FC_EventCodeToString := 'Startup: RTC OK';
        E_EventCode.INFO_INVERTER_COUNT:
            FC_EventCodeToString := 'Startup: quantidade de inversores detectada';
        E_EventCode.INFO_INSTALLED_POWER:
            FC_EventCodeToString := 'Startup: potencia instalada OK';
        E_EventCode.INFO_K1_CONFIRMED:
            FC_EventCodeToString := 'Startup: K1 confirmado';
        E_EventCode.INFO_K2_CONFIRMED:
            FC_EventCodeToString := 'Startup: K2 confirmado';
        E_EventCode.INFO_STARTUP_DONE:
            FC_EventCodeToString := 'Startup: concluido';
    
        // Medição / Operação (0x12xx)
        E_EventCode.INFO_MEAS_READ_OK:
            FC_EventCodeToString := 'Medidor: leitura OK';
        E_EventCode.INFO_MEAS_DATA_VALID:
            FC_EventCodeToString := 'Medidor: dados validos';
        E_EventCode.INFO_MEAS_RECOVERING:
            FC_EventCodeToString := 'Medicao: recuperando (erros reduzindo)';
    
        // Escrita inversores (0x13xx)
        E_EventCode.INFO_CH1_WRITE_OK:               
    	    FC_EventCodeToString := ' Escrita no canal 01 OK';
    	E_EventCode.INFO_CH2_WRITE_OK:               
    	    FC_EventCodeToString := ' Escrita no canal 01 OK';
    		
        // Scheduler (0x15xx)
        E_EventCode.INFO_SPECIAL_DATE_ACTIVE:
            FC_EventCodeToString := 'Scheduler: data especial ativa';
        E_EventCode.INFO_ZERO_GRID_MODE:
            FC_EventCodeToString := 'Scheduler: modo zero grid ativo';
    
        // Máquina de estados (0x16xx)
        E_EventCode.INFO_CYCLE_COMPLETE:
            FC_EventCodeToString := 'Ciclo: completo';
        E_EventCode.INFO_FAIL_RECOVERY:
            FC_EventCodeToString := 'FAIL: recuperacao automatica';
        E_EventCode.INFO_STATE_CHANGE:
            FC_EventCodeToString := 'Maquina de estados: mudanca de estado';
    
        // STOP/Reset (0x18xx)
        E_EventCode.INFO_STOP_K2_OPEN_CONFIRMED:
            FC_EventCodeToString := 'STOP: K2 aberto confirmado';
        E_EventCode.INFO_STOP_RESET_APPROVED:
            FC_EventCodeToString := 'STOP: reset aprovado';
        E_EventCode.INFO_STOP_RESET_WAITING:
            FC_EventCodeToString := 'STOP: aguardando reset';
    
        // =============================================================
        // WARNING (0x2xxx)
        // =============================================================
        // Startup
        E_EventCode.CRIT_TC_POWER_NOT_SET:
            FC_EventCodeToString := 'Startup: TC Power nao configurado';
        E_EventCode.WARN_NO_INVERSORES_COM02:
            FC_EventCodeToString := 'Startup: nenhum inversor no COM2';
    
        // Medição
        E_EventCode.WARN_MEAS_USING_LAST_VALID:
            FC_EventCodeToString := 'Medicao: usando ultimo valor valido';
        E_EventCode.WARN_MEAS_CROSS_CHECK_PA:
            FC_EventCodeToString := 'Medicao: cross-check Pa falhou';
        E_EventCode.WARN_MEAS_CROSS_CHECK_PB:
            FC_EventCodeToString := 'Medicao: cross-check Pb falhou';
        E_EventCode.WARN_MEAS_CROSS_CHECK_PC:
            FC_EventCodeToString := 'Medicao: cross-check Pc falhou';
        E_EventCode.WARN_MEAS_CROSS_CHECK_PT_SUM:
            FC_EventCodeToString := 'Medicao: cross-check Pt != Pa+Pb+Pc';
        E_EventCode.WARN_MEAS_CROSS_CHECK_PF:
            FC_EventCodeToString := 'Medicao: cross-check PF falhou';
        E_EventCode.WARN_MEAS_ERROR_ISOLATED:
            FC_EventCodeToString := 'Medicao: erro isolado (toleravel)';
    
        // Comunicação inversores
        E_EventCode.WARN_WRITE_INV_ERROR:
            FC_EventCodeToString := 'Inversores: erro de escrita';
        E_EventCode.WARN_WRITE_INV_TIMEOUT:
            FC_EventCodeToString := 'Inversores: timeout de escrita';
    
        // Controle
        E_EventCode.WARN_P_ALLOC_SATURATED:
            FC_EventCodeToString := 'Controle: alocacao de P saturada';
        E_EventCode.WARN_Q_LIMITED_BY_SMAX:
            FC_EventCodeToString := 'Controle: Q limitado por Smax';
        E_EventCode.WARN_PF_BELOW_TARGET:
            FC_EventCodeToString := 'Controle: PF abaixo do alvo';
        E_EventCode.WARN_PF_NOT_ACHIEVABLE:
            FC_EventCodeToString := 'Controle: PF nao atingivel';
        E_EventCode.WARN_PI_P_SATURATED:
            FC_EventCodeToString := 'Controle: PI de P saturado';
        E_EventCode.WARN_PI_Q_SATURATED:
            FC_EventCodeToString := 'Controle: PI de Q saturado';
        E_EventCode.WARN_PHASE_LIMITED:
            FC_EventCodeToString := 'Controle: limitado por fase';
    
        // STOP/reset
        E_EventCode.WARN_STOP_RESET_DENIED:
            FC_EventCodeToString := 'STOP: reset negado';
    
        // =============================================================
        // ALARM (0x4xxx)
        // =============================================================
        // Medição — Range/Freeze
        E_EventCode.ALARM_MEAS_VOLTAGE_A_RANGE:
            FC_EventCodeToString := 'Medicao: tensao fase A fora de faixa';
        E_EventCode.ALARM_MEAS_VOLTAGE_B_RANGE:
            FC_EventCodeToString := 'Medicao: tensao fase B fora de faixa';
        E_EventCode.ALARM_MEAS_VOLTAGE_C_RANGE:
            FC_EventCodeToString := 'Medicao: tensao fase C fora de faixa';
        E_EventCode.ALARM_MEAS_CURRENT_A_RANGE:
            FC_EventCodeToString := 'Medicao: corrente fase A fora de faixa';
        E_EventCode.ALARM_MEAS_CURRENT_B_RANGE:
            FC_EventCodeToString := 'Medicao: corrente fase B fora de faixa';
        E_EventCode.ALARM_MEAS_CURRENT_C_RANGE:
            FC_EventCodeToString := 'Medicao: corrente fase C fora de faixa';
        E_EventCode.ALARM_MEAS_PT_RANGE:
            FC_EventCodeToString := 'Medicao: Pt fora de faixa';
        E_EventCode.ALARM_MEAS_PA_RANGE:
            FC_EventCodeToString := 'Medicao: Pa fora de faixa';
        E_EventCode.ALARM_MEAS_PB_RANGE:
            FC_EventCodeToString := 'Medicao: Pb fora de faixa';
        E_EventCode.ALARM_MEAS_PC_RANGE:
            FC_EventCodeToString := 'Medicao: Pc fora de faixa';
        E_EventCode.ALARM_MEAS_QT_RANGE:
            FC_EventCodeToString := 'Medicao: Qt fora de faixa';
        E_EventCode.ALARM_MEAS_QA_RANGE:
            FC_EventCodeToString := 'Medicao: Qa fora de faixa';
        E_EventCode.ALARM_MEAS_QB_RANGE:
            FC_EventCodeToString := 'Medicao: Qb fora de faixa';
        E_EventCode.ALARM_MEAS_QC_RANGE:
            FC_EventCodeToString := 'Medicao: Qc fora de faixa';
        E_EventCode.ALARM_MEAS_PFT_RANGE:
            FC_EventCodeToString := 'Medicao: PFt fora de faixa';
        E_EventCode.ALARM_MEAS_PFA_RANGE:
            FC_EventCodeToString := 'Medicao: PFa fora de faixa';
        E_EventCode.ALARM_MEAS_PFB_RANGE:
            FC_EventCodeToString := 'Medicao: PFb fora de faixa';
        E_EventCode.ALARM_MEAS_PFC_RANGE:
            FC_EventCodeToString := 'Medicao: PFc fora de faixa';
        E_EventCode.ALARM_MEAS_FROZEN:
            FC_EventCodeToString := 'Medicao: congelada (frozen)';
    
        // Comunicação medidor
        E_EventCode.ALARM_MEAS_MODBUS_ERROR:
            FC_EventCodeToString := 'Medidor: erro Modbus';
        E_EventCode.ALARM_MEAS_MODBUS_TIMEOUT:
            FC_EventCodeToString := 'Medidor: timeout';
    
        // Ciclo / watchdog
        E_EventCode.ALARM_SCAN_OVERRUN:
            FC_EventCodeToString := 'Sistema: scan overrun';
    
        // Comunicação inversores (canal degradado)
        E_EventCode.ALARM_CH1_MODBUS_ERRO:
            FC_EventCodeToString := 'Canal COM1 >50% falhas';
        E_EventCode.ALARM_CH2_MODBUS_ERRO:
            FC_EventCodeToString := 'Canal COM2 >50% falhas';
        E_EventCode.ALARM_CH1_MODBUS_TIMEOUT:
            FC_EventCodeToString := 'Canal COM1 TIMEOUT < 3x';
        E_EventCode.ALARM_CH2_MODBUS_TIMEOUT:
            FC_EventCodeToString := 'Canal COM2 TIMEOUT < 3x';
    
        // =============================================================
        // CRITICAL (0x8xxx)
        // =============================================================
        // Startup
        E_EventCode.CRIT_SERIAL_INIT_FAILED:
            FC_EventCodeToString := 'Startup: falha init serial';
        E_EventCode.CRIT_RTC_FAILED:
            FC_EventCodeToString := 'Startup: falha RTC';
        E_EventCode.CRIT_INSTALLED_PWR_ZERO:
            FC_EventCodeToString := 'Startup: potencia instalada = 0';
        E_EventCode.CRIT_K1_TIMEOUT:
            FC_EventCodeToString := 'Startup: timeout K1';
    
        // Medição
        E_EventCode.CRIT_MEAS_PERSISTENT_FAIL:
            FC_EventCodeToString := 'Medicao: falha persistente';
        E_EventCode.CRIT_MEAS_COM_FAIL:
            FC_EventCodeToString := 'Medidor: falha comunicacao';
    
        // Comunicação inversores
        E_EventCode.CRIT_INV_CHANNEL_FAIL:
            FC_EventCodeToString := 'Inversores: falha canal comunicacao';
    
        // Controle
        E_EventCode.CRIT_INSTALLED_POWER_ZERO:
            FC_EventCodeToString := 'Controle: potencia instalada zero';
    
        // Scheduler
        E_EventCode.CRIT_RTC_READ_FAIL:
            FC_EventCodeToString := 'Scheduler: falha leitura RTC';
        E_EventCode.CRIT_SCHEDULE_INDEX_INVALID:
            FC_EventCodeToString := 'Scheduler: indice invalido';
    
        // Overrun
        E_EventCode.CRIT_SCAN_OVERRUN:
            FC_EventCodeToString := '3× overruns consecutivos → FAIL';
    
        // Proteções normativas
        E_EventCode.CRIT_HARDLIMIT_15S:
            FC_EventCodeToString := 'Protecao: HardLimit >15s';
        E_EventCode.CRIT_EXPORT_OVER_LPI_30S:
            FC_EventCodeToString := 'Protecao: Exportacao >LPI >30s';
        E_EventCode.CRIT_MEDIDOR_TIMEOUT_IN_FAIL:
            FC_EventCodeToString := 'Protecao: timeout medidor em FAIL';
    
        // STOP / Trip
        E_EventCode.CRIT_STOP_ENTRY:
            FC_EventCodeToString := 'STOP: entrada em STOP';
        E_EventCode.CRIT_K2_DID_NOT_OPEN:
            FC_EventCodeToString := 'STOP: K2 nao abriu';
        E_EventCode.CRIT_STATE_CORRUPTION:
            FC_EventCodeToString := 'Sistema: corrupcao de estado';
    
    ELSE
        FC_EventCodeToString := 'Evento desconhecido';
    END_CASE
END_FUNCTION
