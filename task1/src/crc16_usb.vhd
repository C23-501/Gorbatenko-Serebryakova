library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity crc16_usb is
  generic (
    POLY : std_logic_vector(15 downto 0) := x"A001";
    INIT : std_logic_vector(15 downto 0) := x"FFFF";
    PACKET_SIZE : natural := 64
  );
  
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    enable  : in  std_logic;
    data_in : in  std_logic;
    crc_out : out std_logic_vector(15 downto 0);
    done    : out std_logic
  );
end entity;

architecture rtl of crc16_usb is
  -- Функция для вычисления необходимого количества бит для счетчика
  function log2(n : natural) return natural is
  begin
    if n <= 2 then
      return 1;
    else
      return integer(ceil(log2(real(n))));
    end if;
  end function;

  constant COUNTER_BITS : natural := log2(PACKET_SIZE);

  signal bit_cnt : unsigned(COUNTER_BITS-1 downto 0);
  signal crc_reg     : std_logic_vector(15 downto 0);
  signal done_reg    : std_logic;
  signal feedback    : std_logic;

begin

  feedback <= crc_reg(0) xor data_in;
  
  process(clk, rst)
  begin
    if rst = '1' then
      crc_reg   <= INIT;
      bit_cnt   <= (others => '0');
      done_reg  <= '0';
    elsif rising_edge(clk) then
      if done_reg = '0' then
        if enable = '1' then
          -- Вычисление CRC с произвольным полиномом
          if feedback = '1' then
            crc_reg <= ('0' & crc_reg(15 downto 1)) xor POLY;
          else
            crc_reg <= '0' & crc_reg(15 downto 1);
          end if;
          
          -- Счетчик битов
          if bit_cnt = PACKET_SIZE - 1 then
            bit_cnt <= (others => '0');
            done_reg <= '1';
          else
            bit_cnt <= bit_cnt + 1;
          end if;
        end if;
      else
        -- Автоперезапуск
        if enable = '1' then
          crc_reg     <= INIT;
          bit_cnt <= (others => '0');
          done_reg    <= '0';
        end if;
      end if;
    end if;
  end process;

  crc_out <= crc_reg xor INIT;
  done    <= done_reg;

end architecture;