// ════════════════════════════════════════════════════════════════════
// ST_Event — Registro dos eventos para mostrar na tabela
// ════════════════════════════════════════════════════════════════════
// Tamanho estimado: 28 bytes (verificar alinhamento no target)
//
// CAMPOS:
//   tTimestamp  — Epoch UTC (UDINT, até 2106). Obtido via SysTimeRtcGet.
//   eCode      — Código do evento (E_EventCode). Identifica unicamente o que ocorreu.
//   bRaised    — TRUE = evento apareceu / FALSE = evento foi limpo.
//                Permite rastrear par raise/clear no histórico.
//   rParam1    — Valor de contexto #1 no momento do evento.
//                Ex: Pt medido (kW) quando hard-limit disparou.
//   rParam2    — Valor de contexto #2 no momento do evento.
//                Ex: limite violado (kW), ou índice do inversor.
//   uMachState — Estado da máquina (E_MachineState) no momento do registro.
//                Essencial para análise pós-mortem.
// ════════════════════════════════════════════════════════════════════
TYPE ST_EventEntry :
STRUCT
    tTimestamp      : UDINT;            // UTC epoch (segundos)
    eCode           : E_EventCode;      // UINT — código unificado do evento
    bRaised         : BOOL;             // TRUE=raise, FALSE=clear
    rParam1         : REAL;             // contexto numérico #1
    rParam2         : REAL;             // contexto numérico #2
    uMachState      : UINT;             // E_MachineState no instante do registro
END_STRUCT
END_TYPE
