PROGRAM TaskIHM
VAR
	fbEventDisplay  		: FB_EventDisplay;			// prepara dados para a IHM
    fbSetRTC        		: FB_SetRTC;       			// set RTC
	
	// ══════════════════════════════════════════════════════════
	// Variáveis manipuladas pela IHM
	// ══════════════════════════════════════════════════════════
 	HMI_bRefresh    		: BOOL;     // Botão "Refresh" na IHM (pulso)
    HMI_nPage       		: UINT;     // Página atual (0 = mais recente)
	
	    // ── Variáveis de correção de RTC (expostas na tela "Config" da IHM) ───────
    HMI_RTC_Set         : BOOL;           // Botão "Aplicar" na IHM (pulso)
    HMI_RTC_Year        : UINT := 2026;   // Campo: Ano   (pré-preenchido com ano atual)
    HMI_RTC_Month       : UINT := 1;      // Campo: Mês
    HMI_RTC_Day         : UINT := 1;      // Campo: Dia
    HMI_RTC_Hour        : UINT := 0;      // Campo: Hora  (UTC — sem offset de fuso)
    HMI_RTC_Minute      : UINT := 0;      // Campo: Minuto
    HMI_RTC_Second      : UINT := 0;      // Campo: Segundo

    // ── Feedback (somente leitura na IHM) ────────────────────────────────────
    HMI_RTC_Busy        : BOOL;           // Indicador de operação em andamento
    HMI_RTC_Success     : BOOL;           // Verde: sucesso
    HMI_RTC_Error       : BOOL;           // Vermelho: falha
    HMI_RTC_ErrorCode   : UINT;           // Código numérico do erro
    HMI_RTC_StatusMsg   : STRING(40);     // Mensagem de status
	
END_VAR

        // ── Display de eventos ────────────────────────────────────────────────────
        fbEventDisplay(
            pEventLog   := GVL_Main.fbEventLog,
            bRefresh    := HMI_bRefresh,
            nPageOffset := HMI_nPage
        );
    
        // ── Correção de RTC ───────────────────────────────────────────────────────
        fbSetRTC(
            bSet        := HMI_RTC_Set,
            nYear       := HMI_RTC_Year,
            nMonth      := HMI_RTC_Month,
            nDay        := HMI_RTC_Day,
            nHour       := HMI_RTC_Hour,
            nMinute     := HMI_RTC_Minute,
            nSecond     := HMI_RTC_Second,
            bBusy       => HMI_RTC_Busy,
            bSuccess    => HMI_RTC_Success,
            bError      => HMI_RTC_Error,
            nErrorCode  => HMI_RTC_ErrorCode,
            sStatusMsg  => HMI_RTC_StatusMsg
        );
    
        // Auto-reset do botão após borda consumida pelo FB
        IF HMI_RTC_Set AND (HMI_RTC_Busy OR HMI_RTC_Success OR HMI_RTC_Error) THEN
            HMI_RTC_Set := FALSE;
        END_IF
    
    (*
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      3. NOTAS DE COMISSIONAMENTO
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
      a) A hora informada na IHM deve ser UTC (não hora local).
         O FB_Scheduler aplica o offset de fuso (TIMEZONEOFFSET) internamente.
         Exemplo: se o horário local é 11:30 (UTC-3), digitar 14:30 na IHM.
    
      b) Se preferir que o operador informe hora local, subtrair o offset antes
         de chamar fbSetRTC. Isso pode ser feito na própria task IHM:
           HMI_RTC_Hour_UTC := (HMI_RTC_Hour_Local - GVL_Main.TIMEZONEOFFSET + 24) MOD 24;
         (cuidado com virada de data ao subtrair)
    
      c) Após corrigir o RTC, o FB_Scheduler irá reler o horário no próximo ciclo
         normalmente — nenhuma ação adicional é necessária.
    
      d) O WAGO CC100 (751-9402) suporta módulo de bateria RTC externo (750-650).
         Recomenda-se fortemente instalá-lo para eliminar a necessidade de
         reconfigurar data/hora após toda queda de energia.
    
      e) Alternativa a este FB para produção: sincronização via NTP (protocolo
         SNTP disponível no Codesys V3.5 com SysClock.library). Mais robusto
         que correção manual, mas requer rede disponível no campo.
    *)
END_PROGRAM
