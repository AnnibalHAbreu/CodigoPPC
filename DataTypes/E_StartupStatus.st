{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_StartupStatus :
(
  stInit,			(* inicializa variaveis *)
  stWait_K1,      	(* transição imediata quando o delay completa *)
  stWait_K2,       	(* mantém bK3_out; monitora bK2_in com debounce *)
  stDone,           (* sucesso: desliga bK3_out e liga bK4_out *)
  stError           (* erro: sinaliza e coloca saídas em estado seguro *)
);
END_TYPE
