.data
small_array: .word 0x1000, 0x2000, 0x3000, 0x4000  # 4 palavras em meio bloco
iterations:  .word 1000

.text
main:
    lw $t0, iterations        # Carrega contador
    la $s0, small_array       # Base do array pequeno
    li $t1, 0                 # Contador de loop
    
temporal_loop:
    # Acessa as mesmas 4 palavras repetidamente
    lw $t2, 0($s0)           # Hit após miss inicial
    lw $t3, 4($s0)           # Hit
    lw $t4, 8($s0)           # Hit  
    lw $t5, 12($s0)          # Hit
    
    addi $t1, $t1, 1         # Incrementa contador
    blt $t1, $t0, temporal_loop  # Repete 1000x
    
    li $v0, 10               # Exit
    syscall