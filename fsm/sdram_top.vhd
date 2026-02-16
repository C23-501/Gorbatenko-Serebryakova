LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;

LIBRARY work;
USE work.sdram_subsys_package.ALL;

LIBRARY altera_mf;
USE altera_mf.all;

entity SdramTop is
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
        Dq    : inout std_logic_vector(15 downto 0);

        nCS_o  : out std_logic;
        nRAS_o : out std_logic;
        nCAS_o : out std_logic;
        nWE_o  : out std_logic;

        CLK_160MHz_o : out std_logic;
        CLK_80MHz_o  : out std_logic;

        req_cmd_wrreq  : in  std_logic;
        req_cmd_wdata  : in  std_logic_vector(61 downto 0);
        req_cmd_wrfull : out std_logic;

        req_data_wrreq  : in  std_logic;
        req_data_wdata  : in  std_logic_vector(63 downto 0);
        req_data_wrfull : out std_logic;

        resp_cmd_rdreq   : in  std_logic;
        resp_cmd_rdata   : out std_logic_vector(19 downto 0);
        resp_cmd_rdempty : out std_logic;

        resp_data_rdreq   : in  std_logic;
        resp_data_rdata   : out std_logic_vector(63 downto 0);
        resp_data_rdempty : out std_logic;

        request_command_fifo_read_en   : out std_logic;
        request_data_fifo_read_en      : out std_logic;
        response_command_fifo_write_en : out std_logic;
        response_command_fifo_data     : out std_logic_vector(19 downto 0);
        response_data_fifo_write_en    : out std_logic;
        response_data_fifo_data        : out std_logic_vector(63 downto 0);

        -- LEDs
        LED_ctr : out std_logic_vector(7 downto 0)
    );
end SdramTop;


architecture rtl of SdramTop is

    signal A_FSM       : std_logic_vector(11 downto 0);
    signal A_Subsys    : std_logic_vector(11 downto 0);
    signal BS_FSM      : std_logic_vector(1 downto 0);
    signal BS_Subsys   : std_logic_vector(1 downto 0);
    signal CKE_FSM     : std_logic;
    signal CKE_Subsys  : std_logic;
    signal DQM_FSM     : std_logic_vector(1 downto 0);
    signal DQM_Subsys  : std_logic_vector(1 downto 0);
    signal StateFSM    : StateFSM_type;
    signal State_out   : StateSubsys_type;
    signal nCAS_FSM    : std_logic;
    signal nCAS_Subsys : std_logic;
    signal nCS_FSM     : std_logic;
    signal nCS_Subsys  : std_logic;
    signal nRAS_FSM    : std_logic;
    signal nRAS_Subsys : std_logic;
    signal nWE_FSM     : std_logic;
    signal nWE_Subsys  : std_logic;

    -- LED
    signal LED_counter  : std_logic_vector(23 downto 0);
    signal LED_quarters : std_logic_vector(1 downto 0);
    signal LED_r        : std_logic_vector(7 downto 0);
    signal quarter_flag : std_logic;

    signal nCS_s  : std_logic;
    signal nCAS_s : std_logic;
    signal nRAS_s : std_logic;
    signal nWE_s  : std_logic;

    signal CLK_160MHz : std_logic;
    signal CLK_80MHz  : std_logic;

    signal PLL_reset     : std_logic;
    signal pll_lock_160  : std_logic;
    signal pll_lock_80   : std_logic;
    signal nRst_global   : std_logic;

    -- request (FIFO q/empty/full)
    signal req_cmd_q      : std_logic_vector(61 downto 0);
    signal req_cmd_empty  : std_logic;
    signal req_cmd_full_s : std_logic;

    signal req_data_q      : std_logic_vector(63 downto 0);
    signal req_data_empty  : std_logic;
    signal req_data_full_s : std_logic;

    -- response (FIFO q/empty/full)
    signal resp_cmd_q       : std_logic_vector(19 downto 0);
    signal resp_cmd_empty_s : std_logic;
    signal resp_cmd_full_s  : std_logic;

    signal resp_data_q       : std_logic_vector(63 downto 0);
    signal resp_data_empty_s : std_logic;
    signal resp_data_full_s  : std_logic;

    -- rdreq от FSM 
    signal req_cmd_rdreq_s  : std_logic;
    signal req_data_rdreq_s : std_logic;

    -- wren/wdata от FSM 
    signal resp_cmd_wren_s  : std_logic;
    signal resp_cmd_wdata_s : std_logic_vector(19 downto 0);

    signal resp_data_wren_s  : std_logic;
    signal resp_data_wdata_s : std_logic_vector(63 downto 0);

    --------------------------------------------------------------------
    -- COMPONENT объявления
    --------------------------------------------------------------------
    component SdramArbiter
        port (
            nRst        : in  std_logic;
            CLK         : in  std_logic;

            StateFSM    : in  StateFSM_type;
            nCS_FSM     : in  std_logic;
            nRAS_FSM    : in  std_logic;
            nCAS_FSM    : in  std_logic;
            nWE_FSM     : in  std_logic;
            CKE_FSM     : in  std_logic;
            DQM_FSM     : in  std_logic_vector(1 downto 0);
            BS_FSM      : in  std_logic_vector(1 downto 0);
            A_FSM       : in  std_logic_vector(11 downto 0);

            nCS_Subsys  : in  std_logic;
            nRAS_Subsys : in  std_logic;
            nCAS_Subsys : in  std_logic;
            nWE_Subsys  : in  std_logic;
            CKE_Subsys  : in  std_logic;
            DQM_Subsys  : in  std_logic_vector(1 downto 0);
            BS_Subsys   : in  std_logic_vector(1 downto 0);
            A_Subsys    : in  std_logic_vector(11 downto 0);

            nCS         : out std_logic;
            nRAS        : out std_logic;
            nCAS        : out std_logic;
            nWE         : out std_logic;
            CKE         : out std_logic;
            DQM         : out std_logic_vector(1 downto 0);
            BS          : out std_logic_vector(1 downto 0);
            A           : out std_logic_vector(11 downto 0)
        );
    end component;

    component SdramSubsys
        generic (
            Burst_length : integer := 4;
            CAS_Latency  : integer := 3;
            CLK_Freq_MHz : integer := 160
        );
        port (
            nRst      : in  std_logic;
            CLK       : in  std_logic;

            StateFSM  : in  StateFSM_type;
            A_FSM     : in  std_logic_vector(11 downto 0);

            nCS       : out std_logic;
            nRAS      : out std_logic;
            nCAS      : out std_logic;
            nWE       : out std_logic;
            CKE       : out std_logic;
            DQM       : out std_logic_vector(1 downto 0);
            BS        : out std_logic_vector(1 downto 0);
            A         : out std_logic_vector(11 downto 0);
            State_out : out StateSubsys_type
        );
    end component;

    component PLL_i12MHz_o160MHz
        port (
            areset : in  std_logic := '0';
            inclk0 : in  std_logic := '0';
            c0     : out std_logic;
            locked : out std_logic
        );
    end component;

    component PLL_i12MHz_o80MHz
        port (
            areset : in  std_logic := '0';
            inclk0 : in  std_logic := '0';
            c0     : out std_logic;
            locked : out std_logic
        );
    end component;

    component SdramFsm
        port (
            clk      : in  std_logic;
            nRst     : in  std_logic;

            state_subsys : in  StateSubsys_type;
            state_fsm    : out StateFSM_type;

            request_command_fifo_rden  : out std_logic;
            request_command_fifo_data  : in  std_logic_vector(61 downto 0);
            request_command_fifo_empty : in  std_logic;

            request_data_fifo_rden  : out std_logic;
            request_data_fifo_data  : in  std_logic_vector(63 downto 0);
            request_data_fifo_empty : in  std_logic;

            response_command_fifo_wren : out std_logic;
            response_command_fifo_data : out std_logic_vector(19 downto 0);
            response_command_fifo_full : in  std_logic;

            response_data_fifo_wren : out std_logic;
            response_data_fifo_data : out std_logic_vector(63 downto 0);
            response_data_fifo_full : in  std_logic;

            nCS  : out std_logic;
            nRAS : out std_logic;
            nCAS : out std_logic;
            nWE  : out std_logic;
            CKE  : out std_logic;
            DQ   : inout std_logic_vector(15 downto 0);
            DQM  : out std_logic_vector(1 downto 0);
            BS   : out std_logic_vector(1 downto 0);
            A    : out std_logic_vector(11 downto 0)
        );
    end component;

    component request_cmd_fifo
        port (
            data    : in  std_logic_vector(61 downto 0);
            rdclk   : in  std_logic;
            rdreq   : in  std_logic;
            wrclk   : in  std_logic;
            wrreq   : in  std_logic;
            q       : out std_logic_vector(61 downto 0);
            rdempty : out std_logic;
            wrfull  : out std_logic
        );
    end component;

    component request_data_fifo
        port (
            data    : in  std_logic_vector(63 downto 0);
            rdclk   : in  std_logic;
            rdreq   : in  std_logic;
            wrclk   : in  std_logic;
            wrreq   : in  std_logic;
            q       : out std_logic_vector(63 downto 0);
            rdempty : out std_logic;
            wrfull  : out std_logic
        );
    end component;

    component response_cmd_fifo
        port (
            data    : in  std_logic_vector(19 downto 0);
            rdclk   : in  std_logic;
            rdreq   : in  std_logic;
            wrclk   : in  std_logic;
            wrreq   : in  std_logic;
            q       : out std_logic_vector(19 downto 0);
            rdempty : out std_logic;
            wrfull  : out std_logic
        );
    end component;

    component response_data_fifo
        port (
            data    : in  std_logic_vector(63 downto 0);
            rdclk   : in  std_logic;
            rdreq   : in  std_logic;
            wrclk   : in  std_logic;
            wrreq   : in  std_logic;
            q       : out std_logic_vector(63 downto 0);
            rdempty : out std_logic;
            wrfull  : out std_logic
        );
    end component;

begin
    CLK_160MHz_o <= CLK_160MHz;
    CLK_80MHz_o  <= CLK_80MHz;

    ----------------------------------------------------------------
    -- PLL / reset
    ----------------------------------------------------------------
    PLL_reset <= not nRst;

    U_PLL160 : PLL_i12MHz_o160MHz
        port map (
            areset => PLL_reset,
            inclk0 => CLK_12MHz,
            c0     => CLK_160MHz,
            locked => pll_lock_160
        );

    U_PLL80 : PLL_i12MHz_o80MHz
        port map (
            areset => PLL_reset,
            inclk0 => CLK_12MHz,
            c0     => CLK_80MHz,
            locked => pll_lock_80
        );

    nRst_global <= nRst and pll_lock_160 and pll_lock_80;

    nCS_o  <= nCS_s;
    nCAS_o <= nCAS_s;
    nRAS_o <= nRAS_s;
    nWE_o  <= nWE_s;

    nCS  <= nCS_s;
    nCAS <= nCAS_s;
    nRAS <= nRAS_s;
    nWE  <= nWE_s;

    LED_ctr <= LED_r;

    request_command_fifo_read_en   <= req_cmd_rdreq_s;
    request_data_fifo_read_en      <= req_data_rdreq_s;

    response_command_fifo_write_en <= resp_cmd_wren_s;
    response_command_fifo_data     <= resp_cmd_wdata_s;

    response_data_fifo_write_en    <= resp_data_wren_s;
    response_data_fifo_data        <= resp_data_wdata_s;

    ----------------------------------------------------------------
    -- Request FIFOs: write @ 80MHz, read @ 160MHz (FSM)
    ----------------------------------------------------------------
    U_REQ_CMD_FIFO : request_cmd_fifo
        port map (
            data    => req_cmd_wdata,
            wrclk   => CLK_80MHz,
            wrreq   => req_cmd_wrreq,
            rdclk   => CLK_160MHz,
            rdreq   => req_cmd_rdreq_s,
            q       => req_cmd_q,
            rdempty => req_cmd_empty,
            wrfull  => req_cmd_full_s
        );

    U_REQ_DATA_FIFO : request_data_fifo
        port map (
            data    => req_data_wdata,
            wrclk   => CLK_80MHz,
            wrreq   => req_data_wrreq,
            rdclk   => CLK_160MHz,
            rdreq   => req_data_rdreq_s,
            q       => req_data_q,
            rdempty => req_data_empty,
            wrfull  => req_data_full_s
        );

    req_cmd_wrfull  <= req_cmd_full_s;
    req_data_wrfull <= req_data_full_s;

    ----------------------------------------------------------------
    -- Response FIFOs: write @ 160MHz (FSM), read @ 80MHz 
    ----------------------------------------------------------------
    U_RESP_CMD_FIFO : response_cmd_fifo
        port map (
            data    => resp_cmd_wdata_s,
            wrclk   => CLK_160MHz,
            wrreq   => resp_cmd_wren_s,
            rdclk   => CLK_80MHz,
            rdreq   => resp_cmd_rdreq,
            q       => resp_cmd_q,
            rdempty => resp_cmd_empty_s,
            wrfull  => resp_cmd_full_s
        );

    U_RESP_DATA_FIFO : response_data_fifo
        port map (
            data    => resp_data_wdata_s,
            wrclk   => CLK_160MHz,
            wrreq   => resp_data_wren_s,
            rdclk   => CLK_80MHz,
            rdreq   => resp_data_rdreq,
            q       => resp_data_q,
            rdempty => resp_data_empty_s,
            wrfull  => resp_data_full_s
        );

    resp_cmd_rdata   <= resp_cmd_q;
    resp_cmd_rdempty <= resp_cmd_empty_s;

    resp_data_rdata   <= resp_data_q;
    resp_data_rdempty <= resp_data_empty_s;

    U_FSM : SdramFsm
        port map (
            nRst => nRst_global,
            clk  => CLK_160MHz,

            state_subsys => State_out,
            state_fsm    => StateFSM,

            -- request reads (FSM -> rdreq_s, FIFO -> data/empty)
            request_command_fifo_rden  => req_cmd_rdreq_s,
            request_command_fifo_data  => req_cmd_q,
            request_command_fifo_empty => req_cmd_empty,

            request_data_fifo_rden  => req_data_rdreq_s,
            request_data_fifo_data  => req_data_q,
            request_data_fifo_empty => req_data_empty,

            -- response writes (FSM -> wren/wdata_s, FIFO -> full)
            response_command_fifo_wren => resp_cmd_wren_s,
            response_command_fifo_data => resp_cmd_wdata_s,
            response_command_fifo_full => resp_cmd_full_s,

            response_data_fifo_wren => resp_data_wren_s,
            response_data_fifo_data => resp_data_wdata_s,
            response_data_fifo_full => resp_data_full_s,

            -- SDRAM signals
            nCS  => nCS_FSM,
            nRAS => nRAS_FSM,
            nCAS => nCAS_FSM,
            nWE  => nWE_FSM,
            CKE  => CKE_FSM,
            DQ   => Dq,
            DQM  => DQM_FSM,
            BS   => BS_FSM,
            A    => A_FSM
        );

    U_0 : SdramSubsys
        generic map (
            Burst_length => 4,
            CAS_Latency  => 3,
            CLK_Freq_MHz => 160
        )
        port map (
            nRst      => nRst_global,
            CLK       => CLK_160MHz,
            StateFSM  => StateFSM,
            A_FSM     => A_FSM,
            nCS       => nCS_Subsys,
            nRAS      => nRAS_Subsys,
            nCAS      => nCAS_Subsys,
            nWE       => nWE_Subsys,
            CKE       => CKE_Subsys,
            DQM       => DQM_Subsys,
            BS        => BS_Subsys,
            A         => A_Subsys,
            State_out => State_out
        );

    U_2 : SdramArbiter
        port map (
            nRst        => nRst_global,
            CLK         => CLK_160MHz,
            StateFSM    => StateFSM,

            nCS_FSM     => nCS_FSM,
            nRAS_FSM    => nRAS_FSM,
            nCAS_FSM    => nCAS_FSM,
            nWE_FSM     => nWE_FSM,
            CKE_FSM     => CKE_FSM,
            DQM_FSM     => DQM_FSM,
            BS_FSM      => BS_FSM,
            A_FSM       => A_FSM,

            nCS_Subsys  => nCS_Subsys,
            nRAS_Subsys => nRAS_Subsys,
            nCAS_Subsys => nCAS_Subsys,
            nWE_Subsys  => nWE_Subsys,
            CKE_Subsys  => CKE_Subsys,
            DQM_Subsys  => DQM_Subsys,
            BS_Subsys   => BS_Subsys,
            A_Subsys    => A_Subsys,

            nCS         => nCS_s,
            nRAS        => nRAS_s,
            nCAS        => nCAS_s,
            nWE         => nWE_s,
            CKE         => CKE,
            DQM         => DQM,
            BS          => BS,
            A           => A
        );

    LED_process : process (nRst_global, CLK_160MHz) is
    begin
        if (nRst_global = '0') then
            LED_counter  <= (others => '0');
            LED_quarters <= (others => '1');
            LED_r        <= (others => '0');
            quarter_flag <= '0';
        elsif rising_edge(CLK_160MHz) then
            if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
                LED_counter <= conv_std_logic_vector(2400000, LED_counter'length);
            else
                LED_counter <= LED_counter - '1';
            end if;

            if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
                if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length) or
                    LED_quarters = conv_std_logic_vector(3, LED_quarters'length)) then
                    quarter_flag <= not quarter_flag;
                end if;
            end if;

            if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
                if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length)) then
                    LED_quarters <= conv_std_logic_vector(1, LED_quarters'length);
                elsif (LED_quarters = conv_std_logic_vector(3, LED_quarters'length)) then
                    LED_quarters <= conv_std_logic_vector(2, LED_quarters'length);
                else
                    if (quarter_flag = '0') then
                        LED_quarters <= LED_quarters + '1';
                    else
                        LED_quarters <= LED_quarters - '1';
                    end if;
                end if;
            end if;

            if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length)) then
                LED_r(1 downto 0) <= (others => '1');
                LED_r(7 downto 2) <= (others => '0');
            elsif (LED_quarters = conv_std_logic_vector(1, LED_quarters'length)) then
                LED_r(1 downto 0) <= (others => '0');
                LED_r(3 downto 2) <= (others => '1');
                LED_r(7 downto 4) <= (others => '0');
            elsif (LED_quarters = conv_std_logic_vector(2, LED_quarters'length)) then
                LED_r(3 downto 0) <= (others => '0');
                LED_r(5 downto 4) <= (others => '1');
                LED_r(7 downto 6) <= (others => '0');
            else
                LED_r(5 downto 0) <= (others => '0');
                LED_r(7 downto 6) <= (others => '1');
            end if;
        end if;
    end process;

end architecture rtl;
