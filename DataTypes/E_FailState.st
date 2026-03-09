{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_FailState :
(
    FS_INIT         := 0,  // Inicialização FAIL_SAFE
    FS_FORCE_ZERO   := 1,  // Forçar setpoint zero
    FS_VALIDATE     := 2   // Validar geração zero
) UINT;
END_TYPE
