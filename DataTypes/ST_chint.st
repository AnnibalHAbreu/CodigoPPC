TYPE ST_chint :
	STRUCT
		//  22 variaveis do tipo real - ocupam 44 Words no array
		// variavel       tipo      modbusAddress origem         fator_escala 
		Ua    	    : REAL := 0.0; // 2006H - Tensão de fase A x 0,1 V
		Ub    	    : REAL := 0.0; // 2008H - Tensão de fase B x 0,1 V
		Uc    	    : REAL := 0.0; // 200AH - Tensão de fase C x 0,1 V
		Ia    	    : REAL := 0.0; // 200CH - Corrente de fase A x 0,001 A 
		Ib    	    : REAL := 0.0; // 200EH - Corrente de fase B x 0,001 A
		Ic    	    : REAL := 0.0; // 2010H - Corrente de fase C x 0,001 A
		Pt    	    : REAL := 0.0; // 2012H - Potencia ativa combinada x 0,1 W
		Pa    	    : REAL := 0.0; // 2014H - Potencia ativa fase A x 0,1 W
		Pb    	    : REAL := 0.0; // 2016H - Potencia ativa fase B x 0,1 W
		Pc    	    : REAL := 0.0; // 2018H - Potencia ativa fase C x 0,1 W	
		Qt    	    : REAL := 0.0; // 201AH - Potencia reativa combinada x 0,1 var
		Qa    	    : REAL := 0.0; // 201CH - Potencia reativa fase A x 0,1 var
		Qb    	    : REAL := 0.0; // 201EH - Potencia reativa fase B x 0,1 var
		Qc    	    : REAL := 0.0; // 2020H - Potencia reativa fase C x 0,1 var
		Reserved01  : REAL;        // 2022H - sem informação
		Reserved02  : REAL;        // 2024H - sem informação
		Reserved03  : REAL;        // 2026H - sem informação
		Reserved04  : REAL;        // 2028H - sem informação
		PFt    	    : REAL := 0.0; // 202AH - Fator de potência combinado (número positivo: indutivo, número negativo: capacitivo) (x  0,001)
		PFa    	    : REAL := 0.0; // 202CH - Fator de potência de fase A (número positivo: indutivo, número negativo: capacitivo)  (×0,001)
		PFb    	    : REAL := 0.0; // 202EH - Fator de potência de fase B (número positivo: indutivo, número negativo: capacitivo)  (×0,001)
		PFc    	    : REAL := 0.0; // 2030H - Fator de potência de fase C (número positivo: indutivo, número negativo: capacitivo)  (×0,001)
	END_STRUCT
END_TYPE
