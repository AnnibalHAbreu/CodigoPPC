(*
  FB_TurnOff - OPÇÃO B + MODO 1
  - FB NÃO usa GVL.
  - FB NÃO escreve setpoints, NÃO reseta PI, NÃO chama FB_WriteCom.
  - FB SÓ pede ações (pulsos) e decide transições.
  - Main executa: zerar setpoints + reset PI + chamadas FB_WriteCom.
*)
FUNCTION_BLOCK FB_TurnOff
VAR_INPUT
    xEnable          : BOOL;
    xStartResetEdge  : BOOL;

    xK2_in           : BOOL;

    rPt_kW           : REAL;
    xMeasDataOK      : BOOL;

    rP_Threshold_kW  : REAL := 0.5;
    tVerifyTimeout   : TIME := T#30S;
    tK2Timeout       : TIME := T#2S;
    uMaxWriteRetries : UINT := 3;

    // feedback das escritas (Main fornece)
    xCom1Done        : BOOL;
    xCom1Critical    : BOOL;
    xCom2Done        : BOOL;
    xCom2Critical    : BOOL;
END_VAR

VAR_OUTPUT
    // saídas físicas
    xK1_out          : BOOL;
    xK2_out          : BOOL;
    xLedRed          : BOOL;
    xLedYellow       : BOOL;
    xLedGreen        : BOOL;

    // pedidos ao Main (OPÇÃO B)
    xReqZeroSetpoints : BOOL;   // pulso 1 scan
    xReqResetPI       : BOOL;   // pulso 1 scan
    xReqResetCOM      : BOOL;   // pulso 1 scan
    xWriteZeroEnable  : BOOL;   // nível enquanto precisa escrever zero

    // transições
    xRequestStop     : BOOL;
    xRequestStart    : BOOL;

    // log 1 por transição
    xLogEvent        : BOOL;
    eLogCode         : E_EventCode;
    rLogParam1       : REAL;
    rLogParam2       : REAL;
END_VAR

VAR
    status              : E_TurnOffState := E_TurnOffState.TO_INIT;
    stPrevLogged     : E_TurnOffState := E_TurnOffState.TO_INIT;

    uRetry           : UINT := 0;

    tonVerify        : TON;
    tonK2            : TON;

    bInitPulseDone   : BOOL := FALSE;
END_VAR

    // defaults
    xRequestStop := FALSE;
    xRequestStart := FALSE;
    
    xReqZeroSetpoints := FALSE;
    xReqResetPI := FALSE;
    xReqResetCOM := FALSE;
    xWriteZeroEnable := FALSE;
    
    xLogEvent := FALSE;
    eLogCode := E_EventCode.EVT_NONE;
    rLogParam1 := 0.0;
    rLogParam2 := 0.0;
    
    IF NOT xEnable THEN
        status:= E_TurnOffState.TO_INIT;
        stPrevLogged := E_TurnOffState.TO_INIT;
        uRetry := 0;
        tonVerify(IN := FALSE);
        tonK2(IN := FALSE);
        bInitPulseDone := FALSE;
    
        xK1_out := FALSE;
        xK2_out := FALSE;
        xLedRed := FALSE;
        xLedYellow := FALSE;
        xLedGreen := FALSE;
        RETURN;
    END_IF
    
    // 1 log por transição (somente quando muda st)
    IF status<> stPrevLogged THEN
        stPrevLogged := status;
        xLogEvent := TRUE;
        CASE status OF
            E_TurnOffState.TO_INIT:        eLogCode := E_EventCode.INFO_TURNOFF_ENTRY;
            E_TurnOffState.TO_VERIFY:      eLogCode := E_EventCode.INFO_TURNOFF_ZERO_SENT;
            E_TurnOffState.TO_DISCONNECT:  eLogCode := E_EventCode.INFO_TURNOFF_EXPORT_CONFIRMED;
            E_TurnOffState.TO_CONFIRM:     eLogCode := E_EventCode.INFO_TURNOFF_K2_TRIPPED;
            E_TurnOffState.TO_DONE:        eLogCode := E_EventCode.INFO_TURNOFF_DONE;
        END_CASE
    END_IF
    
    CASE status OF
    
        E_TurnOffState.TO_INIT:
            xLedYellow := TRUE;  xLedGreen := FALSE; xLedRed := FALSE;
            xK1_out := TRUE;
            xK2_out := FALSE;
    
            tonVerify(IN := FALSE);
            tonK2(IN := FALSE);
            uRetry := 0;
    
            // pede ações UMA VEZ na entrada do TURNOFF (pulso)
            IF NOT bInitPulseDone THEN
                xReqZeroSetpoints := TRUE;
                xReqResetPI := TRUE;
                xReqResetCOM := TRUE;
                bInitPulseDone := TRUE;
            END_IF
    
            status:= E_TurnOffState.TO_WRITE_ZERO;
    
        E_TurnOffState.TO_WRITE_ZERO:
            xLedYellow := TRUE;  xLedGreen := FALSE; xLedRed := FALSE;
            xK1_out := TRUE;
            xK2_out := FALSE;
    
            // habilita escritas de zero no Main
            xWriteZeroEnable := TRUE;
    
            // aguarda resultado das duas COM (feedback do Main)
            IF xCom1Done AND xCom2Done THEN
                IF xCom1Critical OR xCom2Critical THEN
                    uRetry := uRetry + 1;
    
                    xLogEvent := TRUE;
                    eLogCode := E_EventCode.WARN_TURNOFF_WRITE_RETRY;
                    rLogParam1 := TO_REAL(uRetry);
    
                    IF uRetry >= uMaxWriteRetries THEN
                        xLogEvent := TRUE;
                        eLogCode := E_EventCode.CRIT_TURNOFF_WRITE_EXHAUSTED;
                        rLogParam1 := TO_REAL(uRetry);
                        xRequestStop := TRUE;
                    ELSE
                        // retry: pede reset COM + re-zero setpoints por segurança
                        xReqZeroSetpoints := TRUE;
                        xReqResetPI := TRUE;
                        xReqResetCOM := TRUE;
                        status:= E_TurnOffState.TO_WRITE_ZERO; // permanece, mas reinicia escrita no Main via ResetCOM
                    END_IF
                ELSE
                    status:= E_TurnOffState.TO_VERIFY;
                END_IF
            END_IF
    
        E_TurnOffState.TO_VERIFY:
            xLedYellow := TRUE;  xLedGreen := FALSE; xLedRed := FALSE;
            xK1_out := TRUE;
            xK2_out := FALSE;
    
            tonVerify(IN := TRUE, PT := tVerifyTimeout);
    
            IF xMeasDataOK AND (ABS(rPt_kW) < rP_Threshold_kW) THEN
                tonVerify(IN := FALSE);
    
                xLogEvent := TRUE;
                eLogCode := E_EventCode.INFO_TURNOFF_EXPORT_CONFIRMED;
                rLogParam1 := rPt_kW;
                rLogParam2 := rP_Threshold_kW;
    
                status:= E_TurnOffState.TO_DISCONNECT;
            END_IF
    
            IF tonVerify.Q THEN
                tonVerify(IN := FALSE);
    
                xLogEvent := TRUE;
                eLogCode := E_EventCode.CRIT_TURNOFF_VERIFY_TIMEOUT;
                rLogParam1 := rPt_kW;
                rLogParam2 := REAL#30.0;
    
                xRequestStop := TRUE;
            END_IF
    
        E_TurnOffState.TO_DISCONNECT:
            xLedYellow := TRUE;  xLedGreen := FALSE; xLedRed := FALSE;
            xK1_out := FALSE;
            xK2_out := TRUE;
    
            tonK2(IN := FALSE);
            status:= E_TurnOffState.TO_CONFIRM;
    
        E_TurnOffState.TO_CONFIRM:
            xLedYellow := TRUE;  xLedGreen := FALSE; xLedRed := FALSE;
            xK1_out := FALSE;
            xK2_out := TRUE;
    
            tonK2(IN := TRUE, PT := tK2Timeout);
    
            IF tonK2.Q THEN
                tonK2(IN := FALSE);
    
                IF xK2_in THEN
                    xLogEvent := TRUE;
                    eLogCode := E_EventCode.CRIT_TURNOFF_K2_NOT_OPENED;
                    xLedRed := TRUE;
                ELSE
                    xLogEvent := TRUE;
                    eLogCode := E_EventCode.INFO_TURNOFF_K2_CONFIRMED;
                END_IF
    
                status:= E_TurnOffState.TO_DONE;
            END_IF
    
        E_TurnOffState.TO_DONE:
            xK1_out := FALSE;
            xK2_out := TRUE;
    
            xLedGreen := FALSE;
            xLedYellow := TRUE;
            xLedRed := xK2_in;
    
            IF xStartResetEdge THEN
                xRequestStart := TRUE;
    
                // rearma interno p/ próxima vez
                status:= E_TurnOffState.TO_INIT;
                stPrevLogged := E_TurnOffState.TO_INIT;
                uRetry := 0;
                bInitPulseDone := FALSE;
            END_IF
    END_CASE
END_FUNCTION_BLOCK
