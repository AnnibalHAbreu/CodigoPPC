FUNCTION FC_LogEvent : BOOL
VAR_INPUT
    eCode      : E_EventCode;
    bRaised    : BOOL;
    rParam1    : REAL := 0.0;
    rParam2    : REAL := 0.0;
    uMachState : UINT := 0;
END_VAR

    GVL_Main.fbEventLog.LogEvent(
        eCode      := eCode,
        bRaised    := bRaised,
        rParam1    := rParam1,
        rParam2    := rParam2,
        uMachState := uMachState
    );
    
    FC_LogEvent := TRUE;
END_FUNCTION
