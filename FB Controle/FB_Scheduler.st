(*
    FB_Scheduler
    - Agenda semanal: 24 intervalos por dia, 7 dias.
    - Recebe Hora UTC do sistema e converte internamente para LOCAL (Fuso + DST).
    - Feriados/datas especiais sobrescrevem a agenda.
    - Saída: setpoint % da potência instalada.
*)
FUNCTION_BLOCK FB_Scheduler

VAR
    // ════════════════════════════════════════════════════════════
    // VARIÁVEIS DE TIMESTAMP
    // ════════════════════════════════════════════════════════════
    timestampLocal_UDINT 	: UDINT;           		// ✅ Apenas UDINT (sem DINT)
    offsetSeconds 			: DINT;               	// Offset em segundos (pode ser negativo)
    offsetSeconds_ABS 		: UDINT;              	// Valor absoluto do offset
    
    // ════════════════════════════════════════════════════════════
    // CONVERSÕES DE DATA/HORA
    // ════════════════════════════════════════════════════════════
    dtNowLocal 				: DATE_AND_TIME;
    dataNowLocal 			: DATE;
    todNowLocal 			: TOD;
    todAsDword 				: DWORD;
    hora 					: INT;
    diadasemana 			: INT;
	semanaindex 			: BOOL;
    
    // ════════════════════════════════════════════════════════════
    // CACHE DE DATAS ESPECIAIS (Otimização)
    // ════════════════════════════════════════════════════════════
    lastCheckedDate 		: DATE := DATE#1970-01-01;      // Última data verificada
    cachedSpecialDateLimit 	: REAL := -1.0;          // -1 = inválido
    
    // ════════════════════════════════════════════════════════════
    // CACHE DE HORA (Agenda Semanal — Otimização)
    // ════════════════════════════════════════════════════════════
    lastCheckedHour : INT := -1;                    // Última hora processada (-1 = inválido/forçar atualização)
    
	// ════════════════════════════════════════════════════════════
    // AUXILIARES
    // ════════════════════════════════════════════════════════════
    i : UINT;
END_VAR

    
    // ════════════════════════════════════════════════════════════════
    // 1. LEITURA DO RELÓGIO DO SISTEMA (UTC)
    // ════════════════════════════════════════════════════════════════
    
    GVL_Main.timestampUTC := TO_UDINT(SysTimeRtcGet(GVL_Main.Result));
    
    GVL_Alarm.CRIT_RTC_FAIL:=(GVL_Main.Result <> eResultCode.OK);
    IF GVL_Alarm.CRIT_RTC_FAIL THEN
        // ❌ ERRO: Relógio não disponível
        GVL_Main.MaxExportLimit := 0.0;
    	FC_LogEvent(
    		eCode:=E_EventCode.CRIT_RTC_FAILED,
    		bRaised:=TRUE,
    		rParam1:=0.0,
    		rParam2:=0.0,
    		uMachState := GVL_Main.MachineState
    		);
        RETURN;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 2. CÁLCULO DO OFFSET TOTAL (Fuso + Horário de Verão)
    // ════════════════════════════════════════════════════════════════
    
    // Offset base (fuso horário em segundos)
    offsetSeconds := GVL_Main.TIMEZONEOFFSET * 3600;  // Ex: -3 * 3600 = -10800
    
    // Adiciona horário de verão se ativo
    IF GVL_Pers.bHorarioVerao THEN
        offsetSeconds := offsetSeconds + 3600;      // +1 hora
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 3. APLICA OFFSET AO TIMESTAMP UTC
    // ════════════════════════════════════════════════════════════════
    
    // ✅ MÉTODO SEGURO: Usa valor absoluto e subtrai/soma conforme sinal
    offsetSeconds_ABS := DINT_TO_UDINT(ABS(offsetSeconds));
    
    IF offsetSeconds < 0 THEN
        // Fuso NEGATIVO (Américas): subtrai
        timestampLocal_UDINT := GVL_Main.timestampUTC - offsetSeconds_ABS;
    ELSE
        // Fuso POSITIVO (Europa, Ásia): soma
        timestampLocal_UDINT := GVL_Main.timestampUTC + offsetSeconds_ABS;
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 4. CONVERTE TIMESTAMP PARA DATA/HORA LOCAL
    // ════════════════════════════════════════════════════════════════
    
    dtNowLocal := UDINT_TO_DT(timestampLocal_UDINT);
    dataNowLocal := TO_DATE(dtNowLocal);
    
    // Extrai hora (0..23)
    todNowLocal := DT_TO_TOD(dtNowLocal);
    todAsDword := TOD_TO_DWORD(todNowLocal);
    hora := DWORD_TO_INT(todAsDword / DWORD#3600000);
    
    // Extrai dia da semana (1=Dom .. 7=Sáb)
    diadasemana := UDINT_TO_INT(((timestampLocal_UDINT / 86400) + 4) MOD 7) + 1;
    
    // ════════════════════════════���═══════════════════════════════════
    // 5. VERIFICA MUDANÇA DE DATA (Para atualizar cache)
    // ════════════════════════════════════════════════════════════════
    
    IF dataNowLocal <> lastCheckedDate THEN
    	
    	lastCheckedDate := dataNowLocal;
    	cachedSpecialDateLimit := -1.0;  // Invalida cache de data especial
    	lastCheckedHour := -1;           // ✅ Invalida cache de hora (nova data = nova agenda semanal)
    	
    	FOR i := 1 TO GVL_Main.NDATASESPECIAIS DO
    		
    		// ✅ OTIMIZAÇÃO: Early exit se encontrar data vazia
    		IF GVL_Pers.DatasEspeciais[i] = DATE#1970-01-01 THEN
    			EXIT;  // Resto do array está vazio
    		END_IF
    		
    		// Verifica se é data especial — log emitido aqui (uma vez por mudança de data)
    		IF GVL_Pers.DatasEspeciais[i] = dataNowLocal THEN
    			cachedSpecialDateLimit := GVL_Pers.SpecialDaySchedule[i];
    			FC_LogEvent(
    				eCode:=E_EventCode.INFO_SPECIAL_DATE_ACTIVE,
    				bRaised:=TRUE,
    				rParam1:=0.0,
    				rParam2:=0.0,
    				uMachState := GVL_Main.MachineState
    				);
    			EXIT;  // Encontrou, pára a busca
    		END_IF
    		
    	END_FOR
    	
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 6. USA CACHE DE DATA ESPECIAL (Se válido)
    // ════════════════════════════════════════════════════════════════
    
    IF cachedSpecialDateLimit >= 0.0 THEN
    	// Data especial ativa — limite já definido, log já emitido na seção 5
    	GVL_Main.MaxExportLimit := cachedSpecialDateLimit;
    	RETURN;	// Se é data especial, não olha agenda semanal
    END_IF
    
    // ════════════════════════════════════════════════════════════════
    // 7. AGENDA SEMANAL (Hora Local)
    // ════════════════════════════════════════════════════════════════
    
    // ✅ VALIDAÇÃO: Verifica se índices estão dentro dos limites
    semanaindex:= (diadasemana >= 1 AND diadasemana <= 7) AND (hora >= 0 AND hora <= 23);
    GVL_Alarm.CRIT_SCHEDULE_INDEX_INVALID:= NOT semanaindex;
    
    IF semanaindex THEN
    	
    	// ✅ CACHE DE HORA: Só atualiza limite se a hora mudou desde a última leitura
    	IF hora <> lastCheckedHour THEN
    		lastCheckedHour := hora;
    		GVL_Main.MaxExportLimit := GVL_Pers.WeekSchedule_kW[diadasemana, hora + 1];
    	END_IF
    
    ELSE	// ❌ ERRO: Índice inválido (não deveria ocorrer)
    	lastCheckedHour := -1;  // Invalida cache para forçar releitura quando índice voltar a ser válido
    	GVL_Main.MaxExportLimit := 0.0;
    	FC_LogEvent(
    		eCode:=E_EventCode.CRIT_SCHEDULE_INDEX_INVALID,
    		bRaised:=TRUE,
    		rParam1:=0.0,
    		rParam2:=0.0,
    		uMachState := GVL_Main.MachineState
    		);
    	
    END_IF
END_FUNCTION_BLOCK
