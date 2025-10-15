architecture Behavioral of L1_Cache is

    -- Calcular larguras dos campos
    constant OFFSET_BITS : integer := integer(ceil(log2(real(CACHE_LINE_SIZE_WORDS))));
    constant INDEX_BITS  : integer := integer(ceil(log2(real(NUM_CACHE_LINES))));
    constant TAG_BITS    : integer := ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

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
    signal s_offset : std_logic_vector(OFFSET_BITS-1 downto 0);
    
    -- Sinais de controle e estado
    type T_STATE is (IDLE, COMPARE, MEM_READ_FETCH, MEM_WRITE);
    signal s_current_state : T_STATE := IDLE;
    
    signal s_hit : std_logic;

begin

    -- Decomposição do endereço (lógica combinacional)
    s_tag    <= cpu_addr(ADDR_WIDTH-1 downto ADDR_WIDTH - TAG_BITS);
    s_index  <= cpu_addr(ADDR_WIDTH - TAG_BITS - 1 downto OFFSET_BITS);
    s_offset <= cpu_addr(OFFSET_BITS-1 downto 0);

    -- Lógica principal da Cache (processo sequencial)
    process(clk, rst)
        variable v_index_int : integer;
        variable v_tag_from_cache : std_logic_vector(TAG_BITS-1 downto 0);
        variable v_cache_line : std_logic_vector((DATA_WIDTH * CACHE_LINE_SIZE_WORDS) - 1 downto 0);
    begin
        if rst = '1' then
            s_current_state <= IDLE;
            cpu_stall <= '0';
            s_valid_bits <= (others => '0');
            -- Outras inicializações...
        elsif rising_edge(clk) then

            -- Máquina de estados
            case s_current_state is
                
                -- Estado de espera
                when IDLE =>
                    cpu_stall <= '0';
                    mem_read_en <= '0';
                    mem_write_en <= '0';
                    if cpu_write_en = '1' or (cpu_write_en = '0' and cpu_addr'event) then -- Requisição de leitura ou escrita
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
                        if cpu_write_en = '0' then -- É uma leitura (Read Hit)
                            -- Ler da cache e entregar para a CPU
                            v_cache_line := s_data_cache(v_index_int);
                            -- Seleciona a palavra correta com base no offset
                            -- Esta lógica precisa ser mais elaborada para selecionar a palavra certa
                            -- cpu_data_out <= ... v_cache_line com s_offset ...;
                            s_current_state <= IDLE;
                        else -- É uma escrita (Write Hit)
                            -- Atualizar a cache
                            -- s_data_cache(v_index_int) <= ...; (atualiza a palavra certa)
                            -- Iniciar escrita na memória principal (Write-Through)
                            mem_write_en <= '1';
                            mem_addr <= cpu_addr;
                            mem_data_out <= cpu_data_in;
                            s_current_state <= MEM_WRITE;
                        end if;
                    else
                        -- MISS!
                        s_hit <= '0';
                        cpu_stall <= '1'; -- Pausar a CPU
                        
                        -- Iniciar busca do bloco na memória principal
                        mem_read_en <= '1';
                        -- O endereço para a memória é o da tag e do índice, com offset zerado
                        mem_addr <= s_tag & s_index & (OFFSET_BITS-1 downto 0 => '0'); 
                        s_current_state <= MEM_READ_FETCH;
                    end if;

                -- Estado de busca na memória (após um Miss)
                when MEM_READ_FETCH =>
                    if mem_busy = '0' then
                        -- Memória entregou o dado. Escrevê-lo na cache.
                        v_index_int := to_integer(unsigned(s_index));
                        -- Assumindo que a memória entrega o bloco inteiro
                        -- s_data_cache(v_index_int) <= mem_data_in; -- (requer uma interface de barramento)
                        s_tag_cache(v_index_int)   <= s_tag;
                        s_valid_bits(v_index_int)  <= '1';
                        
                        -- Libera a CPU e volta a comparar (agora será um hit)
                        cpu_stall <= '0';
                        mem_read_en <= '0';
                        s_current_state <= COMPARE; 
                    end if;

                -- Estado de escrita na memória (após um Write Hit)
                when MEM_WRITE =>
                    if mem_busy = '0' then
                        mem_write_en <= '0';
                        s_current_state <= IDLE;
                    end if;

            end case;
        end if;
    end process;
    
    -- Lógica combinacional para leitura da cache (exemplo simplificado)
    -- A leitura real acontece no ciclo de hit dentro do processo
    -- cpu_data_out <= ...;

end architecture Behavioral;