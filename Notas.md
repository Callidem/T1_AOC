# Trabalho 1
- Implementação de um sistema de gerenciamento da hierarquia de memória
- Descrito em VHDL
- Simulado no MIPS

## Hierarquia
### Processador
- Porta de endereço
- Porta de controle
- Porta de Status
- Porta de dados ou instruções 
- Envia sinais para L1

#### Cache L1
- Envia sinais para MP
- 8 linhas 8 palavras de 4 bytes

#### FSM 
- addLine, endereço da linha
- addBlock, endereço do bloco dentro da linha
- leitura de bv e tag para dar hit

#### Process Wait
- Hold para CPU
- Recebe hit/miss da FSM
- recebe accessData do processador




##### Memória Principal

