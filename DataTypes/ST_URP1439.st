TYPE ST_URP1439 :
	STRUCT
		//  14 variaveis do tipo UINT - ocupam 14 Words no array
		// variavel       tipo      modbusAddress origem         fator_escala 
		PFa    	    : UINT := 0; // 0099H - Valor positivo: 0…16384 × (1/16384) e Valor negativo: 49151…65535 = -((65535 - valor lido) / 16384)
		PFb    	    : UINT := 0; // 009AH - Valor positivo: 0…16384 × (1/16384) e Valor negativo: 49151…65535 = -((65535 - valor lido) / 16384)
		PFc    	    : UINT := 0; // 009BH - Valor positivo: 0…16384 × (1/16384) e Valor negativo: 49151…65535 = -((65535 - valor lido) / 16384)
		Reserved01  : UINT;      // 009CH - sem informação
		Reserved02  : UINT;      // 009DH - sem informação
		Reserved03  : UINT;      // 009EH - sem informação
		Reserved04  : UINT;      // 009FH - sem informação		
		Ia    	    : UINT := 0; // 00A0H - 12…25.600 × (1/256) A (multiplicar por RTC)
		Ib    	    : UINT := 0; // 00A1H - 12…25.600 × (1/256) A (multiplicar por RTC)
		Ic    	    : UINT := 0; // 00A2H - 12…25.600 × (1/256) A (multiplicar por RTC)	
		Reserved05  : UINT;      // 00A3H - sem informação
		Ua    	    : UINT := 0; // 00A4H - 256…64.000 × (1/128) Vca (multiplicar por RTP)
		Ub    	    : UINT := 0; // 00A5H - 256…64.000 × (1/128) Vca (multiplicar por RTP)
		Uc    	    : UINT := 0; // 00A6H - 256…64.000 × (1/128) Vca (multiplicar por RTP)				
	END_STRUCT
END_TYPE
