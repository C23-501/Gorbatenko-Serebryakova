library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sdram_subsys_package.all;

entity SdramTopTb is
end entity;

architecture struct of SdramTopTb is

    ----------------------------------------------------------------
    -- Компоненты
    ----------------------------------------------------------------
    component SdramTop
        port (
            nRst      : in  std_logic;
            CLK_12MHz : in  std_logic;

            nCS   : out std_logic;
            nRAS  : out std_logic;
            nCAS  : out std_logic;
            nWE   : out std_logic;
            CKE   : out std_logic;
            DQM   : out std_logic_vector(1 downto 0);
            BS    : out std_logic_vector(1 downto 0);
            A     : out std_logic_vector(11 downto 0);
            Dq    : out std_logic_vector(15 downto 0);

            nCS_o  : out std_logic;
            nRAS_o : out std_logic;
            nCAS_o : out std_logic;
            nWE_o  : out std_logic;
            
            CLK_160MHz_o : out std_logic;

            request_command_fifo_read_en : out std_logic;
            request_command_fifo_data    : in  std_logic_vector(61 downto 0);
            request_command_fifo_empty   : in  std_logic;

            request_data_fifo_read_en : out std_logic;
            request_data_fifo_data    : in  std_logic_vector(63 downto 0);
            request_data_fifo_empty   : in  std_logic;

            response_command_fifo_write_en : out std_logic;
            response_command_fifo_data     : out std_logic_vector(19 downto 0);
            response_command_fifo_full     : in  std_logic;

            response_data_fifo_write_en : out std_logic;
            response_data_fifo_data     : out std_logic_vector(63 downto 0);
				response_data_fifo_full     : in  std_logic;
            response_data_fifo_used     : in  std_logic_vector(9 downto 0);

            LED_ctr : out std_logic_vector(7 downto 0)
        );
    end component;

    component SdramTopTester
        port (
            nCS   : in std_logic;
            nRAS  : in std_logic;
            nCAS  : in std_logic;
            nWE   : in std_logic;
            CKE   : in std_logic;
            DQM   : in std_logic_vector(1 downto 0);
            BS    : in std_logic_vector(1 downto 0);
            A     : in std_logic_vector(11 downto 0);
            Dq    : in std_logic_vector(15 downto 0);
            LED_ctr : in std_logic_vector(7 downto 0);

            request_command_fifo_read_en : in  std_logic;
            request_command_fifo_data    : out std_logic_vector(61 downto 0);
            request_command_fifo_empty   : out std_logic;

            request_data_fifo_read_en : in  std_logic;
            request_data_fifo_data    : out std_logic_vector(63 downto 0);
            request_data_fifo_empty   : out std_logic;

            response_command_fifo_write_en : in  std_logic;
            response_command_fifo_data     : in  std_logic_vector(19 downto 0);
            response_command_fifo_full     : out std_logic;

            response_data_fifo_write_en : in  std_logic;
            response_data_fifo_data     : in  std_logic_vector(63 downto 0);
				response_data_fifo_full     : out std_logic;
            response_data_fifo_used     : out std_logic_vector(9 downto 0);

            nRst      : out std_logic;
            CLK_12MHz : out std_logic
        );
    end component;

    component mt48lc4m16a2
        generic (
            addr_bits : integer := 12;
            data_bits : integer := 16;
            col_bits  : integer := 8;
            mem_sizes : integer := 1048575
        );
        port (
            Dq    : inout std_logic_vector (data_bits - 1 downto 0);
            Addr  : in    std_logic_vector (addr_bits - 1 downto 0);
            Ba    : in    std_logic_vector (1 downto 0);
            Clk   : in    std_logic;
            Cke   : in    std_logic;
            Cs_n  : in    std_logic;
            Ras_n : in    std_logic;
            Cas_n : in    std_logic;
            We_n  : in    std_logic;
            Dqm   : in    std_logic_vector (1 downto 0)
        );
    end component;

    ----------------------------------------------------------------
    -- Внутренние сигналы
    ----------------------------------------------------------------
    signal nRst_s      : std_logic;
    signal clk12_s     : std_logic;

    -- шина между топом и памятью
    signal nCS_s   : std_logic;
    signal nRAS_s  : std_logic;
    signal nCAS_s  : std_logic;
    signal nWE_s   : std_logic;
    signal CKE_s   : std_logic;
    signal DQM_s   : std_logic_vector(1 downto 0);
    signal BS_s    : std_logic_vector(1 downto 0);
    signal A_s     : std_logic_vector(11 downto 0);
    signal DQ_bus  : std_logic_vector(15 downto 0);
    signal LED_s   : std_logic_vector(7 downto 0);
    
    signal CLK_160MHz_o_s : std_logic;

    signal nCS_o_s, nRAS_o_s, nCAS_o_s, nWE_o_s : std_logic;

    -- FIFO сигналы между DUT и tester’ом
    signal req_cmd_read_en  : std_logic;
    signal req_cmd_data     : std_logic_vector(61 downto 0);
    signal req_cmd_empty    : std_logic;

    signal req_data_read_en : std_logic;
    signal req_data_data    : std_logic_vector(63 downto 0);
    signal req_data_empty   : std_logic;

    signal resp_cmd_wr_en : std_logic;
    signal resp_cmd_data  : std_logic_vector(19 downto 0);
    signal resp_cmd_full  : std_logic;

    signal resp_data_wr_en : std_logic;
    signal resp_data_data  : std_logic_vector(63 downto 0);
	 signal resp_data_full  : std_logic;
    signal resp_data_used  : std_logic_vector(9 downto 0);

    -- линии с задержкой до SDRAM
    signal nCS_sdram, nRAS_sdram, nCAS_sdram, nWE_sdram : std_logic;
    signal CKE_sdram : std_logic;
    signal DQM_sdram : std_logic_vector(1 downto 0);
    signal BS_sdram  : std_logic_vector(1 downto 0);
    signal A_sdram   : std_logic_vector(11 downto 0);

begin

    ----------------------------------------------------------------
    -- Небольшая задержка до модели памяти (как в твоём примере)
    ----------------------------------------------------------------
    nCS_sdram  <= nCS_s  after 1.2 ns;
    nRAS_sdram <= nRAS_s after 1.2 ns;
    nCAS_sdram <= nCAS_s after 1.2 ns;
    nWE_sdram  <= nWE_s  after 1.2 ns;
    CKE_sdram  <= CKE_s  after 1.2 ns;
    DQM_sdram  <= DQM_s  after 1.2 ns;
    BS_sdram   <= BS_s   after 1.2 ns;
    A_sdram    <= A_s    after 1.2 ns;

    ----------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------
    U_DUT : SdramTop
        port map (
            nRst      => nRst_s,
            CLK_12MHz => clk12_s,

            nCS   => nCS_s,
            nRAS  => nRAS_s,
            nCAS  => nCAS_s,
            nWE   => nWE_s,
            CKE   => CKE_s,
            DQM   => DQM_s,
            BS    => BS_s,
            A     => A_s,
            Dq    => DQ_bus,

            nCS_o  => nCS_o_s,
            nRAS_o => nRAS_o_s,
            nCAS_o => nCAS_o_s,
            nWE_o  => nWE_o_s,
            
            CLK_160MHz_o => CLK_160MHz_o_s,

            request_command_fifo_read_en => req_cmd_read_en,
            request_command_fifo_data    => req_cmd_data,
            request_command_fifo_empty   => req_cmd_empty,

            request_data_fifo_read_en => req_data_read_en,
            request_data_fifo_data    => req_data_data,
            request_data_fifo_empty   => req_data_empty,

            response_command_fifo_write_en => resp_cmd_wr_en,
            response_command_fifo_data     => resp_cmd_data,
            response_command_fifo_full     => resp_cmd_full,

            response_data_fifo_write_en => resp_data_wr_en,
            response_data_fifo_data     => resp_data_data,
				response_data_fifo_full     => resp_data_full,
            response_data_fifo_used     => resp_data_used,

            LED_ctr => LED_s
        );

    ----------------------------------------------------------------
    -- Tester (генерирует клок, reset и FIFO-стимулы)
    ----------------------------------------------------------------
    U_TESTER : SdramTopTester
        port map (
            nCS   => nCS_s,
            nRAS  => nRAS_s,
            nCAS  => nCAS_s,
            nWE   => nWE_s,
            CKE   => CKE_s,
            DQM   => DQM_s,
            BS    => BS_s,
            A     => A_s,
            Dq    => DQ_bus,
            LED_ctr => LED_s,

            request_command_fifo_read_en => req_cmd_read_en,
            request_command_fifo_data    => req_cmd_data,
            request_command_fifo_empty   => req_cmd_empty,

            request_data_fifo_read_en => req_data_read_en,
            request_data_fifo_data    => req_data_data,
            request_data_fifo_empty   => req_data_empty,

            response_command_fifo_write_en => resp_cmd_wr_en,
            response_command_fifo_data     => resp_cmd_data,
            response_command_fifo_full     => resp_cmd_full,

            response_data_fifo_write_en => resp_data_wr_en,
            response_data_fifo_data     => resp_data_data,
				response_data_fifo_full     => resp_data_full,
            response_data_fifo_used     => resp_data_used,

            nRst      => nRst_s,
            CLK_12MHz => clk12_s
        );

    ----------------------------------------------------------------
    -- Модель SDRAM
    ----------------------------------------------------------------
    U_SDRAM : mt48lc4m16a2
        port map (
            Dq    => DQ_bus,
            Addr  => A_sdram,
            Ba    => BS_sdram,
            Clk   => CLK_160MHz_o_s,
            Cke   => CKE_sdram,
            Cs_n  => nCS_sdram,
            Ras_n => nRAS_sdram,
            Cas_n => nCAS_sdram,
            We_n  => nWE_sdram,
            Dqm   => DQM_sdram
        );

end architecture;
