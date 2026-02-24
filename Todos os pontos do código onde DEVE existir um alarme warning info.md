### **1.1 — FB\_Startup**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 1 | stSeriais | COM1 ou COM2 não fica RUNNING | CRITICAL | ❌ Só comentário // dispara Alarme |
| 2 | stInit | Global.Result \<\> eResultCode.OK (RTC falhou) | CRITICAL | ⚠️ Só K8ErroOut:=TRUE |
| 3 | stInit | InstalledPower \<= 0 | CRITICAL | ⚠️ Só K8ErroOut:=TRUE |
| 4 | stInit | TC\_Power\_kW \= 0 (não configurado) | WARNING | ⚠️ Só K8ErroOut:=TRUE |
| 5 | stWait\_K1 | K1 ativado com sucesso | INFO | ❌ |
| 6 | stWait\_K2 | K2 ativado com sucesso | INFO | ❌ |
| 7 | stDone | Startup completo | INFO | ❌ |
| 8 | stWait\_K1 | K1 não responde (falta timeout\!) | CRITICAL | ❌ Bug: não há timeout |

### **1.2 — FB\_ReadMedidor**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 9 | WAIT | xDone \+ dados OK | INFO | ❌ |
| 10 | WAIT | xError (erro Modbus) | ALARM | ⚠️ Só fbAlarmes(codigo) → sMessage |
| 11 | WAIT | tonTimer.Q (timeout) | ALARM | ⚠️ Só fbAlarmes(16\#B2) |

### **1.3 — FB\_ValidaDadosRele**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 12 | Range | Tensão fora de faixa (A/B/C) | ALARM | ⚠️ Só diagnosticCode \+ bRangeError |
| 13 | Range | Corrente fora de faixa (A/B/C) | ALARM | ⚠️ Idem |
| 14 | Range | Potência ativa fora de faixa | ALARM | ⚠️ Idem |
| 15 | Range | Potência reativa fora de faixa | ALARM | ⚠️ Idem |
| 16 | Range | PF fora de faixa | ALARM | ⚠️ Idem |
| 17 | Cross-check | Pa ≠ Ua×Ia×PFa | WARNING | ⚠️ Idem |
| 18 | Cross-check | Pt ≠ Pa+Pb+Pc | WARNING | ⚠️ Idem |
| 19 | Cross-check | PFt inconsistente com P/S | WARNING | ⚠️ Idem |
| 20 | Freeze | Medição congelada \>THRESHOLD | ALARM | ⚠️ Idem |
| 21 | Erro acumulado | nErrors \>= 5 → degradação | CRITICAL | ⚠️ Só bPoucosErros := FALSE |

### **1.4 — FB\_WriteInv**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 22 | WAIT | Escrita OK (xDone) | INFO | ❌ |
| 23 | WAIT | Erro Modbus na escrita | ALARM | ⚠️ Só fbAlarmes(codigo) |
| 24 | WAIT | Timeout escrita | ALARM | ⚠️ Só fbAlarmes(16\#B2) |

### **1.5 — FB\_Controle**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 25 | Início | InstalledPower \<= 0 | CRITICAL | ⚠️ RETURN silencioso |
| 26 | Início | InstalledSmax \<= 0 | CRITICAL | ⚠️ RETURN silencioso |
| 27 | PAlloc | P alocado \< P comandado (saturação) | WARNING | ❌ |
| 28 | QAlloc | Q limitado por Smax | WARNING | ⚠️ Via bQ\_limit\_reached |
| 29 | PF | PF \< target (não atingível) | WARNING | ⚠️ Via bPF\_OK |

### **1.6 — FB\_Scheduler**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 30 | RTC | Falha leitura RTC | CRITICAL | ⚠️ Só K8ErroOut |
| 31 | Agenda | Índice dia/hora inválido | CRITICAL | ⚠️ Só K8ErroOut |
| 32 | Agenda | Data especial ativa | INFO | ⚠️ Só sMessage |

### **1.7 — MainProgram — Máquina de Estados**

| \# | Local | Condição | Severidade | Existe hoje? |
| ----- | ----- | ----- | ----- | ----- |
| 33 | READ | MedidorOK \+ dados OK → CONTROL | INFO | ❌ |
| 34 | READ | Dados inválidos mas poucos erros | WARNING | ⚠️ Só sMessage |
| 35 | READ | Falha persistente medição → FAIL | CRITICAL | ⚠️ FaultCode:=16\#C1 |
| 36 | READ | Erro/Timeout Modbus → FAIL | CRITICAL | ⚠️ FaultCode:=16\#C2 |
| 37 | CONTROL | InstalledPower \= 0 → STOP | CRITICAL | ⚠️ K8ErroOut |
| 38 | WRITE | Canal COM1 \>50% falhas | CRITICAL | ⚠️ FaultCode:=16\#C2 |
| 39 | WRITE | Canal COM2 \>50% falhas | CRITICAL | ⚠️ Idem |
| 40 | WRITE | Erro individual inversor | WARNING | ❌ Só incrementa contador |
| 41 | IDLE | Scan overrun (\>tolerância) | WARNING | ⚠️ Só ScanOverrunCount++ |
| 42 | IDLE | Watchdog (3× overrun) → FAIL | CRITICAL | ⚠️ FaultCode:=16\#F1 |
| 43 | FAIL | Hard-limit \>15s → STOP | CRITICAL | ⚠️ FaultCode:=16\#E1 |
| 44 | FAIL | Exportação \>LPI \>30s → STOP | CRITICAL | ⚠️ FaultCode:=16\#E2 |
| 45 | FAIL | Timeout medidor em FAIL \>30s → STOP | CRITICAL | ⚠️ FaultCode:=16\#E3 |
| 46 | FAIL | Recuperação automática | INFO | ⚠️ Só sMessage |
| 47 | FAIL→STOP | Transição FAIL→STOP | CRITICAL | ❌ Não registra explicitamente |
| 48 | STOP | Entrada em STOP (trip K2) | CRITICAL | ⚠️ Só sinalização K3/K4/K5 |
| 49 | STOP | K2 não abriu após 2s | CRITICAL | ⚠️ FaultCode:=16\#E2 \+ FaultLatch |
| 50 | STOP | K2 confirmado aberto | INFO | ⚠️ Só sMessage |
| 51 | STOP | Reset manual negado | WARNING | ⚠️ Só sMessage |
| 52 | STOP | Reset manual aprovado | INFO | ⚠️ Só sMessage |
| 53 | STOP | Aguardando Pt estável | INFO | ⚠️ Só sMessage |
| 54 | Transição | Qualquer mudança de estado | INFO | ❌ |

### **1.8 — Pontos AUSENTES no código que DEVERIAM existir**

| \# | Local | Condição | Severidade | Risco |
| ----- | ----- | ----- | ----- | ----- |
| 55 | FB\_Startup | Timeout em stWait\_K1 (K1 nunca responde) | CRITICAL | Trava o sistema |
| 56 | FB\_Startup | Timeout em stSeriais (serial nunca abre) | CRITICAL | Trava o sistema |
| 57 | MainProgram | Estado E\_MachineState.ERROR nunca é usado | WARNING | Estado morto |
| 58 | MainProgram | ELSE default no CASE principal | CRITICAL | Corrupção de MachineState |
| 59 | FB\_FFQ | Q\_target calculado mas nunca atribuído a Q\_reactive\_kvar | BUG | Q feedforward sempre 0 |
| 60 | Geral | Transição de ComOK para NOT ComOK | ALARM | Não registrada |
| 61 | Geral | Transição de MedidorOK para NOT MedidorOK | ALARM | Não registrada |

