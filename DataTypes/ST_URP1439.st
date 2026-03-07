TYPE ST_URP1439 :
	STRUCT
		//  14 variaveis do tipo real - ocupam 28 Words no array
		// variavel       tipo      modbusAddress origem         fator_escala 
		PFa    	    : REAL := 0.0; // 0099H - Valor positivo: 0…16384 × (1/16384) e Valor negativo: 49151…65535 = -((65535 - valor lido) / 16384)
		PFb    	    : REAL := 0.0; // 009AH - Valor positivo: 0…16384 × (1/16384) e Valor negativo: 49151…65535 = -((65535 - valor lido) / 16384)
		PFc    	    : REAL := 0.0; // 009BH - Valor positivo: 0…16384 × (1/16384) e Valor negativo: 49151…65535 = -((65535 - valor lido) / 16384)
		Reserved01  : REAL;        // 009CH - sem informação
		Reserved02  : REAL;        // 009DH - sem informação
		Reserved03  : REAL;        // 009EH - sem informação
		Reserved04  : REAL;        // 009FH - sem informação		
		Ia    	    : REAL := 0.0; // 00A0H - 12…25.600 × (1/256) A (multiplicar por RTC)
		Ib    	    : REAL := 0.0; // 00A1H - 12…25.600 × (1/256) A (multiplicar por RTC)
		Ic    	    : REAL := 0.0; // 00A2H - 12…25.600 × (1/256) A (multiplicar por RTC)	
		Reserved05  : REAL;        // 00A3H - sem informação
		Ua    	    : REAL := 0.0; // 00A4H - 256…64.000 × (1/128) Vca (multiplicar por RTP)
		Ub    	    : REAL := 0.0; // 00A5H - 256…64.000 × (1/128) Vca (multiplicar por RTP)
		Uc    	    : REAL := 0.0; // 00A6H - 256…64.000 × (1/128) Vca (multiplicar por RTP)				
	END_STRUCT
END_TYPE
