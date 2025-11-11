--------------------------------------------------------------------------
-- M�dulo que implementa um modelo comportamental de uma Cache L1
-- com interface ass�ncrona (sem clock)
--------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity L1_Cache is
    generic(  START_ADDRESS: std_logic_vector(31 downto 0) := (others=>'0');
            ADDR_WIDTH  : integer := 32;
            DATA_WIDTH  : integer := 32;
            CACHE_LINE_SIZE_WORDS : integer := 8; -- número de palavras por linha de cache
            NUM_CACHE_LINES : integer := 8  -- número de linhas na cache
            );
    port( --portas CPU-CACHE
        clk, rst: in std_logic;
        cpu_ce: in std_logic; -- chip enable from CPU (uins.ce)
        cpu_addr: in std_logic_vector(ADDR_WIDTH-1 downto 0);
        cpu_data: inout std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_rw: in std_logic; -- '1' = read, '0' = write (match MIPS_S uins.rw)
        cpu_bw: in std_logic; -- byte write enable: '1' = full-word write, '0' = byte write (matches testbench RAM semantics)
        cpu_hold: out std_logic; -- conectar a hold do MIPS_S
        -- instrumentation outputs
        hit_count_out : out integer := 0;
        miss_count_out : out integer := 0;
        stall_cycles_out : out integer := 0;
        --portas CACHE-MP (active-high control signals)
        mem_addr: out std_logic_vector(ADDR_WIDTH-1 downto 0);
        mem_clk, mem_rst : in std_logic; -- (pode usar mesmo clk)
        mem_data : inout std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_write_en, mem_read_en : out std_logic; -- ativa escrita/leitura na MP (ativa ALTA)
        mem_status : in std_logic --busy signal (0 = pronto, 1 = ocupado)
        );
end L1_Cache;


architecture Behavioral of L1_Cache is

    -- Calcular larguras dos campos
    -- byte offset (2 bits for word addressing) + word offset (n bits for words per line)
    constant BYTE_OFFSET_BITS : integer := 2; -- offset inside a 32-bit word
    constant OFFSET_WORD_BITS : integer := integer(ceil(log2(real(CACHE_LINE_SIZE_WORDS))));
    constant TOTAL_OFFSET_BITS : integer := BYTE_OFFSET_BITS + OFFSET_WORD_BITS;
    constant INDEX_BITS  : integer := integer(ceil(log2(real(NUM_CACHE_LINES))));
    constant TAG_BITS    : integer := ADDR_WIDTH - INDEX_BITS - TOTAL_OFFSET_BITS;

    -- Tipos para as memórias internas da cache
    type T_DATA_CACHE_ARRAY is array (0 to NUM_CACHE_LINES-1) of std_logic_vector( (DATA_WIDTH * CACHE_LINE_SIZE_WORDS) - 1 downto 0);
    type T_TAG_CACHE_ARRAY is array (0 to NUM_CACHE_LINES-1) of std_logic_vector(TAG_BITS-1 downto 0);

    -- Sinais para as memórias internas
    signal s_data_cache : T_DATA_CACHE_ARRAY;
    signal s_tag_cache  : T_TAG_CACHE_ARRAY;
    signal s_valid_bits : std_logic_vector(NUM_CACHE_LINES-1 downto 0) := (others => '0');

    -- Sinais para decompor o endereço da CPU
    signal s_tag    : std_logic_vector(TAG_BITS-1 downto 0);
    signal s_index  : std_logic_vector(INDEX_BITS-1 downto 0);
    signal s_word_offset : std_logic_vector(OFFSET_WORD_BITS-1 downto 0);
    signal s_byte_offset : std_logic_vector(BYTE_OFFSET_BITS-1 downto 0);
    
    -- Sinais de controle e estado
    type T_STATE is (IDLE, COMPARE, MEM_READ_FETCH, MEM_WRITE);
    signal s_current_state : T_STATE := IDLE;
    
    signal s_hit : std_logic;

    -- internal default outputs
    signal s_cpu_data_drive : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
    signal s_cpu_drive_en : std_logic := '0';
    -- driver para mem_data (tri-state safe)
    signal s_mem_data_drive : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => 'Z');
    -- counters
    signal s_hit_count : integer := 0;
    signal s_miss_count : integer := 0;
    signal s_stall_cycles : integer := 0;
    -- sinais para fetch sequencial e write-allocate
    signal s_fetch_idx : integer := 0;
    signal s_fetch_base : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal s_pending_write : std_logic := '0';
    signal s_pending_data : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal s_pending_addr : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    -- Safe helpers to avoid arithmetic on vectors containing 'U'/'X'/'Z'
    function bits_are_valid(v: std_logic_vector) return boolean is
    begin
        for i in v'range loop
            if v(i) /= '0' and v(i) /= '1' then
                return false;
            end if;
        end loop;
        return true;
    end function;

    function safe_to_integer(v: std_logic_vector) return integer is
    begin
        if bits_are_valid(v) then
            return to_integer(unsigned(v));
        else
            return 0;
        end if;
    end function;

begin
    -- Decomposição do endereço (lógica combinacional)
    -- decompor endereço: [tag | index | word_offset | byte_offset]
    s_tag    <= cpu_addr(ADDR_WIDTH-1 downto ADDR_WIDTH - TAG_BITS);
    s_index  <= cpu_addr(ADDR_WIDTH - TAG_BITS - 1 downto BYTE_OFFSET_BITS + OFFSET_WORD_BITS);
    s_word_offset <= cpu_addr(BYTE_OFFSET_BITS + OFFSET_WORD_BITS - 1 downto BYTE_OFFSET_BITS);
    s_byte_offset <= cpu_addr(BYTE_OFFSET_BITS-1 downto 0);

    -- Lógica principal da Cache (processo sequencial)
    process(clk, rst)
        variable v_index_int : integer;
        variable v_tag_from_cache : std_logic_vector(TAG_BITS-1 downto 0);
        variable v_cache_line : std_logic_vector((DATA_WIDTH * CACHE_LINE_SIZE_WORDS) - 1 downto 0);
        variable v_word_idx : integer;
        variable v_word_old, v_word_new : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable v_hi, v_lo : integer;
    begin
        if rst = '1' then
            s_current_state <= IDLE;
            cpu_hold <= '0';
            s_valid_bits <= (others => '0');
            -- Outras inicializações...
            s_cpu_drive_en <= '0';
            s_hit_count <= 0;
            s_miss_count <= 0;
            s_stall_cycles <= 0;
            s_mem_data_drive <= (others => 'Z');
        elsif rising_edge(clk) then

            -- contar ciclos de stall
            if cpu_hold = '1' then
                s_stall_cycles <= s_stall_cycles + 1;
            end if;

            -- Máquina de estados
            case s_current_state is
                
                -- Estado de espera
                when IDLE =>
                    cpu_hold <= '0';
                    mem_read_en <= '0';
                    mem_write_en <= '0';
                    s_cpu_drive_en <= '0';
                    -- Detectar requisição da CPU: quando cpu_ce='1' (uins.ce) há uma operação
                    if cpu_ce = '1' then
                        s_current_state <= COMPARE;
                    end if;

                -- Estado de comparação (Hit ou Miss?)
                when COMPARE =>
                    v_index_int := safe_to_integer(s_index);
                    v_tag_from_cache := s_tag_cache(v_index_int);

                    -- Lógica de Hit
                    if s_valid_bits(v_index_int) = '1' and v_tag_from_cache = s_tag then
                        s_hit <= '1';
                        -- HIT!
                        if cpu_rw = '1' then -- É uma leitura (Read Hit) (cpu_rw: '1' = read)
                            -- Ler da cache e entregar para a CPU
                            v_cache_line := s_data_cache(v_index_int);
                            v_word_idx := safe_to_integer(s_word_offset);
                            v_hi := (v_word_idx+1) * DATA_WIDTH - 1;
                            v_lo := v_word_idx * DATA_WIDTH;
                            v_word_old := v_cache_line(v_hi downto v_lo);
                            -- drive CPU data output
                            s_cpu_data_drive <= v_word_old;
                            s_cpu_drive_en <= '1';
                                s_hit_count <= s_hit_count + 1;
                            s_current_state <= IDLE;
                        else -- É uma escrita (Write Hit) (cpu_rw='0')
                            -- Ler linha atual
                            v_cache_line := s_data_cache(v_index_int);
                                v_word_idx := safe_to_integer(s_word_offset);
                            v_hi := (v_word_idx+1) * DATA_WIDTH - 1;
                            v_lo := v_word_idx * DATA_WIDTH;
                            v_word_old := v_cache_line(v_hi downto v_lo);
                            -- Se cpu_bw = '1' atualiza palavra inteira; else atualiza apenas byte menos-significativo
                            if cpu_bw = '1' then
                                v_word_new := cpu_data;
                            else
                                v_word_new := v_word_old;
                                v_word_new(7 downto 0) := cpu_data(7 downto 0);
                            end if;
                            -- Atualiza a linha na posição correta
                            v_cache_line(v_hi downto v_lo) := v_word_new;
                            s_data_cache(v_index_int) <= v_cache_line;
                            -- Iniciar escrita na memória principal (Write-Through)
                            mem_write_en <= '1';
                            mem_addr <= cpu_addr;
                                s_mem_data_drive <= cpu_data;
                            s_current_state <= MEM_WRITE;
                        end if;
                    else
                        -- MISS!
                        s_hit <= '0';
                        cpu_hold <= '1'; -- Pausar a CPU
                            s_miss_count <= s_miss_count + 1;

                        -- preparar base do bloco (offset de palavra + byte = 0)
                        s_fetch_base <= s_tag & s_index & (TOTAL_OFFSET_BITS-1 downto 0 => '0');
                        s_fetch_idx <= 0;
                        -- se for escrita, salvar dado pendente (write-allocate)
                        if cpu_rw = '0' then
                            s_pending_write <= '1';
                            s_pending_data <= cpu_data;
                            s_pending_addr <= cpu_addr;
                        else
                            s_pending_write <= '0';
                        end if;

                        -- iniciar leitura sequencial da primeira palavra do bloco
                        mem_addr <= s_fetch_base;
                        mem_read_en <= '1';
                        s_current_state <= MEM_READ_FETCH;
                    end if;

                -- Estado de busca na memória (após um Miss)
                when MEM_READ_FETCH =>
                    -- leitura sequencial de linhas (word-a-word)
                    if mem_status = '0' then
                        v_index_int := safe_to_integer(s_index);
                        v_cache_line := s_data_cache(v_index_int);
                        -- escreve a palavra retornada na posicao s_fetch_idx
                        v_word_idx := s_fetch_idx;
                        v_hi := (v_word_idx+1) * DATA_WIDTH - 1;
                        v_lo := v_word_idx * DATA_WIDTH;
                        v_word_new := mem_data;
                        v_cache_line(v_hi downto v_lo) := v_word_new;
                        s_data_cache(v_index_int) <= v_cache_line;

                        -- incrementar contador e decidir proximo passo
                        if s_fetch_idx < CACHE_LINE_SIZE_WORDS - 1 then
                            s_fetch_idx <= s_fetch_idx + 1;
                            -- avançar endereço de leitura em 4 bytes (próxima palavra)
                            if bits_are_valid(mem_addr) then
                                mem_addr <= std_logic_vector(unsigned(mem_addr) + 4);
                            else
                                mem_addr <= (others => '0');
                            end if;
                            mem_read_en <= '1'; -- manter leitura
                            s_current_state <= MEM_READ_FETCH;
                        else
                            -- completou o preenchimento da linha
                            s_tag_cache(v_index_int)   <= s_tag;
                            s_valid_bits(v_index_int)  <= '1';
                            mem_read_en <= '0';

                            -- se havia uma escrita pendente (write-allocate), aplica-a agora
                            if s_pending_write = '1' then
                                -- atualiza a palavra correta dentro da linha
                                v_word_idx := to_integer(unsigned(s_word_offset));
                                v_hi := (v_word_idx+1) * DATA_WIDTH - 1;
                                v_lo := v_word_idx * DATA_WIDTH;
                                v_cache_line := s_data_cache(v_index_int);
                                -- se cpu_bw = '1' (full-word) usamos s_pending_data, senão atualizamos apenas byte LSB
                                if cpu_bw = '1' then
                                    v_word_new := s_pending_data;
                                else
                                    v_word_new := v_cache_line(v_hi downto v_lo);
                                    v_word_new(7 downto 0) := s_pending_data(7 downto 0);
                                end if;
                                v_cache_line(v_hi downto v_lo) := v_word_new;
                                s_data_cache(v_index_int) <= v_cache_line;
                                -- iniciar escrita write-through para a palavra solicitada
                                mem_write_en <= '1';
                                mem_addr <= s_pending_addr;
                                s_mem_data_drive <= s_pending_data;
                                s_pending_write <= '0';
                                s_current_state <= MEM_WRITE;
                            else
                                -- sem escrita pendente: libera CPU
                                cpu_hold <= '0';
                                s_current_state <= COMPARE;
                            end if;
                        end if;
                    end if;

                -- Estado de escrita na memória (após um Write Hit)
                when MEM_WRITE =>
                    if mem_status = '0' then
                        mem_write_en <= '0';
                        s_current_state <= IDLE;
                    end if;

            end case;
        end if;
    end process;
    
    -- Lógica combinacional para leitura da cache (exemplo simplificado)
    -- A leitura real acontece no ciclo de hit dentro do processo
    -- cpu_data_out <= ...;

    -- Tri-state driver para o barramento CPU: drive quando habilitado por uma leitura hit
    cpu_data <= s_cpu_data_drive when s_cpu_drive_en = '1' else (others => 'Z');

    -- Tri-state driver para o barramento memória: somente dirigir mem_data quando mem_write_en ativo
    mem_data <= s_mem_data_drive when mem_write_en = '1' else (others => 'Z');

    -- drive instrumentation outputs
    hit_count_out <= s_hit_count;
    miss_count_out <= s_miss_count;
    stall_cycles_out <= s_stall_cycles;

end architecture Behavioral;