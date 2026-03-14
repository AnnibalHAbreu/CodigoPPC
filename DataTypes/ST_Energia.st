TYPE ST_Energia :
	STRUCT
		// variavel       tipo      modbusAddress origem         fator_escala 
		EAImp  : REAL := 0.0; // 101EH - energia ativa total positiva (kWh)
		Vazia1 : REAL := 0.0; // 1020H - void
		Vazia2 : REAL := 0.0; // 1022H - void
		Vazia3 : REAL := 0.0; // 1024H - void
		Vazia4 : REAL := 0.0; // 1026H - void
		EAExp  : REAL := 0.0; // 1028H - energia ativa total negativa (kWh)	
	END_STRUCT
END_TYPE
