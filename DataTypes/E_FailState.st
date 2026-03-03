{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_FailState :
(
    FS_INIT         := 0,  // Inicialização FAIL_SAFE
    FS_FORCE_ZERO   := 1,  // Forçar setpoint zero
    FS_WAIT_CONFIRM := 2,  // Aguardar confirmação escrita
    FS_VALIDATE     := 3,  // Validar geração zero
    FS_ESCALATE     := 4   // Escalar para STOP
) UINT;
END_TYPE
