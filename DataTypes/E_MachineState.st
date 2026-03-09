{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_MachineState :
(
	START       := 0,  // inicializa o sistema uma única vez
    IDLE        := 1,  // Aguardando condições de início
    READ        := 2,  // Lendo medidor
    CONTROL     := 3,  // Calculando setpoints
    WRITE       := 4,  // Enviando comandos inversores
    FAIL	    := 5,  // Redução forçada (sem trip)
    STOP        := 6,  // Trip + latch (reset manual)
	ERRO		:= 7,  // estado de ERRO - provável erro na configuração ou de parâmetros
	TURNOFF		:= 8   // Desligamento controlado da usina (sem trip)
) UINT;
END_TYPE
