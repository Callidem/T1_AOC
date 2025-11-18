-------------------------------------------------------------------------
--
--
--considerando hold e quando e 1 pra segurar e o resto e borda de descida pq fds

--ajeitar todos os acesos a memory pq bloco downto bloco -32

--falta todo o write tbm;

--cache miss falta:
--write da intrucao e bit de validade
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
      generic(WORD: integer := 32; 
              BLOCK_SIZE: integer := 8;
              NUM_LINES: integer := 8;
              LINE_SIZE: integer := 1+26+32*8-1
             );
      -- calculo do tamanho da linha (bit_de_validade + tag + tamanho_da_palavra*BLOCK_SIZE - 1)

      port( data_io:   inout std_logic_vector(31 downto 0); -- dado a ser ecrito ou a ser enviado
            addr_i:    in    std_logic_vector(31 downto 0); -- endereco do dado
            ce_i:      in    std_logic; -- chip enable
            we_i:      in    std_logic; -- write enable
            oe_i:      in    std_logic; -- read enable
            hold_i:    in    std_logic;
            clk:       in    std_logic;
            rst:       in    std_logic;
            -- fio para comunicacao com a proxima memoria
            hold_o:      out   std_logic;
            addr_o:    out   std_logic_vector(31 downto 0); -- endereco do dado
            ce_o:      out   std_logic; -- chip enable proxima memoria
            oe_o:      out   std_logic; -- read enable proxima memoria
            we_o:      out   std_logic  -- write enable proxima memoria

            ); -- 1 out esta pronto, 0 em operacao
end;

architecture cache of cache is

  type cache_state is (idle, read, write, cache_miss);
  type cache_memory is array(0 to NUM_LINES-1) of std_logic_vector(LINE_SIZE-1 downto 0);

  signal memory:  cache_memory;
  signal state:   cache_state;
  signal tag:     integer;
  signal bloco:   integer;
  signal linha:   integer;
  signal aux:     integer; -- ate agr so ultilizado no cache miss para count do bloco

  signal ce: std_logic;

begin

  -- transforma em int para usar em index
  tag     <= CONV_INTEGER(addr_i(31 downto 6));
  bloco   <= CONV_INTEGER(addr_i(5 downto 3));
  linha   <= CONV_INTEGER(addr_i(2 downto 0));

  ce      <= hold and ce_i; -- TODO n sei se tem q ta em zero essa porra AAAAAAAAA

  fsm: process(clk, rst)
  begin
    if rst = '1' then
      state    <= idle;
      aux      <=  0;

      for i in 0 to NUM_LINES loop
            memory(i)(LINE_SIZE) <= '0'; -- zera bit de validade
      end loop;

      -- falta coisa ainda

    else

      if ce = '1' then -- se ce_i e hold liberarem ele vai TODO
        case state is
          when idle =>
            if we_i = '0' then -- fonte ram mips.... linha 152
              state <= write;
            end if;

            if oe_i = '0' then -- fonte ram mips.... linha 167
              state <= read;
            end if;

          when read =>

            if (tag /= memory(linha)(31 downto 6)) and (memory(linha)(LINE_SIZE) = '1') then -- compara tag, e se memoria for valida, caso cache miss
              state <= cache_miss;
            else
              data_io <= memory(linha)((bloco + 1)*32 -1 downto bloco * 32);
            end if;

          when write =>

            if (tag /= memory(linha)(31 downto 6)) and (memory(linha)(LINE_SIZE) = '1') then -- compara tag, e se memoria for valida, caso cache miss
              state <= cache_miss;
            end if;

          when cache_miss =>
            if aux = 7 then
              if we_i = '0' then -- fonte ram mips.... linha 152
                state <= write;
              end if;

              if oe_i = '0' then -- fonte ram mips.... linha 167
                state <= read;
              end if;
            end if;

            addr_o(31 downto 3) <= addr_i(31 downto 3);
            addr_o(2 downto 0)  <= std_logic_vector(CONV_INTEGER(aux)); -- TODO
            aux <= aux + 1;

        end case;

      end if;
    end if;
  end process fsm;

end cache;
