{attribute 'strict'}
TYPE E_ModbusResult :
(
    BUSY,   		// operação em andamento
    DONE,   		// leitura finalizada com sucesso (pulso curto)
    ERRO,   		// ocorreu erro superior ao maximo permitido
	ABORT,			// comunicação foi abortada
	TIMEOUT,		// ocorreu timeout superior ao maximo permitido
	END				// finaliza a comunicação
);
END_TYPE
