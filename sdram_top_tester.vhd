library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sdram_subsys_package.all;

entity SdramTopTester is
    port (
        ----------------------------------------------------------------
        -- Наблюдаемые сигналы с топа (можно использовать в проверках)
        ----------------------------------------------------------------
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

        ----------------------------------------------------------------
        -- Интерфейс FIFO, который мы моделируем
        ----------------------------------------------------------------
        -- Request Command FIFO (чтение)
        request_command_fifo_read_en : in  std_logic;
        request_command_fifo_data    : out std_logic_vector(61 downto 0);
        request_command_fifo_empty   : out std_logic;

        -- Request Data FIFO (чтение)
        request_data_fifo_read_en : in  std_logic;
        request_data_fifo_data    : out std_logic_vector(63 downto 0);
        request_data_fifo_empty   : out std_logic;

        -- Response Command FIFO (запись)
        response_command_fifo_write_en : in  std_logic;
        response_command_fifo_data     : in  std_logic_vector(19 downto 0);
        response_command_fifo_full     : out std_logic;

        -- Response Data FIFO (запись)
        response_data_fifo_write_en : in  std_logic;
        response_data_fifo_data     : in  std_logic_vector(63 downto 0);
        response_data_fifo_full     : out std_logic;              -- <<< ДОБАВЛЕН
        response_data_fifo_used     : out std_logic_vector(9 downto 0);

        ----------------------------------------------------------------
        -- Общие сигналы, которые мы подаём на DUT
        ----------------------------------------------------------------
        nRst      : out std_logic;
        CLK_12MHz : out std_logic
    );
end entity;

architecture flow of SdramTopTester is

    ----------------------------------------------------------------
    -- Внутренний клок
    ----------------------------------------------------------------
    signal int_clk  : std_logic := '0';
    constant CLK_PRD : time := 6.25 ns; -- "быстрый" клок для симуляции

    ----------------------------------------------------------------
    -- Функция формирования команды (формат как в SdramFsm)
    ----------------------------------------------------------------
    function make_cmd(
        op_type  : std_logic;                        -- 0=READ, 1=WRITE
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

    ----------------------------------------------------------------
    -- Команды, которые будем подавать
    ----------------------------------------------------------------
    constant CMD_READ1 : std_logic_vector(61 downto 0) := make_cmd(
        '0',                                           -- READ
        "00",                                          -- банк
        std_logic_vector(to_unsigned(1, 12)),          -- row = 1
        x"00",                                         -- col = 0
        std_logic_vector(to_unsigned(16, 12)),         -- 16 байт
        x"FF",                                         -- be_first
        x"FF",                                         -- be_last
        x"01"                                          -- op_id
    );

    constant CMD_READ2 : std_logic_vector(61 downto 0) := make_cmd(
        '0',
        "01",                                          -- банк 1
        std_logic_vector(to_unsigned(2, 12)),          -- row = 2
        x"10",                                         -- col = 0x10
        std_logic_vector(to_unsigned(16, 12)),
        x"FF",
        x"FF",
        x"02"                                          -- op_id
    );

    ----------------------------------------------------------------
    -- Счётчик использованных слов в FIFO ответа
    ----------------------------------------------------------------
    signal resp_used_cnt : unsigned(9 downto 0) := (others => '0');

    ----------------------------------------------------------------
    -- FSM тестера
    ----------------------------------------------------------------
    type tester_state_t is (
        ST_RESET_HOLD,
        ST_WAIT_INIT,
        ST_PREP_READ1,
        ST_WAIT_READ1_REQ,
        ST_HOLD_READ1,
        ST_WAIT_AFTER_READ1,
        ST_PREP_READ2,
        ST_WAIT_READ2_REQ,
        ST_HOLD_READ2,
        ST_WAIT_AFTER_READ2,
        ST_DONE
    );

    signal state      : tester_state_t := ST_RESET_HOLD;
    signal cycle_cnt  : integer range 0 to 20000 := 0;

    -- сколько тактов нужно подождать (приблизительно как твои wait for)
    constant CYCLES_INIT        : integer := 800;   -- ~5 us  при 160 МГц
    constant CYCLES_AFTER_RD1   : integer := 3200;  -- ~20 us
    constant CYCLES_AFTER_RD2   : integer := 8000;  -- ~50 us

begin

    ----------------------------------------------------------------
    -- Генератор такта
    ----------------------------------------------------------------
    int_clk   <= not int_clk after CLK_PRD/2;
    CLK_12MHz <= int_clk;  -- в топе это идёт на PLL как "входной клок"

    ----------------------------------------------------------------
    -- Счётчик заполнения data-FIFO ответа
    ----------------------------------------------------------------
    resp_used_proc : process(int_clk)
    begin
        if rising_edge(int_clk) then
            if response_data_fifo_write_en = '1' then
                resp_used_cnt <= resp_used_cnt + 1;
            end if;
        end if;
    end process;

    response_data_fifo_used <= std_logic_vector(resp_used_cnt);

    ----------------------------------------------------------------
    -- Постоянные значения для неиспользуемых линий FIFO
    ----------------------------------------------------------------
    response_command_fifo_full <= '0';      -- командный FIFO никогда не полный
    response_data_fifo_full    <= '0';      -- data-FIFO тоже никогда не полный

    request_data_fifo_data  <= (others => '0'); -- write-данные не используем
    request_data_fifo_empty <= '1';             -- FIFO данных запроса всегда пуст

    ----------------------------------------------------------------
    -- Основной процесс: reset + стимулы
    ----------------------------------------------------------------
    main_proc : process(int_clk)
    begin
        if rising_edge(int_clk) then

            case state is

                ----------------------------------------------------
                when ST_RESET_HOLD =>
                    nRst <= '0';
                    request_command_fifo_empty <= '1';
                    request_command_fifo_data  <= (others => '0');
                    cycle_cnt <= cycle_cnt + 1;

                    if cycle_cnt >= 3 then
                        cycle_cnt <= 0;
                        nRst <= '1';
                        state <= ST_WAIT_INIT;
                    end if;

                ----------------------------------------------------
                when ST_WAIT_INIT =>
                    -- ждём, пока подсистема инициализирует память
                    cycle_cnt <= cycle_cnt + 1;
                    request_command_fifo_empty <= '1';

                    if cycle_cnt >= CYCLES_INIT then
                        cycle_cnt <= 0;
                        state <= ST_PREP_READ1;
                    end if;

                ----------------------------------------------------
                when ST_PREP_READ1 =>
                    -- кладём команду READ1 в FIFO
                    request_command_fifo_data  <= CMD_READ1;
                    request_command_fifo_empty <= '0';
                    state <= ST_WAIT_READ1_REQ;

                when ST_WAIT_READ1_REQ =>
                    -- ждём, пока FSM даст read_en
                    if request_command_fifo_read_en = '1' then
                        state <= ST_HOLD_READ1;
                    end if;

                when ST_HOLD_READ1 =>
                    -- один такт спустя считаем FIFO пустым
                    request_command_fifo_empty <= '1';
                    cycle_cnt <= 0;
                    state <= ST_WAIT_AFTER_READ1;

                ----------------------------------------------------
                when ST_WAIT_AFTER_READ1 =>
                    cycle_cnt <= cycle_cnt + 1;
                    if cycle_cnt >= CYCLES_AFTER_RD1 then
                        cycle_cnt <= 0;
                        state <= ST_PREP_READ2;
                    end if;

                ----------------------------------------------------
                when ST_PREP_READ2 =>
                    request_command_fifo_data  <= CMD_READ2;
                    request_command_fifo_empty <= '0';
                    state <= ST_WAIT_READ2_REQ;

                when ST_WAIT_READ2_REQ =>
                    if request_command_fifo_read_en = '1' then
                        state <= ST_HOLD_READ2;
                    end if;

                when ST_HOLD_READ2 =>
                    request_command_fifo_empty <= '1';
                    cycle_cnt <= 0;
                    state <= ST_WAIT_AFTER_READ2;

                ----------------------------------------------------
                when ST_WAIT_AFTER_READ2 =>
                    cycle_cnt <= cycle_cnt + 1;
                    if cycle_cnt >= CYCLES_AFTER_RD2 then
                        cycle_cnt <= 0;
                        state <= ST_DONE;
                    end if;

                ----------------------------------------------------
                when ST_DONE =>
                    -- тут можно потом добавить проверки,
                    -- а симуляцию остановишь по времени в ModelSim
                    null;

            end case;

        end if;
    end process;

end architecture flow;
