{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_StopState :
(
    STOP_INIT       := 0,  // Inicialização STOP
    STOP_TRIP		:= 1,  // Verifica se disjuntor abriu
    STOP_LATCHED	:= 2  // Prende no estado STOP até reset do operador
) UINT;
END_TYPE
