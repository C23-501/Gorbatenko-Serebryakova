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

        -- SDRAM pins
        nCS   : out std_logic;
        nRAS  : out std_logic;
        nCAS  : out std_logic;
        nWE   : out std_logic;
        CKE   : out std_logic;
        DQM   : out std_logic_vector(1 downto 0);
        BS    : out std_logic_vector(1 downto 0);
        A     : out std_logic_vector(11 downto 0);
        Dq    : inout std_logic_vector(15 downto 0);

        -- debug: tap DQ on separate pins
        DQ_DBG : out std_logic_vector(15 downto 0);

        -- optional debug LEDs (from top)
        LED_ctr : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of SdramTopWrapper is

    ----------------------------------------------------------------
    -- 3 constants you asked for:
    --   1) write command
    --   2) 64-bit data to write
    --   3) read command (same address)
    --
    -- Command format (62 bits):
    -- [61]            op_type
    -- [60..58]        unused/reserved (leave 0)
    -- [57..56]        bank
    -- [55..44]        row
    -- [43..36]        col
    -- [35..24]        words64
    -- [23..16]        be_first
    -- [15..8]         be_last
    -- [7..0]          op_id
    ----------------------------------------------------------------

    -- Pick an address/op_id (you can change these)
    constant C_BANK   : std_logic_vector(1 downto 0)  := "00";
    constant C_ROW    : std_logic_vector(11 downto 0) := x"012";
    constant C_COL    : std_logic_vector(7 downto 0)  := x"34";
    constant C_WORDS1 : std_logic_vector(11 downto 0) := x"001"; -- 1 word64
    constant C_BE_ALL : std_logic_vector(7 downto 0)  := x"FF";
    constant C_OPID_W : std_logic_vector(7 downto 0)  := x"A1";
    constant C_OPID_R : std_logic_vector(7 downto 0)  := x"A2";

    -- !!! If your FSM uses opposite meaning, swap '1'/'0' here.
    constant CMD_WRITE_1W64 : std_logic_vector(61 downto 0) :=
        '1' &                      -- [61] op_type = WRITE (assumption)
        "000" &                    -- [60..58] reserved
        C_BANK &                   -- [57..56]
        C_ROW  &                   -- [55..44]
        C_COL  &                   -- [43..36]
        C_WORDS1 &                 -- [35..24]
        C_BE_ALL &                 -- [23..16] be_first
        C_BE_ALL &                 -- [15..8]  be_last
        C_OPID_W;                  -- [7..0]   op_id

    constant DATA_WRITE_64 : std_logic_vector(63 downto 0) :=
        x"1122334455667788";

    constant CMD_READ_1W64 : std_logic_vector(61 downto 0) :=
        '0' &                      -- [61] op_type = READ (assumption)
        "000" &                    -- [60..58] reserved
        C_BANK &                   -- [57..56]
        C_ROW  &                   -- [55..44]
        C_COL  &                   -- [43..36]
        C_WORDS1 &                 -- [35..24]
        C_BE_ALL &                 -- [23..16] be_first (может игнориться при чтении)
        C_BE_ALL &                 -- [15..8]  be_last
        C_OPID_R;                  -- [7..0]   op_id


    ----------------------------------------------------------------
    -- Wires to SdramTop
    ----------------------------------------------------------------
    signal nCS_o  : std_logic;
    signal nRAS_o : std_logic;
    signal nCAS_o : std_logic;
    signal nWE_o  : std_logic;

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

    -- (these exist on SdramTop but we don't need them outside)
    signal request_command_fifo_read_en   : std_logic;
    signal request_data_fifo_read_en      : std_logic;
    signal response_command_fifo_write_en : std_logic;
    signal response_command_fifo_data     : std_logic_vector(19 downto 0);
    signal response_data_fifo_write_en    : std_logic;
    signal response_data_fifo_data        : std_logic_vector(63 downto 0);

    ----------------------------------------------------------------
    -- Simple sequencer @ 80MHz (because request FIFO write clock is 80MHz)
    ----------------------------------------------------------------
    type t_state is (
        ST_WAIT_INIT,
        ST_PUSH_WR_CMD,
        ST_PUSH_WR_DATA,
        ST_GAP_BEFORE_RD,
        ST_PUSH_RD_CMD,
        ST_DONE
    );
    signal st : t_state;

    -- wait counters (tweak if needed)
    constant INIT_WAIT_CYCLES : std_logic_vector(23 downto 0) := conv_std_logic_vector(800000, 24);
    -- 800k @80MHz ~= 10ms (с запасом для init)
    constant GAP_WAIT_CYCLES  : std_logic_vector(23 downto 0) := conv_std_logic_vector(80000, 24);
    -- 80k @80MHz ~= 1ms

    signal wait_cnt : std_logic_vector(23 downto 0);
    
    constant C_ZERO_24 : std_logic_vector(23 downto 0) := (others => '0');
    constant C_ONE_24  : std_logic_vector(23 downto 0) := conv_std_logic_vector(1, 24);

begin

    ----------------------------------------------------------------
    -- Tap DQ to debug pins
    ----------------------------------------------------------------
    DQ_DBG <= Dq;

    ----------------------------------------------------------------
    -- Instantiate your SdramTop
    ----------------------------------------------------------------
    U_TOP : entity work.SdramTop
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

            nCS_o  => nCS_o,
            nRAS_o => nRAS_o,
            nCAS_o => nCAS_o,
            nWE_o  => nWE_o,

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
            response_command_fifo_data     => response_command_fifo_data,
            response_data_fifo_write_en    => response_data_fifo_write_en,
            response_data_fifo_data        => response_data_fifo_data,

            LED_ctr => LED_ctr
        );

    ----------------------------------------------------------------
    -- Default assignments
    ----------------------------------------------------------------
    req_cmd_wrreq  <= '0' when (st /= ST_PUSH_WR_CMD and st /= ST_PUSH_RD_CMD) else '1';
    req_data_wrreq <= '0' when (st /= ST_PUSH_WR_DATA) else '1';

    -- Put proper wdata depending on what we push
    req_cmd_wdata  <= CMD_WRITE_1W64 when (st = ST_PUSH_WR_CMD) else
                      CMD_READ_1W64  when (st = ST_PUSH_RD_CMD) else
                      (others => '0');

    req_data_wdata <= DATA_WRITE_64 when (st = ST_PUSH_WR_DATA) else (others => '0');

    ----------------------------------------------------------------
    -- Drain responses continuously (so FIFOs don't overflow)
    -- One-cycle read when not empty.
    ----------------------------------------------------------------
    resp_cmd_rdreq  <= not resp_cmd_rdempty;
    resp_data_rdreq <= not resp_data_rdempty;

    ----------------------------------------------------------------
    -- Sequencer process @ 80MHz
    ----------------------------------------------------------------
    process (nRst, CLK_80MHz_o)
begin
    if (nRst = '0') then
        st       <= ST_WAIT_INIT;
        wait_cnt <= C_ZERO_24;

    elsif rising_edge(CLK_80MHz_o) then

        case st is

            when ST_WAIT_INIT =>
                if (wait_cnt = C_ZERO_24) then
                    wait_cnt <= INIT_WAIT_CYCLES;
                else
                    wait_cnt <= wait_cnt - C_ONE_24;
                    if (wait_cnt = C_ONE_24) then
                        st <= ST_PUSH_WR_CMD;
                    end if;
                end if;

            when ST_PUSH_WR_CMD =>
                if (req_cmd_wrfull = '0') then
                    st <= ST_PUSH_WR_DATA;
                end if;

            when ST_PUSH_WR_DATA =>
                if (req_data_wrfull = '0') then
                    st       <= ST_GAP_BEFORE_RD;
                    wait_cnt <= GAP_WAIT_CYCLES;
                end if;

            when ST_GAP_BEFORE_RD =>
                if (wait_cnt = C_ZERO_24) then
                    st <= ST_PUSH_RD_CMD;
                else
                    wait_cnt <= wait_cnt - C_ONE_24;
                end if;

            when ST_PUSH_RD_CMD =>
                if (req_cmd_wrfull = '0') then
                    st <= ST_DONE;
                end if;

            when others =>
                st <= ST_DONE;

        end case;
    end if;
end process;


end architecture;
