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
    DataIn   : in  std_logic_vector(63 downto 0);

    WordOut  : out std_logic_vector(WORD_WIDTH-1 downto 0);
    Done     : out std_logic -- когда Shift выдвигает последнее валидное слово
  );
end entity;

architecture rtl of write_shift_reg is

  type t_sreg_data is array (0 to BURST-1) of std_logic_vector(WORD_WIDTH-1 downto 0);
  signal r_data   : t_sreg_data;

  constant FRAG_BITS    : integer := WORD_WIDTH * BURST;
  constant BYTES_PER_W  : integer := WORD_WIDTH / 8;   -- 1,2,4,8
  constant WORDS_PER_64 : integer := 64 / WORD_WIDTH;  -- 1,2,4,8

begin

  WordOut <= r_data(0);
  Enable  <= r_enable(0);

  p_sreg : process(Clk, nRst)
  begin
    if nRst = '0' then
      for i in 0 to BURST-1 loop
        r_data(i)   <= (others => '0');
      end loop;

    elsif rising_edge(Clk) then

      if Shift = '1' then
        for i in 0 to BURST-2 loop
          r_data(i)   <= r_data(i+1);
        end loop;
        r_data(BURST-1)   <= (others => '0');

      elsif Load = '1' then

        if FRAG_BITS <= 64 then
          for i in 0 to BURST-1 loop
            if ((conv_integer(Idx)*BURST + i + 1) * WORD_WIDTH) <= 64 then
              r_data(i) <= DataIn(
                ((conv_integer(Idx)*BURST + i + 1) * WORD_WIDTH - 1) downto
                ((conv_integer(Idx)*BURST + i)     * WORD_WIDTH));

              if BYTES_PER_W = 1 then
                r_enable(i) <= ByteEn( ((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8 );
              elsif BYTES_PER_W = 2 then
                r_enable(i) <=
                  ByteEn( (((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8) + 1 );
              elsif BYTES_PER_W = 4 then
                r_enable(i) <=
                  ByteEn( (((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8) + 1 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8) + 2 ) or
                  ByteEn( (((conv_integer(Idx)*BURST + i) * WORD_WIDTH) / 8) + 3 );
              else
                r_enable(i) <=
                  ByteEn(0) or ByteEn(1) or ByteEn(2) or ByteEn(3) or
                  ByteEn(4) or ByteEn(5) or ByteEn(6) or ByteEn(7);
              end if;
            else
              r_data(i)   <= (others => '0');
              r_enable(i) <= '0';
            end if;
          end loop;

        else
          for i in 0 to BURST-1 loop
            if i < WORDS_PER_64 then
              r_data(i) <= DataIn(((i+1) * WORD_WIDTH - 1) downto (i * WORD_WIDTH));

              if BYTES_PER_W = 1 then
                r_enable(i) <= ByteEn( (i * WORD_WIDTH) / 8 );
              elsif BYTES_PER_W = 2 then
                r_enable(i) <=
                  ByteEn( ((i * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( ((i * WORD_WIDTH) / 8) + 1 );
              elsif BYTES_PER_W = 4 then
                r_enable(i) <=
                  ByteEn( ((i * WORD_WIDTH) / 8) + 0 ) or
                  ByteEn( ((i * WORD_WIDTH) / 8) + 1 ) or
                  ByteEn( ((i * WORD_WIDTH) / 8) + 2 ) or
                  ByteEn( ((i * WORD_WIDTH) / 8) + 3 );
              else
                r_enable(i) <=
                  ByteEn(0) or ByteEn(1) or ByteEn(2) or ByteEn(3) or
                  ByteEn(4) or ByteEn(5) or ByteEn(6) or ByteEn(7);
              end if;

            else
              r_data(i)   <= (others => '0');
              r_enable(i) <= '0';
            end if;
          end loop;
        end if;
      end if;
    end if;
  end process;

end architecture;
