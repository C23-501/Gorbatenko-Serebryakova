library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SdramTopTester is
    port (
        CLK_80MHz  : in  std_logic;
        CLK_160MHz : in  std_logic;

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

        req_cmd_wrreq  : out std_logic;
        req_cmd_wdata  : out std_logic_vector(61 downto 0);
        req_cmd_wrfull : in  std_logic;

        req_data_wrreq  : out std_logic;
        req_data_wdata  : out std_logic_vector(63 downto 0);
        req_data_wrfull : in  std_logic;

        resp_cmd_rdreq   : out std_logic;
        resp_cmd_rdata   : in  std_logic_vector(19 downto 0);
        resp_cmd_rdempty : in  std_logic;

        resp_data_rdreq   : out std_logic;
        resp_data_rdata   : in  std_logic_vector(63 downto 0);
        resp_data_rdempty : in  std_logic;

        nRst      : out std_logic;
        CLK_12MHz : out std_logic
    );
end entity;

architecture flow of SdramTopTester is

    signal clk12_i : std_logic := '0';
    constant CLK12_PRD : time := 83.333 ns;

    signal nRst_i           : std_logic := '0';
    signal resp_cmd_rdreq_i : std_logic := '0';
    signal resp_data_rdreq_i: std_logic := '0';
    signal req_cmd_wrreq_i  : std_logic := '0';
    signal req_data_wrreq_i : std_logic := '0';
    signal req_cmd_wdata_i  : std_logic_vector(61 downto 0) := (others => '0');
    signal req_data_wdata_i : std_logic_vector(63 downto 0) := (others => '0');

    signal rst_cnt : integer range 0 to 200 := 0;

    function make_cmd(
        op_type  : std_logic;
        bank     : std_logic_vector(1 downto 0);
        row_addr : std_logic_vector(11 downto 0);
        col_addr : std_logic_vector(7 downto 0);
        words64  : std_logic_vector(11 downto 0);
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
        r(35 downto 24) := words64;
        r(23 downto 16) := be_first;
        r(15 downto 8)  := be_last;
        r(7 downto 0)   := op_id;
        return r;
    end function;

    constant CMD_WRITE1 : std_logic_vector(61 downto 0) := make_cmd(
        '1', "11", std_logic_vector(to_unsigned(4095, 12)), x"FC",
        std_logic_vector(to_unsigned(4, 12)),
        x"FF", x"FF", x"10"
    );

    constant CMD_READ1 : std_logic_vector(61 downto 0) := make_cmd(
        '0', "11", std_logic_vector(to_unsigned(4095, 12)), x"FC",
        std_logic_vector(to_unsigned(4, 12)),
        x"FF", x"FF", x"11"
    );

    type t_cmd_mem is array (0 to 1) of std_logic_vector(61 downto 0);
    constant CMDQ : t_cmd_mem := (CMD_WRITE1, CMD_READ1);
    signal cmd_idx : integer range 0 to 2 := 0;

    type t_data_mem is array (0 to 3) of std_logic_vector(63 downto 0);

--    constant DATAQ : t_data_mem := (
--        x"0000000000000001",
--        x"0000000000000002",
--        x"0000000000000003",
--        x"0000000000000004"
--    );

    constant DATAQ : t_data_mem := (
      x"1122334455667788",
      x"99AABBCCDDEEFF00",
      x"0123456789ABCDEF",
      x"FEDCBA9876543210"
    );

    signal data_idx : integer range 0 to 4 := 0;

    signal started_80 : std_logic := '0';
    signal wait80_cnt : integer range 0 to 500 := 0;

    signal resp_cmd_rdreq_d  : std_logic := '0';
    signal resp_cmd_empty_d  : std_logic := '1';
    signal resp_data_rdreq_d : std_logic := '0';
    signal resp_data_empty_d : std_logic := '1';

    function nibble_to_char(n : std_logic_vector(3 downto 0)) return character is
        variable v : integer;
    begin
        if (n = "0000") then return '0'; end if;
        if (n = "0001") then return '1'; end if;
        if (n = "0010") then return '2'; end if;
        if (n = "0011") then return '3'; end if;
        if (n = "0100") then return '4'; end if;
        if (n = "0101") then return '5'; end if;
        if (n = "0110") then return '6'; end if;
        if (n = "0111") then return '7'; end if;
        if (n = "1000") then return '8'; end if;
        if (n = "1001") then return '9'; end if;
        if (n = "1010") then return 'A'; end if;
        if (n = "1011") then return 'B'; end if;
        if (n = "1100") then return 'C'; end if;
        if (n = "1101") then return 'D'; end if;
        if (n = "1110") then return 'E'; end if;
        return 'F';
    end function;

    function slv_to_hex(slv : std_logic_vector) return string is
        constant N : integer := (slv'length + 3) / 4; -- hex digits
        variable padded : std_logic_vector(N*4-1 downto 0) := (others => '0');
        variable res    : string(1 to N);
        variable i      : integer;
        variable nib    : std_logic_vector(3 downto 0);
    begin
        -- align slv into LSB of padded
        padded(slv'length-1 downto 0) := slv;

        for k in 0 to N-1 loop
            i   := N - k; -- string index (1..N)
            nib := padded(k*4+3 downto k*4);
            res(i) := nibble_to_char(nib);
        end loop;
        return res;
    end function;

begin

    nRst <= nRst_i;

    req_cmd_wrreq <= req_cmd_wrreq_i;
    req_cmd_wdata <= req_cmd_wdata_i;

    req_data_wrreq <= req_data_wrreq_i;
    req_data_wdata <= req_data_wdata_i;

    resp_cmd_rdreq  <= resp_cmd_rdreq_i;
    resp_data_rdreq <= resp_data_rdreq_i;

    clk12_i   <= not clk12_i after CLK12_PRD/2;
    CLK_12MHz <= clk12_i;

    process(clk12_i)
    begin
        if rising_edge(clk12_i) then
            if rst_cnt < 40 then
                rst_cnt <= rst_cnt + 1;
                nRst_i <= '0';
            else
                nRst_i <= '1';
            end if;
        end if;
    end process;

    process(CLK_80MHz)
    begin
        if rising_edge(CLK_80MHz) then
            if nRst_i = '0' then
                started_80 <= '0';
                wait80_cnt <= 0;
            else
                if started_80 = '0' then
                    if wait80_cnt < 50 then
                        wait80_cnt <= wait80_cnt + 1;
                    else
                        started_80 <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(CLK_80MHz)
    begin
        if rising_edge(CLK_80MHz) then
            req_cmd_wrreq_i  <= '0';
            req_data_wrreq_i <= '0';
            req_cmd_wdata_i  <= (others => '0');
            req_data_wdata_i <= (others => '0');

            if nRst_i = '0' or started_80 = '0' then
                cmd_idx  <= 0;
                data_idx <= 0;
            else
                if data_idx < 4 and req_data_wrfull = '0' then
                    req_data_wrreq_i <= '1';
                    req_data_wdata_i <= DATAQ(data_idx);
                    data_idx <= data_idx + 1;
                end if;

                if cmd_idx < 2 and req_cmd_wrfull = '0' then
                    req_cmd_wrreq_i <= '1';
                    req_cmd_wdata_i <= CMDQ(cmd_idx);
                    cmd_idx <= cmd_idx + 1;
                end if;
            end if;
        end if;
    end process;

    process(CLK_80MHz)
        variable got_words64 : integer;
        variable got_id      : integer;
    begin
        if rising_edge(CLK_80MHz) then
            resp_cmd_rdreq_i  <= '0';
            resp_data_rdreq_i <= '0';

            if nRst_i = '0' or started_80 = '0' then
                resp_cmd_rdreq_d  <= '0';
                resp_cmd_empty_d  <= '1';
                resp_data_rdreq_d <= '0';
                resp_data_empty_d <= '1';
            else
                if resp_cmd_rdempty = '0' then
                    resp_cmd_rdreq_i <= '1';
                end if;

                if resp_data_rdempty = '0' then
                    resp_data_rdreq_i <= '1';
                end if;

                resp_cmd_rdreq_d <= resp_cmd_rdreq_i;
                resp_cmd_empty_d <= resp_cmd_rdempty;

                resp_data_rdreq_d <= resp_data_rdreq_i;
                resp_data_empty_d <= resp_data_rdempty;

                if resp_cmd_rdreq_d = '1' and resp_cmd_empty_d = '0' then
                    got_words64 := to_integer(unsigned(resp_cmd_rdata(19 downto 8)));
                    got_id      := to_integer(unsigned(resp_cmd_rdata(7 downto 0)));
                    report "RESP_CMD: words64=" & integer'image(got_words64) &
                           " op_id=" & integer'image(got_id);
                end if;

                if resp_data_rdreq_d = '1' and resp_data_empty_d = '0' then
                    report "RESP_DATA: 0x" & slv_to_hex(resp_data_rdata);
                end if;
            end if;
        end if;
    end process;

end architecture;
