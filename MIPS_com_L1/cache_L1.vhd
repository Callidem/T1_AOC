-------------------------------------------------------------------------
--
--
--
--
-- formato do enderecamento:
--         26(31..6) bits       3(5..3) 3(2..0)
-- | -------------------------- | --- | --- |
--            tag                linha  bloco


-----------------------------------------------------------------------
--    CACHE L1
-----------------------------------------------------------------------
library IEEE;
use IEEE.Std_Logic_1164.all;
use IEEE.Std_Logic_unsigned.all;

entity cache is
      generic(word: integer := 32);
      generic(block_size: integer := 8);
      generic(num_lines: integer := 8);
      generic(line_size: integer := 1+26+8*block_size-1);
      -- calculo do tamanho da linha (bit_de_validade + tag + num_blocos*block_size - 1)

      port( data_io:   inout std_logic_vector(31 downto 0); -- dado a ser ecrito ou a ser enviado
            addr_i:    in    std_logic_vector(31 downto 0); -- endereco do dado
            control_i: in    std_logic; -- 1 write 0 read
            clk:       in    std_logic;
            rst:       in    std_logic;
            ce_i:      in    std_logic;
            ce_o:      out   std_logic;
            status_o:  out   std_logic); -- se operacao esta em andamento TODO
end;

architecture cache of cache is

  type cache_state is (idle, read, write, cache_miss);
  type cache_memory is array(0 to num_lines) of std_logic_vector(line_size downto 0);

  signal memory: cache_memory;
  signal state:  cache_state;
  signal tag:    integer;
  signal bloco:  integer;
  signal linha:  integer;

begin

  tag   <= to_integer(unsigned(addr_i(31 downto 6)));
  bloco <= to_integer(unsigned(addr_i(5 downto 3)));
  linha <= to_integer(unsigned(addr_i(2 downto 0)));

  fsm: process(clk, rst)
  begin
    if rst then
      for i in 0 to num_lines loop
            cache_memory(i)(line_size) <= '0';
      end loop;
      status_o < '0';
      -- falta coisa ainda

    else

      case state is
        when idle =>
          if ce_i = '1' and control_i = '1' then -- TODO cipa tem q mudar o control ver modulo do processador pra isso
            state <= write;
          end if;

          if ce_i = '1' and control_i = '0' then -- TODO cipa tem q mudar o control
            state <= read;
          end if;

        when read =>
          if tag /= memory(linha)(31 downto 6) then -- compara tag, caso cache miss
            state <= cache_miss;
          end if;

        when write =>

        when cache_miss =>

      end case;

    end if;
  end process fsm;

end cache;
