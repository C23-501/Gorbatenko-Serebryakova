library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crc16_usb is
  port (
    i_clk   : in  std_logic;
    i_rst   : in  std_logic;
    i_data  : in  std_logic;
    o_data  : out std_logic_vector(15 downto 0)
  );
end crc16_usb;

architecture rtl of crc16_usb is
  signal reg_now  : unsigned(15 downto 0) := (others => '1');
  signal reg_next : unsigned(15 downto 0);
begin

  reg_next <= (('0' & reg_now(15 downto 1)) xor x"A001")
                when (i_data xor reg_now(0)) = '1'
              else ('0' & reg_now(15 downto 1));


  process(i_clk, i_rst)
  begin
    if i_rst = '0' then
      reg_now <= (others => '1');
    elsif rising_edge(i_clk) then
      reg_now <= reg_next;
    end if;
  end process;

  o_data <= std_logic_vector(reg_now xor x"FFFF");

end rtl;

