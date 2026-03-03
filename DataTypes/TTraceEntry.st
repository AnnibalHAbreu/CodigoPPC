TYPE TTraceEntry :
STRUCT
        cyc         : UDINT;
        mode        : USINT;
        startEdge   : BOOL;
        xExecute    : BOOL;
        xAbort      : BOOL;
        xBusy       : BOOL;
        xDone       : BOOL;
        xError      : BOOL;
        xAborted    : BOOL;
        toQ         : BOOL;
        modbusErr   : UDINT;
        eResult     : E_ModbusResult;
    END_STRUCT
END_TYPE
