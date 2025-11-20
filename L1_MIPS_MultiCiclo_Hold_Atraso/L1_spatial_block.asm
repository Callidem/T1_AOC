.data
large_array: .space 256       # 64 palavras (excede capacidade cache)
array_size:  .word 64

.text
main:
    lw $t0, array_size       # Tamanho do array
    la $s0, large_array      # Base do array
    li $t1, 0                # Índice
    
spatial_loop:
    sll $t2, $t1, 2          # Calcula offset (i * 4)
    add $t3, $s0, $t2        # Endereço atual
    lw $t4, 0($t3)           # Acesso sequencial
    
    addi $t1, $t1, 1         # Próxima palavra (Stride=1)
    blt $t1, $t0, spatial_loop
    
    li $v0, 10               # Exit
    syscall