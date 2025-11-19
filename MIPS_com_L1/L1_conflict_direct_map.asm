.data
    .align 8
conflict_addr0: .word 0xAAAA
    .space 248               # Padding até 256 bytes
conflict_addr1: .word 0xBBBB  
    .space 248
conflict_addr2: .word 0xCCCC
    .space 248
conflict_addr3: .word 0xDDDD
    .space 248
conflict_addr4: .word 0xEEEE
    .space 248
conflict_addr5: .word 0xFFFF
    .space 248
conflict_addr6: .word 0x1111
    .space 248
conflict_addr7: .word 0x2222
    .space 248
conflict_addr8: .word 0x3333

loop_count: .word 100

.text
main:
    lw $t0, loop_count
    li $t1, 0
    
conflict_loop:
    # Acesso cíclico a endereços com mesmo índice
    lw $t2, conflict_addr0   # Mesma linha cache (256 bytes apart)
    lw $t3, conflict_addr1   # Conflict miss!
    lw $t4, conflict_addr2   # Conflict miss!
    lw $t5, conflict_addr3   # Conflict miss!
    lw $t6, conflict_addr4   # Conflict miss!
    lw $t7, conflict_addr5   # Conflict miss!
    lw $t8, conflict_addr6   # Conflict miss!
    lw $t9, conflict_addr7   # Conflict miss!
    
    addi $t1, $t1, 1
    blt $t1, $t0, conflict_loop
    
    li $v0, 10
    syscall