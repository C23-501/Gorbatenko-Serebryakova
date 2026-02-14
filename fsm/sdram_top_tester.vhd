library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SdramTopTester is
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

        nRst      : out std_logic;
        CLK_12MHz : out std_logic
    );
end entity;

architecture flow of SdramTopTester is
    signal int_clk : std_logic := '0';
    constant CLK_PRD : time := 83.333 ns;

    function make_cmd(
        op_type  : std_logic;
        bank     : std_logic_vector(1 downto 0);
        row_addr : std_logic_vector(11 downto 0);
        col_addr : std_logic_vector(7 downto 0);
        data_len : std_logic_vector(11 downto 0);
        be_first : std_logic_vector(7 downto 0);
        be_last  : std_logic_vector(7 downto 0);
        op_id    : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
        variable r : std_logic_vector(61 downto 0);
    begin
        r := (others => '0');
        r(61)           := op_type;
        r(57 downto 56) := bank;
        r(55 downto 44) := row_addr;
        r(43 downto 36) := col_addr;
        r(35 downto 24) := data_len;
        r(23 downto 16) := be_first;
        r(15 downto 8)  := be_last;
        r(7 downto 0)   := op_id;
        return r;
    end function;

    constant CMD_READ1 : std_logic_vector(61 downto 0) := make_cmd(
        '0', "00", std_logic_vector(to_unsigned(1, 12)), x"00",
        std_logic_vector(to_unsigned(16, 12)),
        x"FF", x"FF", x"01"
    );

    constant CMD_READ2 : std_logic_vector(61 downto 0) := make_cmd(
        '0', "01", std_logic_vector(to_unsigned(2, 12)), x"10",
        std_logic_vector(to_unsigned(16, 12)),
        x"FF", x"FF", x"02"
    );

    type t_cmd_mem is array (0 to 1) of std_logic_vector(61 downto 0);
    constant CMDQ : t_cmd_mem := (CMD_READ1, CMD_READ2);

    signal cmd_idx : integer range 0 to 2 := 0;
    signal rst_cnt : integer range 0 to 31 := 0;
begin
    int_clk <= not int_clk after CLK_PRD/2;
    CLK_12MHz <= int_clk;

    response_command_fifo_full <= '0';
    response_data_fifo_full    <= '0';

    request_data_fifo_data  <= (others => '0');
    request_data_fifo_empty <= '1';

    process(int_clk)
    begin
        if rising_edge(int_clk) then
            if rst_cnt < 10 then
                rst_cnt <= rst_cnt + 1;
                nRst <= '0';
                cmd_idx <= 0;
                request_command_fifo_empty <= '1';
                request_command_fifo_data  <= (others => '0');
            else
                nRst <= '1';

                if cmd_idx < 2 then
                    request_command_fifo_empty <= '0';
                    request_command_fifo_data  <= CMDQ(cmd_idx);
                else
                    request_command_fifo_empty <= '1';
                    request_command_fifo_data  <= (others => '0');
                end if;

                if request_command_fifo_read_en = '1' then
                    if cmd_idx < 2 then
                        cmd_idx <= cmd_idx + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
