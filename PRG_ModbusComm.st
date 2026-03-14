(* ═══════════════════════════════════════════════════════════════════════
   PRG_ModbusComm — Comunicação Modbus RTU (FASE 3)
   ═══════════════════════════════════════════════════════════════════════
   Executa na Task_ModbusComm (cycle time: 2ms, prioridade alta).

   MUDANÇAS DA FASE 3 em relação à versão anterior:
     REMOVIDO:  fbInvRead, fbInvWrite, fbInvWriteMulti (nunca foram usados)
     REMOVIDO:  auiWriteRegAddr (substituído pelo profile)
     ADICIONADO: fbWriteCOM1, fbWriteCOM2 (movidos do MainProgram)
     ADICIONADO: lógica de pending/done para isolar tasks

   ARQUITETURA DE ISOLAMENTO:
     ClientSerial vive aqui.
     FB_ModbusRTU_Write vive aqui.
     MainProgram NUNCA acessa ClientSerial diretamente.
     Comunicação com MainProgram: apenas via GVL_Comm (flags + arrays).

   RESPONSABILIDADES:
     1. Gerenciar ClientSerial COM1 e COM2
     2. Leitura cíclica do medidor (COM1)
     3. Escrita de setpoints nos inversores (COM1 e COM2)
        quando bWritePendingCOMx for TRUE
     4. Propagar status e resultados para GVL_Comm
   ═══════════════════════════════════════════════════════════════════════ *)
PROGRAM PRG_ModbusComm
VAR
    // ─── Clients seriais (um por porta COM) ──────────────────────────
    clientCOM1          : ModbusFB.ClientSerial;
    clientCOM2          : ModbusFB.ClientSerial;

    // ─── Leitura do medidor (COM1) ───────────────────────────────────
    fbReadMeter         : ModbusFB.ClientRequestReadHoldingRegisters;
    eMeterState         : (MS_IDLE, MS_READING) := MS_IDLE;
    tonMeterPoll        : TON;

    // ─── Escrita nos inversores ──────────────────────────────────────
    fbWriteCOM1         : FB_ModbusRTU_Write;
    fbWriteCOM2         : FB_ModbusRTU_Write;

    // ─── Controle de inicialização ───────────────────────────────────
    bInitDone           : BOOL := FALSE;

    // ─── Detecção de borda dos triggers de escrita ───────────────────
    rTrigWrite1         : R_TRIG;
    rTrigWrite2         : R_TRIG;
END_VAR

        // ═══════════════════════════════════════════════════════════════════
        // INICIALIZAÇÃO (uma vez, no primeiro scan)
        // ═══════════════════════════════════════════════════════════════════
        IF NOT bInitDone THEN
            bInitDone := TRUE;
    
            // ── Configurar COM1 ──────────────────────────────────────────
            clientCOM1(
                iPort      := SysCom.SYS_COM_PORTS.SYS_COMPORT1,
                dwBaudRate := SysCom.SYS_BR_9600,
                byDataBits := 8,
                eParity    := SysCom.SYS_EVENPARITY,
                eStopBits  := SysCom.SYS_ONESTOPBIT,
                eRtuAscii  := ModbusFB.RtuAscii.RTU
            );
            clientCOM1(xConnect := TRUE);
    
            // ── Configurar COM2 ──────────────────────────────────────────
            clientCOM2(
                iPort      := SysCom.SYS_COM_PORTS.SYS_COMPORT2,
                dwBaudRate := SysCom.SYS_BR_9600,
                byDataBits := 8,
                eParity    := SysCom.SYS_EVENPARITY,
                eStopBits  := SysCom.SYS_ONESTOPBIT,
                eRtuAscii  := ModbusFB.RtuAscii.RTU
            );
            clientCOM2(xConnect := TRUE);
    
            // ── Configurar request de leitura do medidor ─────────────────
            fbReadMeter(
                rClient      := clientCOM1,
                uiUnitId     := GVL_Comm.uiMeterSlaveId,
                uiStartItem  := GVL_Comm.uiMeterStartReg,
                uiQuantity   := GVL_Comm.uiMeterRegCount,
                pData        := ADR(GVL_Comm.awMeterRawData[0]),
                udiTimeout   := GVL_Comm.udiMeterTimeout,
                uiMaxRetries := 1
            );
    
            GVL_Comm.bCommInitDone := FALSE;
        END_IF
    
        // ═══════════════════════════════════════════════════════════════════
        // EXECUÇÃO CÍCLICA — obrigatório chamar clients e requests a cada ciclo
        // ═══════════════════════════════════════════════════════════════════
        clientCOM1();
        clientCOM2();
    
        // Propagar estado de conexão
        GVL_Comm.bCOM1Connected := clientCOM1.xConnected;
        GVL_Comm.bCOM2Connected := clientCOM2.xConnected;
        GVL_Comm.bCOM1Error     := clientCOM1.xError;
        GVL_Comm.bCOM2Error     := clientCOM2.xError;
    
        IF clientCOM1.xConnected AND clientCOM2.xConnected THEN
            GVL_Comm.bCommInitDone := TRUE;
        END_IF
    
        // ═══════════════════════════════════════════════════════════════════
        // POLLING DO MEDIDOR — Leitura cíclica com timer fixo
        // ═══════════════════════════════════════════════════════════════════
        fbReadMeter(rClient := clientCOM1);
    
        IF clientCOM1.xConnected THEN
    
            CASE eMeterState OF
    
                MS_IDLE:
                    tonMeterPoll(IN := TRUE, PT := UINT_TO_TIME(GVL_Comm.uiMeterPollMs));
                    IF tonMeterPoll.Q THEN
                        tonMeterPoll(IN := FALSE);
                        fbReadMeter(
                            rClient     := clientCOM1,
                            xExecute    := TRUE,
                            uiUnitId    := GVL_Comm.uiMeterSlaveId,
                            uiStartItem := GVL_Comm.uiMeterStartReg,
                            uiQuantity  := GVL_Comm.uiMeterRegCount,
                            pData       := ADR(GVL_Comm.awMeterRawData[0])
                        );
                        eMeterState := MS_READING;
                    END_IF
    
                MS_READING:
                    IF fbReadMeter.xDone THEN
                        fbReadMeter.xExecute := FALSE;
                        GVL_Comm.bMeterReadDone  := TRUE;
                        GVL_Comm.eMeterResult    := E_ModbusResult.DONE;
                        GVL_Comm.bMeterOnline    := TRUE;
                        GVL_Comm.uiMeterRegsRead := GVL_Comm.uiMeterRegCount;
                        eMeterState := MS_IDLE;
    
                    ELSIF fbReadMeter.xError THEN
                        fbReadMeter.xExecute := FALSE;
                        GVL_Comm.bMeterReadDone := TRUE;
                        IF fbReadMeter.eErrorID = ModbusFB.Error.ReplyTimeout THEN
                            GVL_Comm.eMeterResult := E_ModbusResult.TIMEOUT;
                        ELSE
                            GVL_Comm.eMeterResult := E_ModbusResult.ERRO;
                        END_IF
                        eMeterState := MS_IDLE;
                    END_IF
    
            END_CASE
    
        ELSE
            GVL_Comm.bMeterOnline := FALSE;
            GVL_Comm.eMeterResult := E_ModbusResult.TIMEOUT;
            eMeterState := MS_IDLE;
        END_IF
    
        // ═══════════════════════════════════════════════════════════════════
        // ESCRITA NOS INVERSORES COM1
        // ═══════════════════════════════════════════════════════════════════
        // Detecção de borda: MainProgram seta bWritePendingCOM1, aqui consumimos
        rTrigWrite1(CLK := GVL_Comm.bWritePendingCOM1);
    
        fbWriteCOM1(
            xTrigger      := rTrigWrite1.Q,                 // pulso ao detectar pending
            nInverters    := GVL_Main.NInversoresCOM01,
            tTimeout      := T#500MS,
            maxErrors     := GVL_Main.MAX_CH1_MODBUS_ERROS,
            maxTimeouts   := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
            pProfile      := ADR(GVL_ModbusProfiles.Profile_Goodwe_GW50K),
            rClient       := clientCOM1,
            auiSlaveIds   := GVL_Comm.auiInvSlaveIdsCOM1,
            arWriteValues := GVL_Comm.arWriteValuesCOM1
        );
    
        // Quando varredura concluir, propagar resultado e limpar pending
        IF fbWriteCOM1.xDone THEN
            GVL_Comm.bWriteDoneCOM1         := TRUE;
            GVL_Comm.bWriteCriticalCOM1     := fbWriteCOM1.xCritical;
            GVL_Comm.uiWriteErrCOM1         := fbWriteCOM1.ErrCount;
            GVL_Comm.uiWriteTmoCOM1         := fbWriteCOM1.TmoCount;
            GVL_Comm.uiWriteLastFailInvCOM1 := fbWriteCOM1.LastFailInv;
            GVL_Comm.eWriteLastFailResCOM1  := fbWriteCOM1.LastFailRes;
            GVL_Comm.bWritePendingCOM1      := FALSE;   // consome o trigger
        END_IF
    
        // ═══════════════════════════════════════════════════════════════════
        // ESCRITA NOS INVERSORES COM2
        // ═══════════════════════════════════════════════════════════════════
        rTrigWrite2(CLK := GVL_Comm.bWritePendingCOM2);
    
        fbWriteCOM2(
            xTrigger      := rTrigWrite2.Q,
            nInverters    := GVL_Main.NInversoresCOM02,
            tTimeout      := T#500MS,
            maxErrors     := GVL_Main.MAX_CH2_MODBUS_ERROS,
            maxTimeouts   := GVL_Main.MAX_CH2_MODBUS_TIMEOUTS,
            pProfile      := ADR(GVL_ModbusProfiles.Profile_Goodwe_GW50K),
            rClient       := clientCOM2,
            auiSlaveIds   := GVL_Comm.auiInvSlaveIdsCOM2,
            arWriteValues := GVL_Comm.arWriteValuesCOM2
        );
    
        IF fbWriteCOM2.xDone THEN
            GVL_Comm.bWriteDoneCOM2         := TRUE;
            GVL_Comm.bWriteCriticalCOM2     := fbWriteCOM2.xCritical;
            GVL_Comm.uiWriteErrCOM2         := fbWriteCOM2.ErrCount;
            GVL_Comm.uiWriteTmoCOM2         := fbWriteCOM2.TmoCount;
            GVL_Comm.uiWriteLastFailInvCOM2 := fbWriteCOM2.LastFailInv;
            GVL_Comm.eWriteLastFailResCOM2  := fbWriteCOM2.LastFailRes;
            GVL_Comm.bWritePendingCOM2      := FALSE;
        END_IF
END_PROGRAM
