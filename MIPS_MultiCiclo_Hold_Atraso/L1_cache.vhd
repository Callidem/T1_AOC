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
      generic(  START_ADDRESS: wires32 := (others=>'0')  );
      port( ce_n, we_n, oe_n, bw: in std_logic;
            add_in, status_in, control_in : in wires32;
            add_out, status_out, control_out: out wires32;
            data: inout wires32);
end L1_Cache;

architecture L1_Cache of L1_Cache is 
   signal RAM : memory;
   signal tmp_address: wires32;
   alias  low_address: wires16 is tmp_address(15 downto 0);    --  baixa para 16 bits, devido ao CONV_INTEGER --
begin     

   tmp_address <= address - START_ADDRESS;   --  offset do endereamento  -- 
   
   -- escrita ass�ncrona na mem�ria  -- LITTLE ENDIAN -------------------
   process(ce_n, we_n, low_address) -- Modifica��o em 16/05/2012 para uso
                                    -- processadores monociclo apenas
     begin
       if ce_n='0' and we_n='0' then
          if CONV_INTEGER(low_address)>=0 and CONV_INTEGER(low_address)<=MEMORY_SIZE-3 then
               if bw='1' then
                   RAM(CONV_INTEGER(low_address+3)) <= data(31 downto 24);
                   RAM(CONV_INTEGER(low_address+2)) <= data(23 downto 16);
                   RAM(CONV_INTEGER(low_address+1)) <= data(15 downto  8);
               end if;
               RAM(CONV_INTEGER(low_address  )) <= data( 7 downto  0); 
          end if;
         end if;   
    end process;   
    
   -- leitura da mem�ria
   process(ce_n, oe_n, low_address)
     begin
       if ce_n='0' and oe_n='0' and
          CONV_INTEGER(low_address)>=0 and CONV_INTEGER(low_address)<=MEMORY_SIZE-3 then
            data(31 downto 24) <= RAM(CONV_INTEGER(low_address+3));
            data(23 downto 16) <= RAM(CONV_INTEGER(low_address+2));
            data(15 downto  8) <= RAM(CONV_INTEGER(low_address+1));
            data( 7 downto  0) <= RAM(CONV_INTEGER(low_address  ));
        else
            data(31 downto 24) <= (others=>'Z');
            data(23 downto 16) <= (others=>'Z');
            data(15 downto  8) <= (others=>'Z');
            data( 7 downto  0) <= (others=>'Z');
        end if;
   end process;   

end L1_Cache;

