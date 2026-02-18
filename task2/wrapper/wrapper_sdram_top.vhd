LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;

LIBRARY work;
USE work.sdram_subsys_package.ALL;

entity SdramTopWrapper is
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

        nCS_DBG  : out std_logic;
        nRAS_DBG : out std_logic;
        nCAS_DBG : out std_logic;
        nWE_DBG  : out std_logic;

        DQ0_DBG        : out std_logic;
        FSM_ACTIVE_DBG : out std_logic;
        RESP_VALID_DBG : out std_logic;
        WREN           : out std_logic;

        RD_LOAD_DBG  : out std_logic;
        WR_SHIFT_DBG : out std_logic;
        CLK_160MHz_DBG : out std_logic
    );
end entity;

architecture rtl of SdramTopWrapper is

    constant C_BANK   : std_logic_vector(1 downto 0)  := "00";
    constant C_ROW    : std_logic_vector(11 downto 0) := x"012";
    constant C_COL    : std_logic_vector(7 downto 0)  := x"34";
    constant C_WORDS1 : std_logic_vector(11 downto 0) := x"001";
    constant C_BE_ALL : std_logic_vector(7 downto 0)  := x"FF";
    constant C_OPID_W : std_logic_vector(7 downto 0)  := x"A1";
    constant C_OPID_R : std_logic_vector(7 downto 0)  := x"A2";

    constant CMD_WRITE_1W64 : std_logic_vector(61 downto 0) :=
        '1' & "000" & C_BANK & C_ROW & C_COL & C_WORDS1 & C_BE_ALL & C_BE_ALL & C_OPID_W;

    constant DATA_WRITE_64 : std_logic_vector(63 downto 0) :=
        x"1122334455667788";

    constant CMD_READ_1W64 : std_logic_vector(61 downto 0) :=
        '0' & "000" & C_BANK & C_ROW & C_COL & C_WORDS1 & C_BE_ALL & C_BE_ALL & C_OPID_R;

    signal nCS_s, nRAS_s, nCAS_s, nWE_s : std_logic;
    signal CKE_s : std_logic;
    signal DQM_s : std_logic_vector(1 downto 0);
    signal BS_s  : std_logic_vector(1 downto 0);
    signal A_s   : std_logic_vector(11 downto 0);

    signal CLK_160MHz_o : std_logic;
    signal CLK_80MHz_o  : std_logic;

    signal req_cmd_wrreq  : std_logic;
    signal req_cmd_wdata  : std_logic_vector(61 downto 0);
    signal req_cmd_wrfull : std_logic;

    signal req_data_wrreq  : std_logic;
    signal req_data_wdata  : std_logic_vector(63 downto 0);
    signal req_data_wrfull : std_logic;

    signal resp_cmd_rdreq   : std_logic;
    signal resp_cmd_rdata   : std_logic_vector(19 downto 0);
    signal resp_cmd_rdempty : std_logic;

    signal resp_data_rdreq   : std_logic;
    signal resp_data_rdata   : std_logic_vector(63 downto 0);
    signal resp_data_rdempty : std_logic;

    signal request_command_fifo_read_en   : std_logic;
    signal request_data_fifo_read_en      : std_logic;
    signal response_command_fifo_write_en : std_logic;
    signal response_data_fifo_write_en    : std_logic;

    signal rd_load_dbg_s  : std_logic;
    signal wr_shift_dbg_s : std_logic;

    type t_state is (ST_INIT, ST_WAIT1, ST_WR_CMD, ST_WR_DATA, ST_WAIT2, ST_RD_CMD, ST_DONE);
    signal st : t_state;

    signal wait_cnt : std_logic_vector(9 downto 0);

    constant C_WAIT  : std_logic_vector(9 downto 0) :=
        conv_std_logic_vector(800, 10);

    signal wrapper_running_s : std_logic;
    signal fsm_active_s      : std_logic;
    signal resp_valid_s      : std_logic;

    signal req_cmd_wrreq_r   : std_logic := '0';
    signal req_data_wrreq_r  : std_logic := '0';
    signal resp_cmd_rdreq_r  : std_logic := '0';
    signal resp_data_rdreq_r : std_logic := '0';

begin

    ----------------------------------------------------------------
    -- Outputs
    ----------------------------------------------------------------
    nCS  <= nCS_s;
    nRAS <= nRAS_s;
    nCAS <= nCAS_s;
    nWE  <= nWE_s;
    CKE  <= CKE_s;
    DQM  <= DQM_s;
    BS   <= BS_s;
    A    <= A_s;

    nCS_DBG  <= nCS_s;
    nRAS_DBG <= nRAS_s;
    nCAS_DBG <= nCAS_s;
    nWE_DBG  <= nWE_s;

    DQ0_DBG <= Dq(0);
    WREN <= req_cmd_wrreq;

    ----------------------------------------------------------------
    -- FSM activity detection
    ----------------------------------------------------------------
    wrapper_running_s <= '1' when (st /= ST_DONE) else '0';

    fsm_active_s <= request_command_fifo_read_en or
                    request_data_fifo_read_en or
                    response_command_fifo_write_en or
                    response_data_fifo_write_en or
                    wrapper_running_s;

    FSM_ACTIVE_DBG <= fsm_active_s;

    resp_valid_s <= (not resp_cmd_rdempty) or (not resp_data_rdempty);
    RESP_VALID_DBG <= resp_valid_s;

    RD_LOAD_DBG <= rd_load_dbg_s;
    WR_SHIFT_DBG <= wr_shift_dbg_s;

    CLK_160MHz_DBG <= CLK_160MHz_o;

    U_TOP : entity work.SdramTop
        port map (
            nRst      => nRst,
            CLK_12MHz => CLK_12MHz,

            nCS  => nCS_s,
            nRAS => nRAS_s,
            nCAS => nCAS_s,
            nWE  => nWE_s,
            CKE  => CKE_s,
            DQM  => DQM_s,
            BS   => BS_s,
            A    => A_s,
            Dq   => Dq,

            nCS_o  => open,
            nRAS_o => open,
            nCAS_o => open,
            nWE_o  => open,

            CLK_160MHz_o => CLK_160MHz_o,
            CLK_80MHz_o  => CLK_80MHz_o,

            req_cmd_wrreq  => req_cmd_wrreq,
            req_cmd_wdata  => req_cmd_wdata,
            req_cmd_wrfull => req_cmd_wrfull,

            req_data_wrreq  => req_data_wrreq,
            req_data_wdata  => req_data_wdata,
            req_data_wrfull => req_data_wrfull,

            resp_cmd_rdreq   => resp_cmd_rdreq,
            resp_cmd_rdata   => resp_cmd_rdata,
            resp_cmd_rdempty => resp_cmd_rdempty,

            resp_data_rdreq   => resp_data_rdreq,
            resp_data_rdata   => resp_data_rdata,
            resp_data_rdempty => resp_data_rdempty,

            request_command_fifo_read_en   => request_command_fifo_read_en,
            request_data_fifo_read_en      => request_data_fifo_read_en,
            response_command_fifo_write_en => response_command_fifo_write_en,
            response_command_fifo_data     => open,
            response_data_fifo_write_en    => response_data_fifo_write_en,
            response_data_fifo_data        => open,

            rd_load_out => rd_load_dbg_s,
            wr_shift_out => wr_shift_dbg_s,

            LED_ctr => open
        );

    req_cmd_wrreq  <= req_cmd_wrreq_r;
    req_data_wrreq <= req_data_wrreq_r;

    req_cmd_wdata  <= CMD_WRITE_1W64 when (st = ST_WR_CMD) else
                      CMD_READ_1W64  when (st = ST_RD_CMD) else
                      (others => '0');

    req_data_wdata <= DATA_WRITE_64;

    -- Read responses on 80 MHz domain (registered)
    resp_cmd_rdreq  <= resp_cmd_rdreq_r;
    resp_data_rdreq <= resp_data_rdreq_r;


    process(nRst, CLK_80MHz_o)
    begin
        if nRst = '0' then
            st <= ST_INIT;

        elsif rising_edge(CLK_80MHz_o) then
            case st is

                when ST_INIT =>
                    st <= ST_WAIT1;

                when ST_WAIT1 =>
                    if wait_cnt = conv_std_logic_vector(0, wait_cnt'length) then
                        st <= ST_WR_DATA;
                    end if;

                when ST_WR_DATA =>
                    st <= ST_WR_CMD;

                when ST_WR_CMD =>
                    st <= ST_WAIT2;

                when ST_WAIT2 =>
                    if wait_cnt = conv_std_logic_vector(0, wait_cnt'length) then
                        st <= ST_RD_CMD;
                    end if;

                when ST_RD_CMD =>
                    st <= ST_DONE;

                when ST_DONE =>
                    st <= ST_DONE;

            end case;
        end if;
    end process;

    process(nRst, CLK_80MHz_o)
    begin
        if nRst = '0' then
            wait_cnt <= (others => '0');

            req_cmd_wrreq_r   <= '0';
            req_data_wrreq_r  <= '0';
            resp_cmd_rdreq_r  <= '0';
            resp_data_rdreq_r <= '0';

        elsif rising_edge(CLK_80MHz_o) then
            resp_cmd_rdreq_r  <= not resp_cmd_rdempty;
            resp_data_rdreq_r <= not resp_data_rdempty;

            if st = ST_INIT then
                wait_cnt <= C_WAIT;
            elsif st = ST_WR_CMD then
                wait_cnt <= C_WAIT;
            elsif wait_cnt /= conv_std_logic_vector(0, wait_cnt'length) then
                wait_cnt <= wait_cnt - 1;
            end if;

            if st = ST_WAIT1 and wait_cnt = conv_std_logic_vector(0, wait_cnt'length) then
                req_data_wrreq_r <= '1';
            else
                req_data_wrreq_r <= '0';
            end if;

            if st = ST_WR_DATA then
                req_cmd_wrreq_r <= '1';
            elsif st = ST_WAIT2 and wait_cnt = conv_std_logic_vector(0, wait_cnt'length) then
                req_cmd_wrreq_r <= '0';
            end if;

        end if;
    end process;


end architecture;
