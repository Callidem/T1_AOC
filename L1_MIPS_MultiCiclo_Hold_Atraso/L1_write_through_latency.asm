.data
write_data: .word 0, 0, 0, 0  # 4 palavras que cabem na L1
write_iter: .word 500

.text
main:
    lw $t0, write_iter
    la $s0, write_data
    li $t1, 0
    li $t2, 0x1234           # Dummy data
    
write_penalty_test:
    # Múltiplas escritas no mesmo bloco (hit, mas write-through)
    sw $t2, 0($s0)           # Write-through: 16 ciclos
    sw $t2, 4($s0)           # Write-through: 16 ciclos  
    sw $t2, 8($s0)           # Write-through: 16 ciclos
    sw $t2, 12($s0)          # Write-through: 16 ciclos
    
    addi $t1, $t1, 1
    blt $t1, $t0, write_penalty_test
    
    li $v0, 10
    syscall