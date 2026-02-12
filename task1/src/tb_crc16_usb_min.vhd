library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_crc16_usb_min is
end tb_crc16_usb_min;

architecture sim of tb_crc16_usb_min is
  signal i_clk      : std_logic := '0';
  signal i_rst   : std_logic := '1';
  signal i_data : std_logic := '0';
  signal o_data  : std_logic_vector(15 downto 0);

  constant CLK_PERIOD : time := 10 ns;
begin

  uut : entity work.crc16_usb
    port map (
      i_clk      => i_clk,
      i_rst   => i_rst,
      i_data => i_data,
      o_data  => o_data
    );

  clk_proc : process
  begin
    loop
      i_clk <= '0'; wait for CLK_PERIOD/2;
      i_clk <= '1'; wait for CLK_PERIOD/2;
    end loop;
  end process clk_proc;

  stim_proc : process
  begin
    i_rst <= '0'; wait for 25 ns;
    i_rst <= '1'; wait for 2 * CLK_PERIOD;

    for i in 0 to 7 loop
      i_data <= '0';
      wait until rising_edge(i_clk);
    end loop;

    for i in 0 to 7 loop
      i_data <= '1';
      wait until rising_edge(i_clk);
    end loop;

    wait for 5 * CLK_PERIOD;

    report "SIM: o_data = " & to_hstring(o_data) severity note;

    assert FALSE report "End of simulation" severity FAILURE;

    wait;
  end process stim_proc;

end architecture sim;
