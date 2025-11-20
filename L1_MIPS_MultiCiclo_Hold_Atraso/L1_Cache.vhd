--------------------------------------------------------------------------
-- M�dulo que implementa um modelo comportamental de uma Cache L1
-- com interface ass�ncrona (sem clock)
--------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity L1_Cache is
    generic(  START_ADDRESS: std_logic_vector(31 downto 0) := (others=>'0');
            ADDR_WIDTH  : integer := 32;
            DATA_WIDTH  : integer := 32;
            CACHE_LINE_SIZE_WORDS : integer := 8; -- palavras por linha
            NUM_CACHE_LINES : integer := 8  -- linhas na cache
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
        mem_clk, mem_rst : in std_logic; -- pode usar mesmo `clk`
        mem_data : inout std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_write_en, mem_read_en : out std_logic; -- ativa escrita/leitura na MP (ativa ALTA)
        mem_status : in std_logic -- busy signal (0 = pronto, 1 = ocupado)
        );
end L1_Cache;


architecture Behavioral of L1_Cache is

    -- Simplified direct-mapped cache parameters
    constant BYTE_OFFSET_BITS : integer := 2; -- byte offset inside word

    -- integer ceiling of log2 (small helper used for static constants)
    function clog2(n: integer) return integer is
        variable k: integer := 0;
        variable v: integer := 1;
    begin
        while v < n loop
            v := v * 2;
            k := k + 1;
        end loop;
        return k;
    end function;

    constant OFFSET_WORD_BITS : integer := clog2(CACHE_LINE_SIZE_WORDS);
    constant TOTAL_OFFSET_BITS : integer := BYTE_OFFSET_BITS + OFFSET_WORD_BITS;
    constant INDEX_BITS  : integer := clog2(NUM_CACHE_LINES);
    constant TAG_BITS    : integer := ADDR_WIDTH - INDEX_BITS - TOTAL_OFFSET_BITS;

    type T_DATA_LINE is array (0 to CACHE_LINE_SIZE_WORDS-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    type T_DATA_CACHE_ARRAY is array (0 to NUM_CACHE_LINES-1) of T_DATA_LINE;
    type T_TAG_CACHE_ARRAY is array (0 to NUM_CACHE_LINES-1) of std_logic_vector(TAG_BITS-1 downto 0);

    signal s_data_cache : T_DATA_CACHE_ARRAY;
    signal s_tag_cache  : T_TAG_CACHE_ARRAY;
    signal s_valid_bits : std_logic_vector(NUM_CACHE_LINES-1 downto 0) := (others => '0');

    signal s_tag    : std_logic_vector(TAG_BITS-1 downto 0);
    signal s_index  : std_logic_vector(INDEX_BITS-1 downto 0);
    signal s_word_offset : std_logic_vector(OFFSET_WORD_BITS-1 downto 0);

    type T_STATE is (IDLE, COMPARE, FETCH, WAIT_WRITE);
    signal s_current_state : T_STATE := IDLE;

    signal cpu_hold_o : std_logic := '0';
    signal mem_write_en_o : std_logic := '0';
    signal mem_read_en_o : std_logic := '0';
    signal mem_addr_o : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others=>'0');
    signal s_cpu_data_drive : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
    signal s_cpu_drive_en : std_logic := '0';
    signal s_mem_data_drive : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => 'Z');

    signal s_fetch_idx : integer range 0 to CACHE_LINE_SIZE_WORDS-1 := 0;
    signal s_hit_count : integer := 0;
    signal s_miss_count : integer := 0;
    signal s_stall_cycles : integer := 0;
    -- pending write signals for simple write-allocate
    signal s_pending_write : std_logic := '0';
    signal s_pending_data  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal s_pending_addr  : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal s_pending_bw    : std_logic := '1';

begin
    -- Decomposição do endereço (lógica combinacional)
    s_tag    <= cpu_addr(ADDR_WIDTH-1 downto ADDR_WIDTH - TAG_BITS);
    s_index  <= cpu_addr(ADDR_WIDTH - TAG_BITS - 1 downto BYTE_OFFSET_BITS + OFFSET_WORD_BITS);
    s_word_offset <= cpu_addr(BYTE_OFFSET_BITS + OFFSET_WORD_BITS - 1 downto BYTE_OFFSET_BITS);

    -- Main simplified FSM
    process(clk, rst)
        variable v_idx : integer := 0;
        variable v_word_idx : integer := 0;
    begin
        if rst = '1' then
            s_current_state <= IDLE;
            cpu_hold_o <= '0';
            s_valid_bits <= (others => '0');
            s_cpu_drive_en <= '0';
            s_hit_count <= 0;
            s_miss_count <= 0;
            s_stall_cycles <= 0;
            s_mem_data_drive <= (others => 'Z');
            mem_read_en_o <= '0';
            mem_write_en_o <= '0';
            mem_addr_o <= (others => '0');
            s_fetch_idx <= 0;
            -- clear pending write on reset
            s_pending_write <= '0';
            s_pending_data  <= (others => '0');
            s_pending_addr  <= (others => '0');
            s_pending_bw    <= '1';
        elsif rising_edge(clk) then
            if cpu_hold_o = '1' then
                s_stall_cycles <= s_stall_cycles + 1;
            end if;

            -- defaults
            s_cpu_drive_en <= '0';
            mem_read_en_o <= '0';
            mem_write_en_o <= '0';
            s_mem_data_drive <= (others => 'Z');

            case s_current_state is
                when IDLE =>
                    cpu_hold_o <= '0';
                    if cpu_ce = '1' then
                        s_current_state <= COMPARE;
                    end if;

                when COMPARE =>
                    v_idx := to_integer(unsigned(s_index));
                    if s_valid_bits(v_idx) = '1' and s_tag_cache(v_idx) = s_tag then
                        -- HIT
                        s_hit_count <= s_hit_count + 1;
                        if cpu_rw = '1' then -- read
                            v_word_idx := to_integer(unsigned(s_word_offset));
                            s_cpu_data_drive <= s_data_cache(v_idx)(v_word_idx);
                            s_cpu_drive_en <= '1';
                            s_current_state <= IDLE;
                        else -- write hit: update cache and write-through
                            v_word_idx := to_integer(unsigned(s_word_offset));
                            if cpu_bw = '1' then
                                s_data_cache(v_idx)(v_word_idx) <= cpu_data;
                            else
                                -- only update LSB byte
                                s_data_cache(v_idx)(v_word_idx)(7 downto 0) <= cpu_data(7 downto 0);
                            end if;
                            mem_write_en_o <= '1';
                            mem_addr_o <= cpu_addr;
                            s_mem_data_drive <= cpu_data;
                            cpu_hold_o <= '1';
                            s_current_state <= WAIT_WRITE;
                        end if;
                    else
                        -- MISS
                        s_miss_count <= s_miss_count + 1;
                        cpu_hold_o <= '1';
                        if cpu_rw = '1' then
                            -- read miss: fetch entire line word-by-word
                            s_fetch_idx <= 0;
                            -- align address to line base: zero lower TOTAL_OFFSET_BITS
                            mem_addr_o <= cpu_addr(ADDR_WIDTH-1 downto TOTAL_OFFSET_BITS) & (TOTAL_OFFSET_BITS-1 downto 0 => '0');
                            mem_read_en_o <= '1';
                            s_current_state <= FETCH;
                        else
                            -- write miss: simple write-allocate
                            s_pending_write <= '1';
                            s_pending_data  <= cpu_data;
                            s_pending_addr  <= cpu_addr;
                            s_pending_bw    <= cpu_bw;
                            -- start fetching the block from memory (line base)
                            s_fetch_idx <= 0;
                            mem_addr_o <= cpu_addr(ADDR_WIDTH-1 downto TOTAL_OFFSET_BITS) & (TOTAL_OFFSET_BITS-1 downto 0 => '0');
                            mem_read_en_o <= '1';
                            s_current_state <= FETCH;
                        end if;
                    end if;

                when FETCH =>
                    -- wait mem to present the next word on mem_data (mem_status='0' when ready)
                    if mem_status = '0' then
                        v_idx := to_integer(unsigned(s_index));
                        s_data_cache(v_idx)(s_fetch_idx) <= mem_data;
                        if s_fetch_idx < CACHE_LINE_SIZE_WORDS-1 then
                            s_fetch_idx <= s_fetch_idx + 1;
                            mem_addr_o <= std_logic_vector(unsigned(mem_addr_o) + 4);
                            mem_read_en_o <= '1';
                        else
                            -- finished line
                            s_tag_cache(v_idx) <= s_tag;
                            s_valid_bits(v_idx) <= '1';
                            mem_read_en_o <= '0';
                            -- if there was a pending write (write-allocate), apply it now
                            if s_pending_write = '1' then
                                -- update the correct word inside the fetched line
                                v_word_idx := to_integer(unsigned(s_word_offset));
                                if s_pending_bw = '1' then
                                    s_data_cache(v_idx)(v_word_idx) <= s_pending_data;
                                else
                                    s_data_cache(v_idx)(v_word_idx)(7 downto 0) <= s_pending_data(7 downto 0);
                                end if;
                                -- initiate write-through of the requested word to MP
                                mem_write_en_o <= '1';
                                mem_addr_o <= s_pending_addr;
                                s_mem_data_drive <= s_pending_data;
                                s_pending_write <= '0';
                                s_current_state <= WAIT_WRITE;
                            else
                                cpu_hold_o <= '0';
                                s_current_state <= COMPARE;
                            end if;
                        end if;
                    end if;

                when WAIT_WRITE =>
                    if mem_status = '0' then
                        mem_write_en_o <= '0';
                        s_mem_data_drive <= (others => 'Z');
                        cpu_hold_o <= '0';
                        s_current_state <= IDLE;
                    end if;

                when others =>
                    s_current_state <= IDLE;
            end case;
        end if;
    end process;

    -- outputs
    cpu_hold <= cpu_hold_o;
    mem_write_en <= mem_write_en_o;
    mem_read_en <= mem_read_en_o;
    mem_addr <= mem_addr_o;

    cpu_data <= s_cpu_data_drive when s_cpu_drive_en = '1' else (others => 'Z');
    mem_data <= s_mem_data_drive when mem_write_en_o = '1' else (others => 'Z');

    hit_count_out <= s_hit_count;
    miss_count_out <= s_miss_count;
    stall_cycles_out <= s_stall_cycles;

end architecture Behavioral;
