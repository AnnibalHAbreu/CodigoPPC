(* ═══════════════════════════════════════════════════════════════════════
   GVL_ModbusProfiles — Perfis de dispositivos Modbus
   ═══════════════════════════════════════════════════════════════════════
   Contém os perfis hardcoded de cada modelo de inversor suportado.
   Declarados como CONSTANT: imutáveis em runtime, residem em Flash.

   FASE 1: apenas Goodwe GW50K-MT (único modelo em operação).
   FASE 4: FB_LoadProfiles substituirá estes valores por dados do CSV,
           mantendo este como fallback em caso de falha de leitura.

   PROTOCOLO GOODWE — REGISTRO 0x0101 (Fator de Potência):
     Indutivo  (Q ≥ 0): valor 80..100 → PF = valor / 100  (ex: 92 → PF 0.92)
     Capacitivo(Q < 0): valor  1.. 20 → PF = (100-valor)/100 (ex: 10 → PF 0.90 cap)
     A conversão para este formato já é feita pelo FB_QAlloc e armazenada
     em GVL_Main.PF_inv_Percent[i]. Aqui Scale=1.0 pois o valor já está
     no formato correto para o registro.

   PROTOCOLO GOODWE — REGISTRO 0x0100 (Potência Ativa):
     Valor direto 0..100 representando 0..100% da potência nominal.
     FB_PAlloc já calcula P_inv_Percent em 0..100. Scale=1.0.
   ═══════════════════════════════════════════════════════════════════════ *)
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT

    Profile_Goodwe_GW50K : ST_InverterProfile := (
        Name             := 'Goodwe GW50K-MT',
        ManufacturerCode := 1,          // 1 = Goodwe
        MaxRegsPerWrite  := 1,          // Goodwe: 1 registro por transação FC06
        InterFrameDelayMs := 0,         // ModbusFB respeita silêncio RTU automaticamente

        nWriteRegs := 2,
        WriteMap := [
            // Índice 0 — Setpoint Potência Ativa (%)
            (Address     := 16#0100,    // 256 decimal
             Quantity    := 1,
             FuncCode    := 6,          // FC06: Write Single Register
             Scale       := 1.0,        // P_inv_Percent já está em 0..100
             Offset      := 0.0,
             MinPhys     := 0.0,        // 0% = inversor parado
             MaxPhys     := 100.0,      // 100% = potência nominal
             bEnabled    := TRUE),

            // Índice 1 — Setpoint Fator de Potência (formato Modbus Goodwe)
            // Indutivo:  80..100 (PF = valor/100)
            // Capacitivo: 1..20  (PF = (100-valor)/100)
            // PF_inv_Percent já contém o valor neste formato (calculado em FB_QAlloc)
            (Address     := 16#0101,    // 257 decimal
             Quantity    := 1,
             FuncCode    := 6,          // FC06: Write Single Register
             Scale       := 1.0,        // PF_inv_Percent já é o valor de registro
             Offset      := 0.0,
             MinPhys     := 1.0,        // menor valor válido do protocolo
             MaxPhys     := 100.0,      // maior valor válido (PF=1.0 indutivo)
             bEnabled    := TRUE),

            // Índices 2..4 — reservados
            (bEnabled := FALSE, Scale := 1.0, MinPhys := 0.0, MaxPhys := 0.0,
             Address := 0, Quantity := 0, FuncCode := 0, Offset := 0.0),
            (bEnabled := FALSE, Scale := 1.0, MinPhys := 0.0, MaxPhys := 0.0,
             Address := 0, Quantity := 0, FuncCode := 0, Offset := 0.0),
            (bEnabled := FALSE, Scale := 1.0, MinPhys := 0.0, MaxPhys := 0.0,
             Address := 0, Quantity := 0, FuncCode := 0, Offset := 0.0)
        ]
    );

END_VAR
