(* ═══════════════════════════════════════════════════════════════════════
   ST_InverterProfile
   ═══════════════════════════════════════════════════════════════════════
   Perfil completo de um modelo de inversor: identidade, restrições de
   comunicação e mapa de registros de escrita.

   Limites do mapa:
     MAX_WRITE_REGS = 5  (canais de escrita por inversor)

   USO:
     - Declarar como VAR_GLOBAL CONSTANT em GVL_ModbusProfiles
     - Passar por ponteiro para FB_ModbusRTU_Write
     - Nunca modificar em tempo de execução (CONSTANT)

   EXTENSÃO FUTURA:
     Adicionar ReadMap quando leitura de status de inversor for necessária.
     Por ora o foco é escrita de setpoints (P% e PF).
   ═══════════════════════════════════════════════════════════════════════ *)
TYPE ST_InverterProfile :
STRUCT
    // ── Identificação ────────────────────────────────────────────────
    Name                : STRING(40);   // Ex: 'Goodwe GW50K-MT'
    ManufacturerCode    : USINT;        // 1=Goodwe, 2=SMA, 3=Fronius ... (para log)

    // ── Restrições de protocolo ──────────────────────────────────────
    MaxRegsPerWrite     : UINT;         // 1 = só FC06 (Goodwe); >1 = FC16 possível
    InterFrameDelayMs   : UINT;         // Delay entre frames consecutivos ao mesmo slave (ms)
                                        // Goodwe: 0 (ModbusFB já respeita tempo de silêncio RTU)

    // ── Mapa de escrita ──────────────────────────────────────────────
    nWriteRegs          : UINT;         // Quantidade de registros válidos em WriteMap (1..5)
    WriteMap            : ARRAY[0..4] OF ST_ModbusRegister;
    // Índice convencional:
    //   0 = Setpoint P (%)
    //   1 = Setpoint PF (valor Modbus conforme protocolo)
    //   2..4 = reservados / futuros

END_STRUCT
END_TYPE
