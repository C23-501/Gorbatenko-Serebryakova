library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crc16_usb is
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

  constant POLY    : std_logic_vector(15 downto 0) := x"A001";
  constant INIT    : std_logic_vector(15 downto 0) := x"FFFF";
  constant MAX_CNT : unsigned(5 downto 0) := to_unsigned(63, 6); -- 63 в unsigned

  signal bit_cnt   : unsigned(5 downto 0);
  signal crc_reg   : std_logic_vector(15 downto 0);
  signal done_reg  : std_logic;
  signal enable_internal : std_logic;
  signal feedback  : std_logic;

begin

  feedback <= crc_reg(0) xor data_in;
  
  process(clk, rst)
  begin
    if rst = '1' then
      crc_reg   <= INIT;
      bit_cnt   <= (others => '0');
      done_reg  <= '0';
      enable_internal <= '0';
    elsif rising_edge(clk) then
      -- Управление внутренним enable
      if enable = '1' then
        enable_internal <= '1';
      elsif bit_cnt = MAX_CNT then  -- Правильное сравнение
        enable_internal <= '0';
      end if;
    
      -- Обработка CRC
      if enable_internal = '1' then
        if feedback = '1' then
          crc_reg <= ('0' & crc_reg(15 downto 1)) xor POLY;
        else
          crc_reg <= '0' & crc_reg(15 downto 1);
        end if;
      end if;
      
      -- Счетчик битов
      if enable_internal = '1' then
        if bit_cnt = MAX_CNT then  -- Правильное сравнение
          bit_cnt <= (others => '0');
        else
          bit_cnt <= bit_cnt + 1;
        end if;
      end if;
      
      -- Сигнал завершения
      if enable_internal = '1' and bit_cnt = MAX_CNT then  -- Правильное сравнение
        done_reg <= '1';
      elsif enable = '1' then
        done_reg <= '0';
      end if;
    end if;
  end process;

  crc_out <= crc_reg xor INIT;
  done    <= done_reg;

end architecture;