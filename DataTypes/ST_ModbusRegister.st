(* ═══════════════════════════════════════════════════════════════════════
   ST_ModbusRegister
   ═══════════════════════════════════════════════════════════════════════
   Descreve um único registro Modbus: endereço, função, tipo de dado,
   escala e limites físicos válidos.

   Usado em ST_InverterProfile para declarar o mapa de leitura e escrita
   de cada modelo de inversor sem recompilar o projeto.

   NOTA SOBRE Scale e Offset:
     ValorFísico = (ValorModbus × Scale) + Offset
     ValorModbus = ROUND((ValorFísico - Offset) / Scale)
     Para registros que já chegam em unidade final (ex: reg 0x0100 = %):
       Scale := 1.0, Offset := 0.0

   NOTA SOBRE FuncCode:
     3  = Read Holding Registers  (FC03)
     6  = Write Single Register   (FC06)  ← Goodwe: obrigatório 1 reg por vez
     16 = Write Multiple Registers (FC16) ← outros fabricantes
   ═══════════════════════════════════════════════════════════════════════ *)
TYPE ST_ModbusRegister :
STRUCT
    Address     : UINT;     // Endereço do registro (base 0, ex: 16#0100 = 256)
    Quantity    : UINT;     // Quantidade de registros (1 para UINT/INT, 2 para DWORD/REAL)
    FuncCode    : USINT;    // Código de função Modbus: 3, 6 ou 16
    Scale       : REAL;     // Multiplicador: ValorFísico = ValorReg × Scale
    Offset      : REAL;     // Offset: ValorFísico = (ValorReg × Scale) + Offset
    MinPhys     : REAL;     // Limite físico mínimo (para validação e LIMIT antes de escrever)
    MaxPhys     : REAL;     // Limite físico máximo (para validação e LIMIT antes de escrever)
    bEnabled    : BOOL;     // FALSE = ignora este registro na varredura
END_STRUCT
END_TYPE

