// ════════════════════════════════════════════════════════════════════
// FC_EventCodeToString — Mensagem legível para E_EventCode (PPC-GD)
// ════════════════════════════════════════════════════════════════════
// Retorna string descritiva para cada código de evento definido em E_EventCode
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
            // INFO (0x1xxx) — registro operacional, sem ação
            // =============================================================
    
            // ── Startup (0x11xx) ─────────────────────────────────────────
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
            E_EventCode.INFO_INV_CHECK_OK:                                   
                FC_EventCodeToString := 'Startup: inversores configurados OK';
    
            // ── Medicao / Operacao (0x12xx) ──────────────────────────────
            E_EventCode.INFO_MEAS_READ_OK:
                FC_EventCodeToString := 'Medidor: leitura OK';
            E_EventCode.INFO_MEAS_DATA_VALID:
                FC_EventCodeToString := 'Medidor: dados validos';
            E_EventCode.INFO_MEAS_RECOVERING:
                FC_EventCodeToString := 'Medicao: recuperando (erros reduzindo)';
    
            // ── Escrita inversores (0x13xx) ──────────────────────────────
            E_EventCode.INFO_CH1_WRITE_OK:
                FC_EventCodeToString := 'Inversores: escrita canal COM1 OK';
            E_EventCode.INFO_CH2_WRITE_OK:                                  
                FC_EventCodeToString := 'Inversores: escrita canal COM2 OK';
    
            // ── Scheduler (0x15xx) ───────────────────────────────────────
            E_EventCode.INFO_SPECIAL_DATE_ACTIVE:
                FC_EventCodeToString := 'Scheduler: data especial ativa';
            E_EventCode.INFO_ZERO_GRID_MODE:
                FC_EventCodeToString := 'Scheduler: modo zero grid ativo';
    
            // ── Maquina de estados / Ciclo (0x16xx) ──────────────────────
            E_EventCode.INFO_CYCLE_COMPLETE:
                FC_EventCodeToString := 'Ciclo: completo';
            E_EventCode.INFO_FAIL_RECOVERY:
                FC_EventCodeToString := 'FAIL: recuperacao automatica';
            E_EventCode.INFO_STATE_CHANGE:
                FC_EventCodeToString := 'Maquina de estados: mudanca de estado';
            E_EventCode.INFO_FAIL_RECOVERY_STARTED:                          
                FC_EventCodeToString := 'FAIL: condicoes de recuperacao detectadas';
            E_EventCode.INFO_FAIL_STATE_CHANGE:                              
                FC_EventCodeToString := 'FAIL: mudanca de sub-estado';
    
            // ── STOP / Reset (0x18xx) ────────────────────────────────────
            E_EventCode.INFO_STOP_K2_OPEN_CONFIRMED:
                FC_EventCodeToString := 'STOP: K2 aberto confirmado';
            E_EventCode.INFO_STOP_RESET_APPROVED:
                FC_EventCodeToString := 'STOP: reset aprovado';
            E_EventCode.INFO_STOP_RESET_WAITING:
                FC_EventCodeToString := 'STOP: aguardando reset';
    
            // ── TURNOFF — Desligamento controlado (0x19xx) ───────────────
            E_EventCode.INFO_TURNOFF_ENTRY:
                FC_EventCodeToString := 'TURNOFF: iniciando desligamento controlado';
            E_EventCode.INFO_TURNOFF_ZERO_SENT:
                FC_EventCodeToString := 'TURNOFF: setpoints zero enviados';
            E_EventCode.INFO_TURNOFF_EXPORT_CONFIRMED:
                FC_EventCodeToString := 'TURNOFF: geracao zero confirmada';
            E_EventCode.INFO_TURNOFF_K1_DISABLED:
                FC_EventCodeToString := 'TURNOFF: K1 desativado';
            E_EventCode.INFO_TURNOFF_K2_TRIPPED:
                FC_EventCodeToString := 'TURNOFF: K2 trip comandado';
            E_EventCode.INFO_TURNOFF_K2_CONFIRMED:
                FC_EventCodeToString := 'TURNOFF: K2 aberto confirmado';
            E_EventCode.INFO_TURNOFF_DONE:
                FC_EventCodeToString := 'TURNOFF: desligamento concluido';
    
            // =============================================================
            // WARNING (0x2xxx) — desvio toleravel, sem acao de potencia
            // =============================================================
    
            // ── Startup (0x21xx) ─────────────────────────────────────────
            E_EventCode.WARN_NO_INVERSORES_COM02:
                FC_EventCodeToString := 'Startup: nenhum inversor no COM2';
            E_EventCode.WARN_INV_CHECK_PARTIAL:                              
                FC_EventCodeToString := 'Startup: inversores parcialmente responderam';
    
            // ── Medicao (0x22xx) ─────────────────────────────────────────
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
    
            // ── Comunicacao inversores (0x23xx) ──────────────────────────
            E_EventCode.WARN_WRITE_INV_ERROR:
                FC_EventCodeToString := 'Inversores: erro de escrita';
            E_EventCode.WARN_WRITE_INV_TIMEOUT:
                FC_EventCodeToString := 'Inversores: timeout de escrita';
    
            // ── Controle (0x24xx) ────────────────────────────────────────
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
    
            // ── STOP / Reset (0x28xx) ────────────────────────────────────
            E_EventCode.WARN_STOP_RESET_DENIED:
                FC_EventCodeToString := 'STOP: reset negado';
    
            // ── TURNOFF (0x29xx) ─────────────────────────────────────────
            E_EventCode.WARN_TURNOFF_WRITE_RETRY:
                FC_EventCodeToString := 'TURNOFF: retry escrita zero';
    
            // =============================================================
            // ALARM (0x4xxx) — falha que requer atencao, pode degradar
            // =============================================================
    
            // ── Medicao — Range (0x42xx) ─────────────────────────────────
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
            E_EventCode.ALARM_MEAS_PT_XCHECK_FAIL:                          
                FC_EventCodeToString := 'Medicao: xcheck Pt falhou';
            E_EventCode.ALARM_MEAS_PA_XCHECK_FAIL:                          
                FC_EventCodeToString := 'Medicao: xcheck Pa falhou';
            E_EventCode.ALARM_MEAS_PB_XCHECK_FAIL:                          
                FC_EventCodeToString := 'Medicao: xcheck Pb falhou';
            E_EventCode.ALARM_MEAS_PC_XCHECK_FAIL:                          
                FC_EventCodeToString := 'Medicao: xcheck Pc falhou';
            E_EventCode.ALARM_MEAS_PFT_XCHECK_FAIL:                         
                FC_EventCodeToString := 'Medicao: xcheck PFt falhou';
            E_EventCode.ALARM_Q_LIMITED_SURPASS:                             
                FC_EventCodeToString := 'Controle: deficit Q > 20% - verificar banco de capacitores';
            E_EventCode.ALARM_Q_LIMITED_REACHED:                             
                FC_EventCodeToString := 'Controle: Q atingiu limite - banco de capacitores recomendado';
            E_EventCode.ALARM_MEAS_USING_LAST_VALUE:                         
                FC_EventCodeToString := 'Medicao: usando ultima medicao valida';
    
            // ── Comunicacao medidor (0x42xx cont.) ───────────────────────
            E_EventCode.ALARM_MEAS_MODBUS_ERROR:
                FC_EventCodeToString := 'Medidor: erro Modbus';
            E_EventCode.ALARM_MEAS_MODBUS_TIMEOUT:
                FC_EventCodeToString := 'Medidor: timeout Modbus';
    
            // ── Ciclo / watchdog (0x42xx) ─────────────────────────────────
            E_EventCode.ALARM_SCAN_OVERRUN:
                FC_EventCodeToString := 'Sistema: scan overrun';
    
            // ── Comunicacao inversores — canal degradado (0x43xx) ────────
            E_EventCode.ALARM_CH1_MODBUS_ERRO:
                FC_EventCodeToString := 'Canal COM1: >50% falhas Modbus';
            E_EventCode.ALARM_CH2_MODBUS_ERRO:
                FC_EventCodeToString := 'Canal COM2: >50% falhas Modbus';
            E_EventCode.ALARM_CH1_MODBUS_TIMEOUT:
                FC_EventCodeToString := 'Canal COM1: timeout Modbus';
            E_EventCode.ALARM_CH2_MODBUS_TIMEOUT:
                FC_EventCodeToString := 'Canal COM2: timeout Modbus';
    
            // ── Erros driver Modbus Codesys (0x4Axx) ─────────────────────
            E_EventCode.ALARM_MB_ILLEGAL_FUNC:                               
                FC_EventCodeToString := 'Modbus: codigo de funcao nao suportado pelo escravo';
            E_EventCode.ALARM_MB_ILLEGAL_ADDR:                               
                FC_EventCodeToString := 'Modbus: endereco de registro nao suportado';
            E_EventCode.ALARM_MB_ILLEGAL_VALUE:                              
                FC_EventCodeToString := 'Modbus: valor a gravar invalido';
            E_EventCode.ALARM_MB_SLAVE_FAILURE:                              
                FC_EventCodeToString := 'Modbus: falha irrecuperavel no escravo';
            E_EventCode.ALARM_MB_ACKNOWLEDGE:                                
                FC_EventCodeToString := 'Modbus: escravo iniciou operacao longa (ACK)';
            E_EventCode.ALARM_MB_SLAVE_BUSY:                                 
                FC_EventCodeToString := 'Modbus: escravo ocupado com operacao longa';
            E_EventCode.ALARM_MB_MEMORY_PARITY:                              
                FC_EventCodeToString := 'Modbus: erro de paridade de memoria (FC20/21)';
            E_EventCode.ALARM_MB_GW_PATH_UNAVAIL:                            
                FC_EventCodeToString := 'Modbus: caminho gateway indisponivel';
            E_EventCode.ALARM_MB_GW_DEVICE_FAIL:                             
                FC_EventCodeToString := 'Modbus: dispositivo atras do gateway nao responde';
            E_EventCode.ALARM_MB_RESPONSE_TIMEOUT:                           
                FC_EventCodeToString := 'Modbus: timeout de resposta';
            E_EventCode.ALARM_MB_RESPONSE_CRC:                               
                FC_EventCodeToString := 'Modbus: CRC da resposta incorreto';
            E_EventCode.ALARM_MB_WRONG_SLAVE:                                
                FC_EventCodeToString := 'Modbus: resposta de escravo inesperado';
            E_EventCode.ALARM_MB_WRONG_FC:                                   
                FC_EventCodeToString := 'Modbus: resposta com codigo de funcao incorreto';
            E_EventCode.ALARM_MB_INVALID_DATA:                               
                FC_EventCodeToString := 'Modbus: resposta contem dados invalidos';
            E_EventCode.ALARM_MB_INVALID_PROTOCOL:                           
                FC_EventCodeToString := 'Modbus: resposta fora do protocolo Modbus';
            E_EventCode.ALARM_MB_INVALID_HEADER:                             
                FC_EventCodeToString := 'Modbus: cabecalho MBAP invalido';
            E_EventCode.ALARM_MB_INVALID_PARAM:                              
                FC_EventCodeToString := 'Modbus: parametro de entrada invalido';
            E_EventCode.ALARM_MB_UNDEFINED:                                  
                FC_EventCodeToString := 'Modbus: resultado indefinido ou desconhecido';
            E_EventCode.ALARM_MB_APP_ABORTED:                                
                FC_EventCodeToString := 'Modbus: requisicao abortada pela aplicacao';
            E_EventCode.ALARM_MB_APP_TIMEOUT:                                
                FC_EventCodeToString := 'Modbus: timeout de aplicacao';
    
            // =============================================================
            // CRITICAL (0x8xxx) — acao de seguranca (FAIL_SAFE ou STOP)
            // =============================================================
    
            // ── Startup (0x81xx) ─────────────────────────────────────────
            E_EventCode.CRIT_SERIAL_INIT_FAILED:
                FC_EventCodeToString := 'Startup: falha inicializacao serial';
            E_EventCode.CRIT_RTC_FAILED:
                FC_EventCodeToString := 'Startup: falha leitura RTC';
            E_EventCode.CRIT_INSTALLED_PWR_ZERO:
                FC_EventCodeToString := 'Startup: potencia instalada = 0';
            E_EventCode.CRIT_K1_TIMEOUT:
                FC_EventCodeToString := 'Startup: timeout confirmacao K1';
            E_EventCode.CRIT_K2_TIMEOUT:                                     
                FC_EventCodeToString := 'Startup: timeout confirmacao K2';
            E_EventCode.CRIT_TC_POWER_NOT_SET:                              
                FC_EventCodeToString := 'Startup: TC_Power_kW nao configurado';
            E_EventCode.CRIT_MEAS_INIC_ERRO_TIMEOUT:                         
                FC_EventCodeToString := 'Startup: erro/timeout no teste de comunicacao do medidor';
            E_EventCode.CRIT_MEAS_INIC_FAIL:                                 
                FC_EventCodeToString := 'Startup: falha no teste de comunicacao do medidor';
            E_EventCode.CRIT_INV_CHECK_BELOW_THRESHOLD:                      
                FC_EventCodeToString := 'Startup: inversores respondentes abaixo do limiar';
    
            // ── Medicao (0x82xx) ─────────────────────────────────────────
            E_EventCode.CRIT_MEAS_PERSISTENT_FAIL:
                FC_EventCodeToString := 'Medicao: falha persistente (>=5 erros)';
            E_EventCode.CRIT_MEAS_COM_FAIL:
                FC_EventCodeToString := 'Medidor: falha de comunicacao -> FAIL';
            E_EventCode.CRIT_MEAS_MODBUS_TIMEOUT:                            
                FC_EventCodeToString := 'Medidor: timeout Modbus -> FAIL';
            E_EventCode.CRIT_MEAS_MODBUS_ERRO:                               
                FC_EventCodeToString := 'Medidor: erro Modbus -> FAIL';
    
            // ── Comunicacao inversores (0x83xx) ──────────────────────────
            E_EventCode.CRIT_INV_CHANNEL_FAIL:
                FC_EventCodeToString := 'Inversores: falha total de canal -> FAIL';
            E_EventCode.CRIT_CH1_MODBUS_TIMEOUT:                             
                FC_EventCodeToString := 'Canal COM1: timeout 3x consecutivos -> FAIL';
            E_EventCode.CRIT_CH2_MODBUS_TIMEOUT:                             
                FC_EventCodeToString := 'Canal COM2: timeout 3x consecutivos -> FAIL';
            E_EventCode.CRIT_CH1_MODBUS_ERRO:                                
                FC_EventCodeToString := 'Canal COM1: >50% falhas -> FAIL';
            E_EventCode.CRIT_CH2_MODBUS_ERRO:                                
                FC_EventCodeToString := 'Canal COM2: >50% falhas -> FAIL';
    
            // ── Controle (0x84xx) ────────────────────────────────────────
            E_EventCode.CRIT_INSTALLED_POWER_ZERO:
                FC_EventCodeToString := 'Controle: potencia instalada zero em runtime';
            E_EventCode.CRIT_INSTALLED_SMAX_ZERO:                            
                FC_EventCodeToString := 'Controle: potencia reativa instalada (Smax) = 0';
    
            // ── Scheduler (0x85xx) ───────────────────────────────────────
            E_EventCode.CRIT_RTC_READ_FAIL:
                FC_EventCodeToString := 'Scheduler: falha leitura RTC em operacao';
            E_EventCode.CRIT_SCHEDULE_INDEX_INVALID:
                FC_EventCodeToString := 'Scheduler: indice de dia/hora invalido';
    
            // ── Watchdog / Scan (0x86xx) ─────────────────────────────────
            E_EventCode.CRIT_SCAN_OVERRUN:
                FC_EventCodeToString := 'Sistema: 3x scan overrun consecutivos -> FAIL';
            E_EventCode.CRIT_FAIL_WRITE_ZERO_FAILED:                         
                FC_EventCodeToString := 'FAIL: escrita zero falhou';
            E_EventCode.CRIT_FAIL_WRITE_EXHAUSTED:                           
                FC_EventCodeToString := 'FAIL: esgotou tentativas de escrita zero';
            E_EventCode.CRIT_FAIL_GLOBAL_TIMEOUT:                            
                FC_EventCodeToString := 'FAIL: timeout global de permanencia em FAIL';
    
            // ── Protecao normativa (0x87xx) ──────────────────────────────
            E_EventCode.CRIT_HARDLIMIT_15S:
                FC_EventCodeToString := 'Protecao: P > LPI+10%Pnom por >15s -> STOP';
            E_EventCode.CRIT_EXPORT_OVER_LPI_30S:
                FC_EventCodeToString := 'Protecao: exportacao > LPI por >30s -> STOP';
            E_EventCode.CRIT_MEAS_TIMEOUT_IN_FAIL:
                FC_EventCodeToString := 'Protecao: 5s sem medicao valida em FAIL -> STOP';
    
            // ── FAIL / STOP / Trip (0x88xx) ──────────────────────────────
            E_EventCode.CRIT_STOP_ENTRY:
                FC_EventCodeToString := 'STOP: entrada em STOP';
            E_EventCode.CRIT_K2_NOT_OPENED:
                FC_EventCodeToString := 'STOP: K2 nao abriu apos 2s -> FaultLatch';
            E_EventCode.CRIT_STATE_CORRUPTION:
                FC_EventCodeToString := 'Sistema: corrupcao de MachineState';
            E_EventCode.CRIT_FAIL_ENTRY:                                     
                FC_EventCodeToString := 'FAIL: entrada no estado FAIL';
    
            // ── TURNOFF — Desligamento controlado (0x89xx) ───────────────
            E_EventCode.CRIT_TURNOFF_WRITE_EXHAUSTED:
                FC_EventCodeToString := 'TURNOFF: esgotou tentativas de escrita -> STOP';
            E_EventCode.CRIT_TURNOFF_VERIFY_TIMEOUT:
                FC_EventCodeToString := 'TURNOFF: timeout verificacao geracao -> STOP';
            E_EventCode.CRIT_TURNOFF_K2_NOT_OPENED:
                FC_EventCodeToString := 'TURNOFF: K2 nao abriu apos trip -> FaultLatch';
            E_EventCode.CRIT_TURNOFF_K1_NOT_OPENED:
                FC_EventCodeToString := 'TURNOFF: K1 nao abriu apos comando -> STOP';
    
        ELSE
            FC_EventCodeToString := 'Evento desconhecido';
        END_CASE
END_FUNCTION
