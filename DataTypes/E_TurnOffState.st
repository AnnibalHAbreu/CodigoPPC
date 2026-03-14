{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_TurnOffState :
(
    TO_INIT         := 0,  // Inicialização: zera setpoints, prepara escrita
    TO_WRITE_ZERO   := 1,  // Envia setpoint zero via Modbus a todos inversores
    TO_VERIFY       := 2,  // Lê medidor e verifica se geração caiu a ~0
    TO_DISCONNECT   := 3,  // Desativa K1 e aciona K2 (trip controlado)
    TO_CONFIRM      := 4,  // Aguarda confirmação de abertura de K2 (contato aux)
    TO_DONE         := 5   // Desligamento concluído, aguarda reset manual
) UINT;
END_TYPE
