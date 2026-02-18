library ieee;
use ieee.std_logic_1164.all;

entity SdramTopWrapperTb is
end entity;

architecture tb of SdramTopWrapperTb is

    -- входы
    signal nRst      : std_logic := '0';
    signal CLK_12MHz : std_logic := '0';

    -- SDRAM pins
    signal nCS   : std_logic;
    signal nRAS  : std_logic;
    signal nCAS  : std_logic;
    signal nWE   : std_logic;
    signal CKE   : std_logic;
    signal DQM   : std_logic_vector(1 downto 0);
    signal BS    : std_logic_vector(1 downto 0);
    signal A     : std_logic_vector(11 downto 0);
    signal Dq    : std_logic_vector(15 downto 0);

    -- debug
    signal nCS_DBG  : std_logic;
    signal nRAS_DBG : std_logic;
    signal nCAS_DBG : std_logic;
    signal nWE_DBG  : std_logic;

    signal DQ0_DBG        : std_logic;
    signal FSM_ACTIVE_DBG : std_logic;
    signal RESP_VALID_DBG : std_logic;
    signal WREN           : std_logic;

    signal RD_LOAD_DBG    : std_logic;
    signal WR_SHIFT_DBG   : std_logic;
    signal CLK_160MHz_DBG : std_logic;

    constant TCLK : time := 83.333 ns; -- 12 MHz

begin

    --------------------------------------------------------------------
    -- Clock generator (12 MHz)
    --------------------------------------------------------------------
    p_clk : process
    begin
        while true loop
            CLK_12MHz <= '0';
            wait for TCLK/2;
            CLK_12MHz <= '1';
            wait for TCLK/2;
        end loop;
    end process;

    --------------------------------------------------------------------
    -- Reset generator
    --------------------------------------------------------------------
    p_rst : process
    begin
        nRst <= '0';
        wait for 2 us; 
        nRst <= '1';
        wait;
    end process;

    --------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------
    U_DUT : entity work.SdramTopWrapper
        port map (
            nRst      => nRst,
            CLK_12MHz => CLK_12MHz,

            nCS  => nCS,
            nRAS => nRAS,
            nCAS => nCAS,
            nWE  => nWE,
            CKE  => CKE,
            DQM  => DQM,
            BS   => BS,
            A    => A,
            Dq   => Dq,

            nCS_DBG  => nCS_DBG,
            nRAS_DBG => nRAS_DBG,
            nCAS_DBG => nCAS_DBG,
            nWE_DBG  => nWE_DBG,

            DQ0_DBG        => DQ0_DBG,
            FSM_ACTIVE_DBG => FSM_ACTIVE_DBG,
            RESP_VALID_DBG => RESP_VALID_DBG,
            WREN           => WREN,

            RD_LOAD_DBG    => RD_LOAD_DBG,
            WR_SHIFT_DBG   => WR_SHIFT_DBG,
            CLK_160MHz_DBG => CLK_160MHz_DBG
        );

    Dq <= (others => 'Z');


end architecture;
