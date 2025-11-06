# Trabalho 1
- Implementação de um sistema de gerenciamento da hierarquia de memória
- Descrito em VHDL
- Simulado no MIPS

## Hierarquia
### Processador
- address out 32b
- control out 1b
- Status in 1b
- data inout 32b
- Envia sinais para L1 

#### Cache L1
- Processador
    - data inout 32b
    - address in 32b
    - control in 1b
    - status out 1b
- Envia sinais para MP
    - data inout 32b
    - address out 32b
    - control out 1b
    - status in 1b
- 8 linhas 8 palavras de 4 bytes
- Mapeamento direto
- Write-through
- Mesma frequência do processador
    - Acesso com 1 ciclo de relógio, borda invertida
- MP com tempo de 16 ciclos


#### FSM 
- addLine, endereço da linha
- addBlock, endereço do bloco dentro da linha
- leitura de bv e tag para dar hit

#### Process Wait
- Hold para CPU
- Recebe hit/miss da FSM
- recebe accessData do processador




##### Memória Principal

