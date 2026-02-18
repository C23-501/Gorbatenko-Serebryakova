library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity write_shift_reg is
    generic (
        WORD_WIDTH : integer := 16; -- 8, 16, 32, 64
        BURST      : integer := 4   -- 1, 2, 4, 8, 16
    );
    port (
        Clk     : in  std_logic;
        nRst    : in  std_logic;

        Load    : in  std_logic;
        Shift   : in  std_logic;

        IdxPart : in  std_logic_vector(2 downto 0);
        IdxWord : in  std_logic_vector(3 downto 0);

        DataIn  : in  std_logic_vector(63 downto 0);

        WordOut : out std_logic_vector(WORD_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of write_shift_reg is

    type t_sreg_data is array (0 to BURST-1)
        of std_logic_vector(WORD_WIDTH-1 downto 0);

    signal r_data   : t_sreg_data;

    constant BURST_BITS   : integer := WORD_WIDTH * BURST;
    constant W64_PER_BURST : integer := BURST_BITS / 64;
    constant BURST_PER_W64 : integer := 64 / BURST_BITS;
    constant WORDS_PER_W64 : integer := 64 / WORD_WIDTH;

begin

    WordOut <= r_data(0);

    p_sreg : process(Clk, nRst)
    begin
        if nRst = '0' then
            for j in 0 to BURST-1 loop
                r_data(j)   <= (others => '0');
            end loop;

        elsif rising_edge(Clk) then

            if Shift = '1' then
                for j in 0 to BURST-2 loop
                    r_data(j)   <= r_data(j+1);
                end loop;

                r_data(BURST-1)   <= (others => '0');

            elsif Load = '1' then

                if BURST_BITS <= 64 then
                    if conv_integer(IdxPart) < BURST_PER_W64 then
                        for j in 0 to BURST-1 loop
                            r_data(j) <= DataIn(
                                ((conv_integer(IdxPart) * BURST + j + 1) * WORD_WIDTH - 1)
                                downto
                                ((conv_integer(IdxPart) * BURST + j) * WORD_WIDTH)
                            );
                        end loop;
                    else
                        for j in 0 to BURST-1 loop
                            r_data(j)   <= (others => '0');
                        end loop;
                    end if;

                else -- BURST_BITS > 64
                    if conv_integer(IdxWord) < W64_PER_BURST then
                        for j in 0 to WORDS_PER_W64-1 loop
                                r_data(conv_integer(IdxWord)*WORDS_PER_W64 + j) 
                                <= DataIn(
                                    ((j + 1) * WORD_WIDTH  - 1)
                                    downto
                                    (j * WORD_WIDTH)
                                );
                        end loop;
                    else
                        for j in 0 to BURST-1 loop
                            r_data(j)   <= (others => '0');
                        end loop;
                    end if;
                end if;

            end if;
        end if;
    end process;

end architecture;
