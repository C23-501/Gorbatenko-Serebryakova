library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity read_shift_reg_tester is
  generic (
    WORD_WIDTH : integer := 16; -- 8, 16, 32, 64
    BURST      : integer := 4   -- 1, 2, 4, 8
  );
end entity;

architecture tb of read_shift_reg_tester is

  constant CLK_PERIOD  : time    := 10 ns;
  constant FRAG_BITS   : integer := WORD_WIDTH * BURST;
  constant NUM_SHIFTS  : integer := (FRAG_BITS + 63) / 64;
  constant WORDS_PER_64: integer := 64 / WORD_WIDTH;

  signal Clk      : std_logic := '0';
  signal nRst     : std_logic := '0';

  signal Load     : std_logic := '0';
  signal Shift    : std_logic := '0';

  signal DataIn   : std_logic_vector(WORD_WIDTH-1 downto 0) := (others => '0');
  signal DataOut  : std_logic_vector(63 downto 0);
  signal Valid    : std_logic;
  signal Done     : std_logic;

begin

  U_DUT : entity work.read_shift_reg
    generic map (
      WORD_WIDTH => WORD_WIDTH,
      BURST      => BURST
    )
    port map (
      Clk      => Clk,
      nRst     => nRst,
      Load     => Load,
      Shift    => Shift,
      DataIn   => DataIn,
      DataOut  => DataOut,
      Valid    => Valid,
      Done     => Done
    );

  p_clk : process
  begin
    Clk <= '0';
    wait for CLK_PERIOD/2;
    Clk <= '1';
    wait for CLK_PERIOD/2;
  end process;

  p_stim : process
  begin
    nRst   <= '0';
    Load   <= '0';
    Shift  <= '0';
    DataIn <= (others => '0');

    wait for 3*CLK_PERIOD;
    nRst <= '1';

    wait until rising_edge(Clk);

    for i in 0 to BURST-1 loop
      Load   <= '1';
      Shift  <= '0';
      DataIn <= conv_std_logic_vector(i, WORD_WIDTH);
      wait until rising_edge(Clk);
    end loop;

    Load <= '0';

    for k in 0 to NUM_SHIFTS-1 loop
      Shift <= '1';
      Load  <= '0';
      wait until rising_edge(Clk);
    end loop;

    Shift <= '0';

    wait for 5*CLK_PERIOD;
    wait;
  end process;

end architecture;
