library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity write_shift_reg_tester is
  generic (
    WORD_WIDTH : integer := 16;
    BURST      : integer := 4
  );
end entity;

architecture tb of write_shift_reg_tester is

  constant CLK_PERIOD   : time    := 10 ns;
  constant FRAG_BITS  : integer := WORD_WIDTH * BURST;
  constant WORDS_PER_64 : integer := 64 / WORD_WIDTH;

  function calc_num_frags return integer is
  begin
    if FRAG_BITS = 0 then
      return 1;
    elsif FRAG_BITS >= 64 then
      return 1;
    else
      return 64 / FRAG_BITS;
    end if;
  end function;

  constant NUM_FRAGS : integer := calc_num_frags;

  type t_idx_array is array (0 to 7) of std_logic_vector(2 downto 0);
  constant IDX_TABLE : t_idx_array := (
    "000", "001", "010", "011",
    "100", "101", "110", "111"
  );

  constant DATA_TEMPLATE : std_logic_vector(63 downto 0) :=
    x"0123456789ABCDEF";

  type t_be_array is array (natural range <>) of std_logic_vector(7 downto 0);

  constant BE_PATTERNS : t_be_array := (
    "11111111",
    "00111111",
    "11111000",
    "01111100"
  );

  signal Clk    : std_logic := '0';
  signal nRst   : std_logic := '0';

  signal Load   : std_logic := '0';
  signal Shift  : std_logic := '0';

  signal Idx    : std_logic_vector(2 downto 0) := (others => '0');
  signal ByteEn : std_logic_vector(7 downto 0) := (others => '0');
  signal DataIn : std_logic_vector(63 downto 0) := (others => '0');

  signal Enable  : std_logic;
  signal WordOut : std_logic_vector(WORD_WIDTH-1 downto 0);
  signal Done    : std_logic;

begin

  p_clk : process
  begin
    Clk <= '0';
    wait for CLK_PERIOD/2;
    Clk <= '1';
    wait for CLK_PERIOD/2;
  end process;

  dut : entity work.write_shift_reg
    generic map (
      WORD_WIDTH => WORD_WIDTH,
      BURST      => BURST
    )
    port map (
      Clk     => Clk,
      nRst    => nRst,
      Load    => Load,
      Shift   => Shift,
      Idx     => Idx,
      ByteEn  => ByteEn,
      DataIn  => DataIn,
      Enable  => Enable,
      WordOut => WordOut,
      Done    => Done
    );

  p_stim : process

    procedure set_pattern(
      constant be_idx : in integer
    ) is
    begin
      if be_idx < BE_PATTERNS'length then
        ByteEn <= BE_PATTERNS(be_idx);
      else
        ByteEn <= (others => '1');
      end if;
      DataIn <= DATA_TEMPLATE;
    end procedure;

  begin
    nRst   <= '0';
    Load   <= '0';
    Shift  <= '0';
    Idx    <= (others => '0');
    ByteEn <= (others => '0');
    DataIn <= DATA_TEMPLATE;

    wait for 3*CLK_PERIOD;
    wait until rising_edge(Clk);
    nRst <= '1';

    wait for 2*CLK_PERIOD;

    for be_i in 0 to BE_PATTERNS'length-1 loop

      set_pattern(be_i);
      wait until rising_edge(Clk);

      if FRAG_BITS >= 64 then

        Idx  <= IDX_TABLE(0);
        Load <= '1';
        Shift <= '0';
        wait until rising_edge(Clk);
        Load <= '0';

        for w in 0 to WORDS_PER_64-1 loop
          Shift <= '1';
          wait until rising_edge(Clk);
        end loop;
        Shift <= '0';

        wait for 4*CLK_PERIOD;

      else

        Idx  <= IDX_TABLE(0);
        Load <= '1';
        Shift <= '0';
        wait until rising_edge(Clk);
        Load <= '0';

        for frag in 0 to NUM_FRAGS-1 loop

          for k in 0 to BURST-1 loop
            Shift <= '1';
            wait until rising_edge(Clk);
          end loop;
          Shift <= '0';

          if frag < NUM_FRAGS-1 then
            Idx  <= IDX_TABLE(frag + 1);
            Load <= '1';
            wait until rising_edge(Clk);
            Load <= '0';
          end if;

        end loop;

        wait for 6*CLK_PERIOD;

      end if;

      Load  <= '0';
      Shift <= '0';
      wait for 5*CLK_PERIOD;

    end loop;

    wait;
  end process;

end architecture;
