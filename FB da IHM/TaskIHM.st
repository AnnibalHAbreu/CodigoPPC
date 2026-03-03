PROGRAM TaskIHM
VAR
	    fbEventDisplay  		: FB_EventDisplay;			// prepara dados para a IHM

	// ══════════════════════════════════════════════════════════
	// Variáveis manipuladas pela IHM
	// ══════════════════════════════════════════════════════════
 	HMI_bRefresh    		: BOOL;     // Botão "Refresh" na IHM (pulso)
    HMI_nPage       		: UINT;     // Página atual (0 = mais recente)
	
END_VAR

    // Chama o FB de display todo ciclo (ele só recalcula quando HMI_bRefresh der pulso)
    fbEventDisplay(
        pEventLog   := GVL_Main.fbEventLog,     // referência ao ring buffer
        bRefresh    := HMI_bRefresh,   			// pulso da IHM
        nPageOffset := HMI_nPage       			// página selecionada
    );
END_PROGRAM
