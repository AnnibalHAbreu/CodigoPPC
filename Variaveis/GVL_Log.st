{attribute 'qualified_only'}
// ════════════════════════════════════════════════════════════════════
// GVL_EventLog — Constantes do sistema de log de eventos
// ════════════════════════════════════════════════════════════════════
// Autor: Eng. Principal / Revisão Técnica PPC-GD
// Plataforma: WAGO CC100 (751-9402) / CODESYS V3.5 SP21 Patch 4
//
// DIMENSIONAMENTO:
//   64 entradas × 28 bytes = ~1.792 bytes de RETAIN
//   WAGO CC100 possui ~32 kB RETAIN → uso < 6%
//   Com ~1 evento/min, cobre >1 hora de histórico completo
//   Com taxa de pico (~10 eventos em cascata), ainda retém >6 min
// ════════════════════════════════════════════════════════════════════
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    MAX_EVENT_ENTRIES   : UINT := 64;   // Tamanho do ring buffer (potência de 2 facilita debug)
END_VAR
