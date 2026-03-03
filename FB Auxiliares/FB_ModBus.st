FUNCTION_BLOCK FB_ModBus

VAR_INPUT
    tTimeout    : TIME;
END_VAR

VAR_IN_OUT
    trigInv     : BOOL;                    // ex.: Global.trigInvCOM100[i]
    pSlave      : ModbusSlaveComPort;      // ex.: Global.pInversores100[i]^
END_VAR

VAR_OUTPUT
    result      : E_ModbusResult;
END_VAR

VAR
    state       : (TRIG, WAIT_BUSY_ON, WAIT_DONE) := TRIG;
    tonTimer    : TON;
END_VAR

    // ============================================================
    // Máquina de estados de escrita em inversores
    // ============================================================
    
    // estado default por ciclo
    result := E_ModbusResult.BUSY;
    
    // timeout só enquanto espera finalização real
    tonTimer(IN := (state = WAIT_DONE), PT := tTimeout);
    
    CASE state OF
    
        TRIG:
            trigInv := TRUE;
            state := WAIT_BUSY_ON;
    
       WAIT_BUSY_ON:
            trigInv := FALSE;            // desce trigger (garante borda)
            IF pSlave.xBusy THEN         // transação realmente iniciou
                state := WAIT_DONE;
            END_IF
    
        WAIT_DONE:
        	IF pSlave.xDone THEN
                trigInv := FALSE;
                state := TRIG;
                result := E_ModbusResult.DONE;
    		
          	ELSIF pSlave.xError THEN
                state := TRIG;
    			trigInv := FALSE;
                result := E_ModbusResult.ERRO;
    			FC_LogEvent(
    				eCode:=TO_UINT(pSlave.byModbusError) + 16#4A00,
    				bRaised:=TRUE,
    				rParam1:=0.0,
    				rParam2:=0.0,
    				uMachState := GVL_Main.MachineState
    				);
    			
          	ELSIF tonTimer.Q THEN
                state := TRIG;
                trigInv := FALSE;
                result := E_ModbusResult.TIMEOUT;
            END_IF
    END_CASE
END_FUNCTION_BLOCK
