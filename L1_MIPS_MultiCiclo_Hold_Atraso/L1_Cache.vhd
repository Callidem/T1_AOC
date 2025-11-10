--------------------------------------------------------------------------
-- M�dulo que implementa um modelo comportamental de uma Cache L1
-- com interface ass�ncrona (sem clock)
--------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.STD_LOGIC_UNSIGNED.all;
use std.textio.all;
use work.aux_functions.all;

entity L1_Cache is
      generic(  START_ADDRESS: std_logic_vector(31 downto 0) := (others=>'0'),
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
        elsif rising_edge(clk) then

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
                    v_index_int := to_integer(unsigned(s_index));
                    v_tag_from_cache := s_tag_cache(v_index_int);

                    -- Lógica de Hit
                    if s_valid_bits(v_index_int) = '1' and v_tag_from_cache = s_tag then
                        s_hit <= '1';
                        -- HIT!
                        if cpu_rw = '1' then -- É uma leitura (Read Hit) (cpu_rw: '1' = read)
                            -- Ler da cache e entregar para a CPU
                            v_cache_line := s_data_cache(v_index_int);
                            v_word_idx := to_integer(unsigned(s_word_offset));
                            v_hi := (v_word_idx+1) * DATA_WIDTH - 1;
                            v_lo := v_word_idx * DATA_WIDTH;
                            v_word_old := v_cache_line(v_hi downto v_lo);
                            -- drive CPU data output
                            s_cpu_data_drive <= v_word_old;
                            s_cpu_drive_en <= '1';
                            s_current_state <= IDLE;
                        else -- É uma escrita (Write Hit) (cpu_rw='0')
                            -- Ler linha atual
                            v_cache_line := s_data_cache(v_index_int);
                            v_word_idx := to_integer(unsigned(s_word_offset));
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
                            mem_data <= cpu_data;
                            s_current_state <= MEM_WRITE;
                        end if;
                    else
                        -- MISS!
                        s_hit <= '0';
                        cpu_hold <= '1'; -- Pausar a CPU
                        
                        -- Iniciar busca do bloco na memória principal
                        mem_read_en <= '1';
                        -- O endereço para a memória é o da tag e do índice, com offset zerado
                        -- montar endereço base do bloco (offset de palavra + byte = 0)
                        mem_addr <= s_tag & s_index & (TOTAL_OFFSET_BITS-1 downto 0 => '0'); 
                        s_current_state <= MEM_READ_FETCH;
                    end if;

                -- Estado de busca na memória (após um Miss)
                when MEM_READ_FETCH =>
                    if mem_status = '0' then
                        -- Memória entregou o dado (assume por enquanto que mem_data traz a palavra requisitada).
                        v_index_int := to_integer(unsigned(s_index));
                        -- Nota: implementação completa de fetch por palavras ainda é necessária (ITEM 3).
                        -- Aqui faremos um preenchimento simples assumindo que mem_data contém a palavra zero do bloco.
                        v_cache_line := s_data_cache(v_index_int);
                        -- escreve a palavra retornada na posição indicada por s_word_offset
                        v_word_idx := to_integer(unsigned(s_word_offset));
                        v_hi := (v_word_idx+1) * DATA_WIDTH - 1;
                        v_lo := v_word_idx * DATA_WIDTH;
                        v_word_new := mem_data;
                        v_cache_line(v_hi downto v_lo) := v_word_new;
                        s_data_cache(v_index_int) <= v_cache_line; -- parcial
                        s_tag_cache(v_index_int)   <= s_tag;
                        s_valid_bits(v_index_int)  <= '1';

                        -- Libera a CPU e volta a comparar (agora será um hit)
                        cpu_hold <= '0';
                        mem_read_en <= '0';
                        s_current_state <= COMPARE; 
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

end architecture Behavioral;