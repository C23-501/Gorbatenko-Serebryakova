library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity write_shift_reg is
  generic (
    WORD_WIDTH : integer := 16; -- 8, 16, 32, 64
    BURST      : integer := 4   -- 1, 2, 4, 8
  );
  port (
    Clk      : in  std_logic;
    nRst     : in  std_logic;

    Load     : in  std_logic;
    Shift    : in  std_logic;

    Idx      : in  std_logic_vector(2 downto 0); -- для длины регистра < 64, вычисляется 64/FRAG_BITS, 000 -> 001 -> 002 ...
    ByteEn   : in  std_logic_vector(7 downto 0);
    DataIn   : in  std_logic_vector(63 downto 0);

    Enable   : out std_logic;
    WordOut  : out std_logic_vector(WORD_WIDTH-1 downto 0);
    Done     : out std_logic -- когда Shift выдвигает последнее валидное слово
  );
end entity;

architecture rtl of write_shift_reg is

  type t_sreg_data   is array (0 to BURST-1) of std_logic_vector(WORD_WIDTH-1 downto 0);
  type t_sreg_enable is array (0 to BURST-1) of std_logic;

  signal r_data   : t_sreg_data;
  signal r_enable : t_sreg_enable;

  constant FRAG_BITS    : integer := WORD_WIDTH * BURST;
  constant BYTES_PER_W  : integer := WORD_WIDTH / 8;   -- 1,2,4,8
  constant WORDS_PER_64 : integer := 64 / WORD_WIDTH;  -- 1,2,4,8

begin

  WordOut <= r_data(0);
  Enable  <= r_enable(0);

  gen_done_1 : if BURST = 1 generate
      Done <= '1' when (Shift = '1' and r_enable(0) = '1') else '0';
  end generate;

  gen_done_2 : if BURST = 2 generate
      Done <= '1' when (Shift = '1' and r_enable(0) = '1' and r_enable(1) = '0') else '0';
  end generate;

  gen_done_4 : if BURST = 4 generate
      Done <= '1' when (Shift = '1' and r_enable(0) = '1' and
                      r_enable(1) = '0' and r_enable(2) = '0' and r_enable(3) = '0')
            else '0';
  end generate;

  gen_done_8 : if BURST = 8 generate
      Done <= '1' when (Shift = '1' and r_enable(0) = '1' and
                      r_enable(1) = '0' and r_enable(2) = '0' and r_enable(3) = '0' and
                      r_enable(4) = '0' and r_enable(5) = '0' and r_enable(6) = '0' and r_enable(7) = '0')
            else '0';
  end generate;

  p_sreg : process(Clk, nRst)
  begin
    if nRst = '0' then
      for j in 0 to BURST-1 loop
        r_data(j)   <= (others => '0');
        r_enable(j) <= '0';
      end loop;

    elsif rising_edge(Clk) then

      if Shift = '1' then
        for j in 0 to BURST-2 loop
          r_data(j)   <= r_data(j+1);
          r_enable(j) <= r_enable(j+1);
        end loop;
        r_data(BURST-1)   <= (others => '0');
        r_enable(BURST-1) <= '0';

      elsif Load = '1' then

        if FRAG_BITS <= 64 then
          for j in 0 to BURST-1 loop
            if ((conv_integer(Idx)*BURST + j + 1) * WORD_WIDTH) <= 64 then
              r_data(j) <= DataIn(
                ((conv_integer(Idx)*BURST + j + 1) * WORD_WIDTH - 1) downto
                ((conv_integer(Idx)*BURST + j)     * WORD_WIDTH));

              if BYTES_PER_W = 1 then
                r_enable(j) <= ByteEn( ((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8 );
              elsif BYTES_PER_W = 2 then
                r_enable(j) <=
                  ByteEn( (((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8) + 1 );
              elsif BYTES_PER_W = 4 then
                r_enable(j) <=
                  ByteEn( (((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8) + 1 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8) + 2 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + j) * WORD_WIDTH) / 8) + 3 );
              else
                r_enable(j) <=
                  ByteEn(0) or ByteEn(1) or ByteEn(2) or ByteEn(3) or
                  ByteEn(4) or ByteEn(5) or ByteEn(6) or ByteEn(7);
              end if;
            else
              r_data(j)   <= (others => '0');
              r_enable(j) <= '0';
            end if;
          end loop;

        else
          for j in 0 to BURST-1 loop
            if j < WORDS_PER_64 then
              r_data(j) <= DataIn(((j+1) * WORD_WIDTH - 1) downto (j * WORD_WIDTH));

              if BYTES_PER_W = 1 then
                r_enable(j) <= ByteEn( (j * WORD_WIDTH) / 8 );
              elsif BYTES_PER_W = 2 then
                r_enable(j) <=
                  ByteEn( ((j * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( ((j * WORD_WIDTH) / 8) + 1 );
              elsif BYTES_PER_W = 4 then
                r_enable(j) <=
                  ByteEn( ((j * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( ((j * WORD_WIDTH) / 8) + 1 ) or
                  ByteEn( ((j * WORD_WIDTH) / 8) + 2 ) or
                  ByteEn( ((j * WORD_WIDTH) / 8) + 3 );
              else
                r_enable(j) <=
                  ByteEn(0) or ByteEn(1) or ByteEn(2) or ByteEn(3) or
                  ByteEn(4) or ByteEn(5) or ByteEn(6) or ByteEn(7);
              end if;

            else
              r_data(j)   <= (others => '0');
              r_enable(j) <= '0';
            end if;
          end loop;
        end if;
      end if;
    end if;
  end process;

end architecture;
