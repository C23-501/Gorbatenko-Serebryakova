LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;

LIBRARY work;
USE work.sdram_subsys_package.ALL;  -- важно: пакет с типами StateFSM_type / StateSubsys_type

LIBRARY altera_mf;
USE altera_mf.all;

entity SdramTop is
    port (
        -- Общие
        nRst      : in  std_logic;
        CLK_12MHz : in  std_logic;

        -- Интерфейс к SDRAM (через арбитр + подсистема + FSM)
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

        -- Интерфейс к FIFO (Avalon-часть FSM)
        -- Request Command FIFO (чтение)
        request_command_fifo_read_en : out std_logic;
        request_command_fifo_data    : in  std_logic_vector(61 downto 0);
        request_command_fifo_empty   : in  std_logic;

        -- Request Data FIFO (чтение)
        request_data_fifo_read_en : out std_logic;
        request_data_fifo_data    : in  std_logic_vector(63 downto 0);
        request_data_fifo_empty   : in  std_logic;

        -- Response Command FIFO (запись)
        response_command_fifo_write_en : out std_logic;
        response_command_fifo_data     : out std_logic_vector(19 downto 0);
        response_command_fifo_full     : in  std_logic;

        -- Response Data FIFO (запись)
        response_data_fifo_write_en : out std_logic;
        response_data_fifo_data     : out std_logic_vector(63 downto 0);
		response_data_fifo_full     : in std_logic;

        -- LEDs
        LED_ctr : out std_logic_vector(7 downto 0)
    );
end SdramTop;


architecture rtl of SdramTop is

    -- Линии от FSM и подсистемы к арбитру
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

    -- Локальные копии команд на SDRAM
    signal nCS_s  : std_logic;
    signal nCAS_s : std_logic;
    signal nRAS_s : std_logic;
    signal nWE_s  : std_logic;

    -- Клок и сброс от PLL
    signal CLK_160MHz  : std_logic;
    signal PLL_reset   : std_logic;
    signal nRst_global : std_logic;

    --------------------------------------------------------------------
    -- COMPONENT объявления
    --------------------------------------------------------------------

    component SdramArbiter
        port (
            -- Общие
            nRst        : in  std_logic;
            CLK         : in  std_logic;
            -- От FSM
            StateFSM    : in  StateFSM_type;
            nCS_FSM     : in  std_logic;
            nRAS_FSM    : in  std_logic;
            nCAS_FSM    : in  std_logic;
            nWE_FSM     : in  std_logic;
            CKE_FSM     : in  std_logic;
            DQM_FSM     : in  std_logic_vector(1 downto 0);
            BS_FSM      : in  std_logic_vector(1 downto 0);
            A_FSM       : in  std_logic_vector(11 downto 0);
            -- От подсистемы
            nCS_Subsys  : in  std_logic;
            nRAS_Subsys : in  std_logic;
            nCAS_Subsys : in  std_logic;
            nWE_Subsys  : in  std_logic;
            CKE_Subsys  : in  std_logic;
            DQM_Subsys  : in  std_logic_vector(1 downto 0);
            BS_Subsys   : in  std_logic_vector(1 downto 0);
            A_Subsys    : in  std_logic_vector(11 downto 0);
            -- Выходы на SDRAM
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
            Burst_length : integer := 8;
            CAS_Latency  : integer := 3;
            CLK_Freq_MHz : integer := 160
        );
        port (
            -- Общие
            nRst      : in  std_logic;
            CLK       : in  std_logic;
            -- Входы с FSM
            StateFSM  : in  StateFSM_type;
            A_FSM     : in  std_logic_vector(11 downto 0);
            -- Выходы на арбитр
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

    -- FSM
    component SdramFsm
        port (
            -- Общие
            clk      : in  std_logic;
            nRst     : in  std_logic;

            -- Взаимодействие с Subsystem
            state_subsys : in  StateSubsys_type;
            state_fsm    : out StateFSM_type;

            -- Взаимодействие с Avalon / FIFO
            -- Чтение
            request_command_fifo_rden : out std_logic;
            request_command_fifo_data    : in  std_logic_vector(61 downto 0);
            request_command_fifo_empty   : in  std_logic;

            request_data_fifo_rden : out std_logic;
            request_data_fifo_data    : in  std_logic_vector(63 downto 0);
            request_data_fifo_empty   : in  std_logic;

            -- Запись
            response_command_fifo_wren : out std_logic;
            response_command_fifo_data     : out std_logic_vector(19 downto 0);
            response_command_fifo_full     : in  std_logic;

            response_data_fifo_wren : out std_logic;
            response_data_fifo_data     : out std_logic_vector(63 downto 0);
			response_data_fifo_full     : in  std_logic;

            -- Выходы на арбитр SDRAM
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

begin

    CLK_160MHz_o <= CLK_160MHz;
    ----------------------------------------------------------------
    -- Связка PLL / reset
    ----------------------------------------------------------------
    PLL_reset <= not nRst;

    U_4 : PLL_i12MHz_o160MHz
        port map (
            areset => PLL_reset,
            inclk0 => CLK_12MHz,
            c0     => CLK_160MHz,
            locked => nRst_global
        );

    ----------------------------------------------------------------
    -- Выводы на пины/отладку
    ----------------------------------------------------------------
    nCS_o  <= nCS_s;
    nCAS_o <= nCAS_s;
    nRAS_o <= nRAS_s;
    nWE_o  <= nWE_s;

    nCS  <= nCS_s;
    nCAS <= nCAS_s;
    nRAS <= nRAS_s;
    nWE  <= nWE_s;

    LED_ctr <= LED_r;

    ----------------------------------------------------------------
    -- Инстанс FSM
    ----------------------------------------------------------------
    U_FSM : SdramFsm
        port map (
            nRst => nRst_global,
            clk  => CLK_160MHz,

            state_subsys => State_out,
            state_fsm    => StateFSM,

            -- FIFO-интерфейсы наружу
            request_command_fifo_rden => request_command_fifo_read_en,
            request_command_fifo_data    => request_command_fifo_data,
            request_command_fifo_empty   => request_command_fifo_empty,

            request_data_fifo_rden => request_data_fifo_read_en,
            request_data_fifo_data    => request_data_fifo_data,
            request_data_fifo_empty   => request_data_fifo_empty,

            response_command_fifo_wren => response_command_fifo_write_en,
            response_command_fifo_data     => response_command_fifo_data,
            response_command_fifo_full     => response_command_fifo_full,

            response_data_fifo_wren => response_data_fifo_write_en,
            response_data_fifo_data     => response_data_fifo_data,
			response_data_fifo_full     => response_data_fifo_full,

            -- Выходы на арбитр
            nCS  => nCS_FSM,
            nRAS => nRAS_FSM,
            nCAS => nCAS_FSM,
            nWE  => nWE_FSM,
            CKE  => CKE_FSM,
            DQ   => Dq,        -- напрямую на внешний порт
            DQM  => DQM_FSM,
            BS   => BS_FSM,
            A    => A_FSM
        );

    ----------------------------------------------------------------
    -- Подсистема и арбитр (как у тебя было)
    ----------------------------------------------------------------
    U_0 : SdramSubsys
        generic map (
            Burst_length => 8,
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

    ----------------------------------------------------------------
    -- Процесс для бегущих огоньков (как у тебя)
    ----------------------------------------------------------------
    LED_process : process (nRst_global, CLK_160MHz) is
    begin
        if (nRst = '0') then
            LED_counter  <= (others => '0');
            LED_quarters <= (others => '1');
            LED_r        <= (others => '0');
            quarter_flag <= '0';
        elsif rising_edge(CLK_160MHz) then
            --  LED_counter
            if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
                LED_counter <= conv_std_logic_vector(2400000, LED_counter'length);
            else
                LED_counter <= LED_counter - '1';
            end if;
            --  quater_flag
            if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
                if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length) or
                    LED_quarters = conv_std_logic_vector(3, LED_quarters'length)) then
                    quarter_flag <= not quarter_flag;
                end if;
            end if;
            --  LED_quarters
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
            --  LED_r
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
