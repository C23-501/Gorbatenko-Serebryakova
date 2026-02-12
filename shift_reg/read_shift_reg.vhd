library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity read_shift_reg is
  generic (
    WORD_WIDTH : integer := 16; -- 8, 16, 32, 64
    BURST      : integer := 4   -- 1, 2, 4, 8
  );
  port (
    Clk      : in  std_logic;
    nRst     : in  std_logic;

    Load     : in  std_logic;  
    Shift    : in  std_logic;

    DataIn   : in  std_logic_vector(WORD_WIDTH-1 downto 0);

    DataOut  : out std_logic_vector(63 downto 0);
    Valid    : out std_logic;
    Done     : out std_logic
  );
end entity;

architecture rtl of read_shift_reg is

  type t_sreg_data is array (0 to BURST-1) of std_logic_vector(WORD_WIDTH-1 downto 0);
  signal r_data : t_sreg_data;
  signal r_word_cnt : std_logic_vector(3 downto 0);

  constant FRAG_BITS    : integer := WORD_WIDTH * BURST;
  constant WORDS_PER_64 : integer := 64 / WORD_WIDTH;

begin

  gen_data_out_small : if BURST <= WORDS_PER_64 generate

    gen_real : for i in 0 to BURST-1 generate
      DataOut((i+1)*WORD_WIDTH - 1 downto i*WORD_WIDTH) <= r_data(i);
    end generate;

    gen_zero : for i in BURST to WORDS_PER_64-1 generate
      DataOut((i+1)*WORD_WIDTH - 1 downto i*WORD_WIDTH) <= (others => '0');
    end generate;

  end generate;

  gen_data_out_large : if BURST > WORDS_PER_64 generate

    gen_real_only : for i in 0 to WORDS_PER_64-1 generate
      DataOut((i+1)*WORD_WIDTH - 1 downto i*WORD_WIDTH) <= r_data(i);
    end generate;

  end generate;

  pad_hi : if WORDS_PER_64*WORD_WIDTH < 64 generate
    DataOut(63 downto WORDS_PER_64*WORD_WIDTH) <= (others => '0');
  end generate;

  Valid <=
    '1' when (
      (FRAG_BITS >= 64  and conv_integer(r_word_cnt) >= WORDS_PER_64) or
      (FRAG_BITS <  64  and conv_integer(r_word_cnt) = BURST)
    ) else '0';

  Done <=
    '1' when (
      Shift = '1' and (
        (FRAG_BITS >= 64 and conv_integer(r_word_cnt) = WORDS_PER_64) or
        (FRAG_BITS <  64 and conv_integer(r_word_cnt) = BURST)
      )
    ) else '0';

  p_sreg : process(Clk, nRst)
  begin
    if nRst = '0' then
      for j in 0 to BURST-1 loop
        r_data(j) <= (others => '0');
      end loop;
      r_word_cnt <= (others => '0');

    elsif rising_edge(Clk) then

      if (Shift = '1') and 
         ((FRAG_BITS >= 64 and conv_integer(r_word_cnt) >= WORDS_PER_64) or
          (FRAG_BITS <  64 and conv_integer(r_word_cnt) = BURST)) then

        if FRAG_BITS >= 64 then
          for j in 0 to BURST-1 loop
            if j <= BURST-WORDS_PER_64-1 then
              r_data(j) <= r_data(j+WORDS_PER_64);
            else
              r_data(j) <= (others => '0');
            end if;
          end loop;
          r_word_cnt <= r_word_cnt - conv_std_logic_vector(WORDS_PER_64, 4);

        else
          for j in 0 to BURST-1 loop
            r_data(j) <= (others => '0');
          end loop;
          r_word_cnt <= r_word_cnt - conv_std_logic_vector(BURST, 4);
        end if;

      elsif (Load = '1') and (conv_integer(r_word_cnt) < BURST) then
        r_data(conv_integer(r_word_cnt)) <= DataIn;
        r_word_cnt <= r_word_cnt + conv_std_logic_vector(1, 4);
      end if;
    end if;
  end process;

end architecture;
