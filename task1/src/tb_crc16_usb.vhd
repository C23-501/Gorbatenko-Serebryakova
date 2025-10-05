library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_crc16_usb is
end entity tb_crc16_usb;

architecture behavioral of tb_crc16_usb is

    -- Константы
    constant CLK_PERIOD : time := 10 ns;

    -- Сигналы тестбенча
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '0';
    signal enable   : std_logic := '0';
    signal data_in  : std_logic := '0';
    signal crc_out  : std_logic_vector(15 downto 0);
    signal done     : std_logic;

    -- Компонент тестера
    component crc16_usb_tester is
        generic (
            POLY        : std_logic_vector(15 downto 0);
            INIT        : std_logic_vector(15 downto 0);
            PACKET_SIZE : natural
        );
        port (
            clk      : in  std_logic;
            rst      : out std_logic;
            enable   : out std_logic;
            data_in  : out std_logic;
            crc_out  : in  std_logic_vector(15 downto 0);
            done     : in  std_logic
        );
    end component;

begin

    -- Генератор тактового сигнала
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    -- DUT с параметрами по умолчанию
    dut_default : entity work.crc16_usb
        generic map (
            POLY        => x"A001",
            INIT        => x"FFFF",
            PACKET_SIZE => 64
        )
        port map (
            clk      => clk,
            rst      => rst,
            enable   => enable,
            data_in  => data_in,
            crc_out  => crc_out,
            done     => done
        );

    -- Экземпляр тестера
    tester_inst : crc16_usb_tester
        generic map (
            POLY        => x"A001",
            INIT        => x"FFFF",
            PACKET_SIZE => 64
        )
        port map (
            clk      => clk,
            rst      => rst,
            enable   => enable,
            data_in  => data_in,
            crc_out  => crc_out,
            done     => done
        );

end architecture behavioral;