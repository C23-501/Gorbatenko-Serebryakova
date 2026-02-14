library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sdram_subsys_package.all;

entity SdramFsmTb is
end entity;

architecture struct of SdramFsmTb is

    component SdramFsm
        generic (
            DataWidth      : integer := 16;
            tRCD_Cycles    : integer := 2;
            CAS_Latency    : integer := 3;
            BurstLength    : integer := 8;
            tWR_Cycles     : integer := 2;
            tRAS_Cycles    : integer := 7;
            tRP_Cycles     : integer := 2;
            AddressWidth   : integer := 25
        );
        port (
            nRst : in  std_logic;
            clk  : in  std_logic;

            state_subsys : in  StateSubsys_type;
            state_fsm    : out StateFSM_type;

            request_command_fifo_rden  : out std_logic;
            request_command_fifo_data  : in  std_logic_vector(61 downto 0);
            request_command_fifo_empty : in  std_logic;

            request_data_fifo_rden     : out std_logic;
            request_data_fifo_data     : in  std_logic_vector(63 downto 0);
            request_data_fifo_empty    : in  std_logic;

            response_command_fifo_wren : out std_logic;
            response_command_fifo_data : out std_logic_vector(19 downto 0);
            response_command_fifo_full : in  std_logic;

            response_data_fifo_wren    : out std_logic;
            response_data_fifo_data    : out std_logic_vector(63 downto 0);
            response_data_fifo_full    : in  std_logic;

            nCS  : out std_logic;
            nRAS : out std_logic;
            nCAS : out std_logic;
            nWE  : out std_logic;
            CKE  : out std_logic;
            DQ   : out std_logic_vector(15 downto 0);
            DQM  : out std_logic_vector(1 downto 0);
            BS   : out std_logic_vector(1 downto 0);
            A    : out std_logic_vector(11 downto 0)
        );
    end component;

    component SdramFsmTester
        port (
            nRst : out std_logic;
            clk  : out std_logic;

            state_subsys : out StateSubsys_type;

            request_command_fifo_rden  : in  std_logic;
            request_command_fifo_data  : out std_logic_vector(61 downto 0);
            request_command_fifo_empty : out std_logic;

            request_data_fifo_rden     : in  std_logic;
            request_data_fifo_data     : out std_logic_vector(63 downto 0);
            request_data_fifo_empty    : out std_logic;

            response_command_fifo_wren : in  std_logic;
            response_command_fifo_data : in  std_logic_vector(19 downto 0);
            response_command_fifo_full : out std_logic;

            response_data_fifo_wren    : in  std_logic;
            response_data_fifo_data    : in  std_logic_vector(63 downto 0);
            response_data_fifo_full    : out std_logic
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

    signal nRst_s : std_logic;
    signal clk_s  : std_logic;

    signal state_subsys_s : StateSubsys_type;
    signal state_fsm_s    : StateFSM_type;

    signal req_cmd_rden  : std_logic;
    signal req_cmd_data  : std_logic_vector(61 downto 0);
    signal req_cmd_empty : std_logic;

    signal req_data_rden  : std_logic;
    signal req_data_data  : std_logic_vector(63 downto 0);
    signal req_data_empty : std_logic;

    signal resp_cmd_wren : std_logic;
    signal resp_cmd_data : std_logic_vector(19 downto 0);
    signal resp_cmd_full : std_logic;

    signal resp_data_wren : std_logic;
    signal resp_data_data : std_logic_vector(63 downto 0);
    signal resp_data_full : std_logic;

    signal nCS_s, nRAS_s, nCAS_s, nWE_s : std_logic;
    signal CKE_s : std_logic;
    signal DQM_s : std_logic_vector(1 downto 0);
    signal BS_s  : std_logic_vector(1 downto 0);
    signal A_s   : std_logic_vector(11 downto 0);

    signal DQ_bus : std_logic_vector(15 downto 0);

    signal nCS_sdram, nRAS_sdram, nCAS_sdram, nWE_sdram : std_logic;
    signal CKE_sdram : std_logic;
    signal DQM_sdram : std_logic_vector(1 downto 0);
    signal BS_sdram  : std_logic_vector(1 downto 0);
    signal A_sdram   : std_logic_vector(11 downto 0);

begin

    nCS_sdram  <= nCS_s  after 1.2 ns;
    nRAS_sdram <= nRAS_s after 1.2 ns;
    nCAS_sdram <= nCAS_s after 1.2 ns;
    nWE_sdram  <= nWE_s  after 1.2 ns;
    CKE_sdram  <= CKE_s  after 1.2 ns;
    DQM_sdram  <= DQM_s  after 1.2 ns;
    BS_sdram   <= BS_s   after 1.2 ns;
    A_sdram    <= A_s    after 1.2 ns;

    U_DUT : SdramFsm
        port map (
            nRst => nRst_s,
            clk  => clk_s,

            state_subsys => state_subsys_s,
            state_fsm    => state_fsm_s,

            request_command_fifo_rden  => req_cmd_rden,
            request_command_fifo_data  => req_cmd_data,
            request_command_fifo_empty => req_cmd_empty,

            request_data_fifo_rden  => req_data_rden,
            request_data_fifo_data  => req_data_data,
            request_data_fifo_empty => req_data_empty,

            response_command_fifo_wren => resp_cmd_wren,
            response_command_fifo_data => resp_cmd_data,
            response_command_fifo_full => resp_cmd_full,

            response_data_fifo_wren => resp_data_wren,
            response_data_fifo_data => resp_data_data,
            response_data_fifo_full => resp_data_full,

            nCS  => nCS_s,
            nRAS => nRAS_s,
            nCAS => nCAS_s,
            nWE  => nWE_s,
            CKE  => CKE_s,
            DQ   => DQ_bus,
            DQM  => DQM_s,
            BS   => BS_s,
            A    => A_s
        );

    U_TESTER : SdramFsmTester
        port map (
            nRst => nRst_s,
            clk  => clk_s,

            state_subsys => state_subsys_s,

            request_command_fifo_rden  => req_cmd_rden,
            request_command_fifo_data  => req_cmd_data,
            request_command_fifo_empty => req_cmd_empty,

            request_data_fifo_rden  => req_data_rden,
            request_data_fifo_data  => req_data_data,
            request_data_fifo_empty => req_data_empty,

            response_command_fifo_wren => resp_cmd_wren,
            response_command_fifo_data => resp_cmd_data,
            response_command_fifo_full => resp_cmd_full,

            response_data_fifo_wren => resp_data_wren,
            response_data_fifo_data => resp_data_data,
            response_data_fifo_full => resp_data_full
        );

    U_SDRAM : mt48lc4m16a2
        port map (
            Dq    => DQ_bus,
            Addr  => A_sdram,
            Ba    => BS_sdram,
            Clk   => clk_s,
            Cke   => CKE_sdram,
            Cs_n  => nCS_sdram,
            Ras_n => nRAS_sdram,
            Cas_n => nCAS_sdram,
            We_n  => nWE_sdram,
            Dqm   => DQM_sdram
        );

end architecture;
