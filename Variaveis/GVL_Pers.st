{attribute 'qualified_only'}
VAR_GLOBAL PERSISTENT RETAIN

    // CONFIGURAÇÕES DO SISTEMA (Dados que não podem ser perdidos no desligamento)
    
	// Definição do medidor a ser usado
	MeasDeviceType 		: E_MeasDeviceType := E_MeasDeviceType.CHINT_DTSU666;
    
    // Potência nominal (kW) por tipo
    InvActivePower 		: ARRAY[1..GVL_Main.NMAXINVERSORES] OF REAL; 		// kW
    // Potência Aparente Máxima (kVA) por tipo 
    InvSmaxPower 		: ARRAY[1..GVL_Main.NMAXINVERSORES] OF REAL;		// kVA

    // --- Parâmetros de Controle de Exportação ---
    PowerMode 			: UINT := 2;      								// 0=Total, 1=Por Fase, 2=Ambos
	OperationMode		: BOOL := TRUE;									// FALSE=Export Control  TRUE=Zero Grid
	ControlMode			: UINT := 1;									// 0 = manual  1 = automatico (PI ativo)
    TotALARMaxExport_kW : REAL := 0; 									// Limite físico total (kW)
    PhaseMaxExport_kW 	: REAL := 0; 									// Limite físico por fase (kW)

	// Definição do numero de canais em COM1 e COM2
	nChannelsToWriteCOM1	 	: UINT :=2;
	nChannelsToWriteCOM2	 	: UINT :=2;
	
    (* 
	Regra prática para GD solar: Ti entre 5s e 20s. Mais rápido pode oscilar com a latência Modbus. 
	Mais lento perde capacidade de compensar nuvens passando.
	Ti é o Tempo Integral do controlador PI, também chamado de tempo de reset.
	Relação Ki= Kp / Ti   Então se você tem Kp = 1.0 e Ti = 10s => Ki=1.0/10 = 0.1 (por segundo)
	Na prática para seu sistema:
	Ti pequeno (ex: 2s) → integral age rápido → mais agressivo → risco de oscilação
	Ti grande (ex: 30s) → integral age devagar → mais conservador → lento para corrigir erro estacionário
	Ti = 10s → o controlador elimina o erro estacionário em aproximadamente 30 a 40 segundos (≈ 3-4 × Ti)
	Resumo em uma frase:
	Ti = 10s é "quanto tempo o integrador leva para alcançar a mesma força que o proporcional já deu instantaneamente".
	*)
	
	// --- Controle Droop (Potência Ativa) ---
	Droop_Enable     	: BOOL := TRUE;      							// Habilita droop
	K_Droop          	: REAL := 0.15;      							// kW/kW  (ex.: 0.05 = 5% de ganho)
	Deadband_Droop   	: REAL := 2.0;       							// % (erro menor não gera droop)
	Droop_Max        	: REAL := 0.4;       							// Fração da potência instalada (ex.: 0.6 = 60%)
	
	// --- Parâmetros do Controlador PI (Potência Ativa) ---
    Kp_P           		: REAL := 0.25;									// Recomendado: 0.1 a 1.0
																	    // Maior → resposta mais rápida, risco de oscilação
																	    // Menor → mais suave, mas mais lento
    Ki_P           		: REAL := 0.02;									// Recomendado: 0.02 a 0.1 - Com 1s de ciclo e tempo morto ~1,2–1,6s, integral muito alto oscila.
																		// Com T=1s: constante de tempo integral Ti = Kp/Ki = 12,5s
																	    // Significado: elimina erro estacionário em ~10 segundos
																	    // NUNCA > 0.2 com T=1s (oscilação garantida)
	RampUp_P 			: REAL := 15.0;           						// Rampa de subida (kW/s) - limitar a 15-20 kW/s por causa do sweep de setpoints nos inversores
	RampDown_P 			: REAL := 20.0;         						// Rampa de descida (kW/s) - RampDown_P ≤ 20–30 kW/s
    Deadband_P  		: REAL := 1.0;  								// % da potência instalada (ex: 1.0 = 1%)
	
    // --- Configuração de Fator de Potência (PF) e Reativos (Q) ---
    PF_target       	: REAL := 0.92; 								// Alvo |PF|
	PF_sign				: REAL := 1.0;
    // Parâmetros do PI de Correção de Q (Feedforward + Feedback)
    Kp_Q           		: REAL := 50.0;									// Recomendado: 20.0 a 100.0 kvar/pu_PF
																	    // Unidade: kvar por unidade de erro de PF
																	    // Ex: erro PF = 0.02 → P_term = 50 * 0.02 = 1.0 kvar
    Ki_Q           		: REAL := 5.0;									// Recomendado: 2.0 a 10.0 kvar/(pu_PF·s
																	    // Com T=1s: Ti = Kp/Ki = 10s => elimina erro em ~30-40s
																	    // Significado: corrige PF em ~10 segundos	
	RampUp_Q 			: REAL := 50.0;            						// Rampa de subida (kvar/s)
	RampDown_Q 			: REAL := 50.0;          						// Rampa de descida (kvar/s)
	Deadband_Q 			: REAL := 0.01;          						// Zona morta de PF (ex: 0.01 = ±0.01) — padrão para GD

    // --- Histerese de Habilitação ---
    HysteresisOn	   	: REAL := 0.01; 								// Liga controle acima de 1%
    HysteresisOff		: REAL := 0.01; 								// Desliga abaixo de 1%
		
    // --- Agenda Semanal (7 dias x 24 horas) e Datas Especiais
	bHorarioVerao 		: BOOL:= FALSE;									// se TRUE  = Horário de Verão Ativo (+1h)
    WeekSchedule_kW 	: ARRAY[1..7, 1..24] OF REAL; 					// (1=Dom 2=Seg 3=Ter 4=Quarta 5=Quinta 6=Sexta 7=Sábado) em kW
    DatasEspeciais   	: ARRAY[1..GVL_Main.NDATASESPECIAIS] OF DATE;		// inicializa com zeros
	SpecialDaySchedule 	: ARRAY[1..GVL_Main.NDATASESPECIAIS] OF REAL;		// cada data especial tem apenas um valor de potencia maxima valido para o dia inteiro

    // ════════════════════════════════════════════════════════════════
    // LIMITES FÍSICOS DO SISTEMA (Baseados no Transformador e Rede)
    // ════════════════════════════════════════════════════════════════
	// SafetyMargin_kW = SafetyMargin_pct × TC_Power_kW / 100 - Margem de segurança para compensar erro de TC perto de zero
	SafetyMargin_pct 	: REAL := 3.0;     								// Percentual do TC (%)
	// Exemplo 1: TC de 500 A, Tensão 380 V => P_TC = √3 × V × I = 1.732 × 380 × 500 = 329 kW
	TC_Power_kW			: REAL := 0.0; 									// deve ser configurado como 3% da potencia total sob controle pelo TC
	
	VMIN 				: REAL := 7170;  // Volts - tensão de fase minima para tensão primária de 13,8kV
    VMAX 				: REAL := 8370;  // Volts - tensão de fase máxima para tensão primária de 13,8kV
    IMAX 				: REAL := 125.0;  // Amperes - corrente de linha - para potencia de usina de 3MW erro transformador 5%
    PMAX 				: REAL := 3200.0; // kW (Demanda contratada + 10% de margem)
	QMAX				: REAL := 2400.0; // kvar tan(acos(0.8)) × Pmax
	// τ = tempo para atingir ~63% do valor final e T_scan = período de amostragem (1s no seu caso)
	// α = T_scan / (τ + T_scan)  => Alpha=0.5 => 3 segundos para atingir 95% do valor final
	// Item 2.1: "Responder em até 15 segundos a rejeição de carga"
	// Item 2.2: "Limitar exportação em até 15 segundos"
	// Nuvens passageiras: variação em 1–5 segundos
	// Rejeição de carga: instantânea (< 1s)
	// Ruído de medição: < 100 ms
	ALPHA				: REAL := 0.25;
	
END_VAR
