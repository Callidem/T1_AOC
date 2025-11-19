.data
big_array:   .space 320      # 80 palavras (10 blocos, excede 64 palavras)
re_read_size: .word 16       # Quantidade para reler

.text
main:
    la $s0, big_array
    lw $t0, re_read_size
    
    # Primeira passagem - preenche cache
    li $t1, 0
first_pass:
    sll $t2, $t1, 2
    add $t3, $s0, $t2
    sw $t1, 0($t3)           # Escreve valor
    addi $t1, $t1, 1
    blt $t1, 80, first_pass   # 80 palavras
    
    # Segunda passagem - tenta reler dados ejetados
    li $t1, 0
second_pass:
    sll $t2, $t1, 2
    add $t3, $s0, $t2
    lw $t4, 0($t3)           # Miss por capacidade!
    addi $t1, $t1, 1
    blt $t1, $t0, second_pass
    
    li $v0, 10
    syscall