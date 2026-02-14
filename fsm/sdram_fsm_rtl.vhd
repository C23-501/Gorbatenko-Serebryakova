library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.math_real.all;

library work;
use work.sdram_subsys_package.all;

entity SdramFsm is
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
        -- Общие
        nRst          : in  std_logic;
        clk           : in  std_logic;

        -- Взаимодействие с Subsystem
        state_subsys   : in  StateSubsys_type;
        state_fsm      : out StateFSM_type;

        -- Взаимодействие с Avalon
        -- Чтение
        request_command_fifo_rden   : out std_logic;
        request_command_fifo_data   : in  std_logic_vector(61 downto 0);
        request_command_fifo_empty  : in  std_logic;

        request_data_fifo_rden      : out std_logic;
        request_data_fifo_data      : in  std_logic_vector(63 downto 0);
        request_data_fifo_empty     : in  std_logic;

        -- Запись
        response_command_fifo_wren  : out std_logic;
        response_command_fifo_data  : out std_logic_vector(19 downto 0);
        response_command_fifo_full  : in  std_logic;

        response_data_fifo_wren     : out std_logic;
        response_data_fifo_data     : out std_logic_vector(63 downto 0);
        response_data_fifo_full     : in std_logic;

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
end SdramFsm;

architecture rtl of SdramFsm is
  
    type t_fifo_fsm_state is (
        IDLE,

        RDEN_REQUEST_CMD_FIFO,
        WAIT_REQUEST_CMD_FIFO,

        PREPARE_REQUEST,
        
        START_READ_OP,
        READING,
        UNLOAD_READ_SHIFT_REG,
        
        LOAD_WRITE_SHIFT_REG,
        START_WRITE_OP,
        WRITING,

        PREPARE_RESPONSE,

        WREN_RESPONSE_CMD_FIFO
    );

    type t_sdram_fsm_state is (
        IDLE,
        NOP,

        ACTIVATE,
        WAIT_tRCD,

        SET_READ,
        WAIT_CL,
        READING,

        SET_WRITE,
        WRITING,
        WAIT_tWR,

        WAIT_tRAS,
        FINISH_OP
    );

    -- состояния
    signal sdram_fsm_state : t_sdram_fsm_state;
    signal fifo_fsm_state  : t_fifo_fsm_state;

------------------------------------------------------
            -- SDRAM_FSM
------------------------------------------------------

    -- Максимальные задержки
    constant TRCD_MAX   : integer := tRCD_Cycles;
    constant CL_MAX     : integer := CAS_Latency;
    constant BURST_MAX  : integer := BurstLength;
    constant TWR_MAX    : integer := tWR_Cycles;
    constant TRAS_MAX   : integer := tRAS_Cycles;
    
    -- Ширина счетчиков
    constant TRCD_WIDTH  : integer := integer(floor(log2(real(TRCD_MAX)))) + 1;
    constant CL_WIDTH    : integer := integer(floor(log2(real(CL_MAX)))) + 1;
    constant BURST_WIDTH : integer := integer(floor(log2(real(BURST_MAX)))) + 1;
    constant TWR_WIDTH   : integer := integer(floor(log2(real(TWR_MAX)))) + 1;
    constant TRAS_WIDTH  : integer := integer(floor(log2(real(TRAS_MAX)))) + 1;

    -- Счетчики
    signal trcd_counter  : std_logic_vector(TRCD_WIDTH-1  downto 0);
    signal cl_counter    : std_logic_vector(CL_WIDTH-1   downto 0);
    signal burst_counter : std_logic_vector(BURST_WIDTH-1 downto 0);
    signal twr_counter   : std_logic_vector(TWR_WIDTH-1 downto 0);
    signal tras_counter  : std_logic_vector(TRAS_WIDTH-1 downto 0);

------------------------------------------------------
            -- FIFO_FSM
------------------------------------------------------

    signal request_data_rden_r : std_logic;
    
    -- формируемый ответ-команда
    signal response_command_r : std_logic_vector(19 downto 0);


    -- формируемые выходные данные
    signal response_data_r    : std_logic_vector(63 downto 0);
    signal response_data_wren_r : std_logic;

------------------------------------------------------
            -- COMMON
------------------------------------------------------

    alias op_type    : std_logic                     is request_command_fifo_data(61);
    alias bank_addr  : std_logic_vector(1 downto 0)  is request_command_fifo_data(57 downto 56);
    alias row_addr   : std_logic_vector(11 downto 0) is request_command_fifo_data(55 downto 44);
    alias col_addr   : std_logic_vector(7 downto 0)  is request_command_fifo_data(43 downto 36);
    alias fifo_words : std_logic_vector(11 downto 0) is request_command_fifo_data(35 downto 24);
    alias be_first   : std_logic_vector(7 downto 0)  is request_command_fifo_data(23 downto 16);
    alias be_last    : std_logic_vector(7 downto 0)  is request_command_fifo_data(15 downto 8);
    alias op_id      : std_logic_vector(7 downto 0)  is request_command_fifo_data(7 downto 0);
   
    -- Команда
    signal op_type_r    : std_logic;
    signal bank_addr_r  : std_logic_vector(1 downto 0);
    signal row_addr_r   : std_logic_vector(11 downto 0);
    signal col_addr_r   : std_logic_vector(11 downto 0); -- на самом деле от 7 до 0
    signal fifo_words_r : std_logic_vector(11 downto 0);
    signal be_first_r   : std_logic_vector(7 downto 0);
    signal be_last_r    : std_logic_vector(7 downto 0);
    signal op_id_r      : std_logic_vector(7 downto 0);

    -- Удобные константы
    constant OP_READ   : std_logic := '0';
    constant OP_WRITE  : std_logic := '1';

    signal op_active_r  : std_logic;
    
    constant BURST_BITS     : integer := DataWidth * BurstLength;
    constant WORDS64_PER_TX : integer := (BURST_BITS + 63) / 64;


--    constant LOADS_WIDTH    : integer := integer(floor(log2(real(LOADS)))) + 1;

--    type t_load64_array is array (0 to LOADS-1) of std_logic_vector(63 downto 0);
--    signal load_data_r : t_load64_array;

--    signal loads_counter : std_logic_vector(LOADS_WIDTH-1 downto 0);
--    signal loads_done    : std_logic;

    
--    signal fifo_words_counter : std_logic_vector(11 downto 0);

    -------------------------------------------------------------------

--    constant WORDS_PER_LOAD : integer := 64 / WORD_WIDTH;
--    constant LOADS          : integer := ceil(BURST_BITS / 64);
--    constant LOADS_WIDTH    :
    
    
--    signal loads_counter : std_logic_vector(LOADS_WIDTH-1 downto 0);
--    signal mem_words_counter  : std_logic_vector(BurstLength-1 downto 0);
--    signal frag_counter  : std_logic_vector(2 downto 0);
    --------------------------------------------------------------------

begin
    --  Проверка generic
    assert (DataWidth = 8 or DataWidth = 16 or DataWidth = 32 or DataWidth = 64)
        report "Data width must be equal 8, 16, 32 or 64" severity error;

    assert (BurstLength = 1 or BurstLength = 2 or BurstLength = 4 or BurstLength = 8 or BurstLength = 16)
        report "Burst length must be equal 1, 2, 4, 8 or 16 (full page)" severity error;

    assert (CAS_Latency = 2 or CAS_Latency = 3)
        report "CAS_Latency must be equal 2 or 3" severity error;
   
------------------------------------------------------
            -- TO SUBSYS
------------------------------------------------------

    state_fsm <= Waiting    when (sdram_fsm_state = IDLE or
                                  sdram_fsm_state = NOP) else

                 Activation when (sdram_fsm_state = ACTIVATE or
                                  sdram_fsm_state = WAIT_tRCD) else

                 Reading    when (sdram_fsm_state = SET_READ or
                                  sdram_fsm_state = WAIT_CL or
                                  sdram_fsm_state = READING or
                                  (sdram_fsm_state = WAIT_tRAS and op_type_r = OP_READ)) else

                  Writing   when (sdram_fsm_state = SET_WRITE or
                                  sdram_fsm_state = WRITING or
                                  sdram_fsm_state = WAIT_tWR or
                                  (sdram_fsm_state = WAIT_tRAS and op_type_r = OP_WRITE));

------------------------------------------------------
            -- TO FIFO
------------------------------------------------------

    request_command_fifo_rden  <= '1' when fifo_fsm_state = RDEN_REQUEST_CMD_FIFO else '0';
    
    request_data_fifo_rden     <= '0'; -- Пока что
    
    response_command_fifo_wren <= '1' when (fifo_fsm_state = WREN_RESPONSE_CMD_FIFO and 
                                            response_command_fifo_full='0') else '0';
    -- response_command_fifo_wren <= '1' when fifo_fsm_state = WREN_RESPONSE_CMD_FIFO else '0';
    response_command_fifo_data <= response_command_r;
   
    response_data_fifo_wren    <= '0'; -- Пока что
    response_data_fifo_data    <= response_data_r; 

------------------------------------------------------
            -- TO ARBITER
------------------------------------------------------

    nCS  <= '1' when sdram_fsm_state = IDLE         else '0';
    
    nRAS <= '0' when sdram_fsm_state = ACTIVATE     else '1';

    nCAS <= '0' when sdram_fsm_state = SET_READ or 
                     sdram_fsm_state = SET_WRITE    else '1';

    nWE  <= '0' when sdram_fsm_state = SET_WRITE    else '1';
    
    CKE  <= '0' when sdram_fsm_state = IDLE else '1';
    
    DQ   <= (others => '0') when sdram_fsm_state = IDLE else (others => 'Z');
    
    DQM  <= "00";
    
    BS   <= bank_addr_r;
    
    A    <= row_addr_r when sdram_fsm_state = ACTIVATE else col_addr_r;


    sdram_fsm_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            sdram_fsm_state <= IDLE;
        
        elsif rising_edge(clk) then
            
            case sdram_fsm_state is
                ------------------
                -- IDLE
                ------------------
                when IDLE =>
                    if state_subsys = ValidOp then
                        sdram_fsm_state <= NOP;
                    end if;

                ------------------
                -- NOP
                ------------------
                when NOP =>
                    if state_subsys = ValidOp and op_active_r = '1' then
                        sdram_fsm_state <= ACTIVATE;
                    end if;
                
                ------------------
                -- ACTIVATE
                ------------------
                when ACTIVATE =>
                    sdram_fsm_state <= WAIT_tRCD;

                ------------------
                -- WAIT_tRCD
                ------------------
                when WAIT_tRCD =>
                    if trcd_counter = conv_std_logic_vector(0, trcd_counter'length) then
                        if op_type_r = OP_READ then
                            sdram_fsm_state <= SET_READ;
                        else
                            sdram_fsm_state <= SET_WRITE;
                        end if;
                    end if;

                ------------------
                -- SET_READ
                ------------------
                when SET_READ =>
                    sdram_fsm_state <= WAIT_CL;

                ------------------
                -- WAIT_CL
                ------------------
                when WAIT_CL =>
                    if cl_counter = conv_std_logic_vector(0, cl_counter'length) then
                        sdram_fsm_state <= READING;
                    end if;

                ------------------
                -- READ
                ------------------
                when READING =>
                    if burst_counter = conv_std_logic_vector(0, burst_counter'length) then
                        sdram_fsm_state <= WAIT_tRAS;
                    end if;

                ------------------
                -- SET_WRITE
                ------------------
                when SET_WRITE =>
                    sdram_fsm_state <= WRITING;

                ------------------
                -- WRITE
                ------------------
                when WRITING =>
                    -- burst_counter
                    if burst_counter = conv_std_logic_vector(0, burst_counter'length) then
                        sdram_fsm_state <= WAIT_tWR;
                    end if;
                
                ------------------
                -- WAIT_tWR
                ------------------
                when WAIT_tWR =>
                    if twr_counter = conv_std_logic_vector(0, twr_counter'length) then
                        sdram_fsm_state <= WAIT_tRAS;
                    end if;

                ------------------
                -- WAIT_tRAS
                ------------------
                when WAIT_tRAS =>
                    if tras_counter = conv_std_logic_vector(0, tras_counter'length) then
                        sdram_fsm_state <= FINISH_OP;
                    end if;
                ------------------
                -- FINISH_OP
                ------------------    
                when FINISH_OP =>
                    sdram_fsm_state <= NOP;

            end case;
        end if;
    end process sdram_fsm_proc;


    sdram_logic_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            -- счётчики
            trcd_counter  <= (others => '0');
            cl_counter    <= (others => '0');
            burst_counter <= (others => '0');
            twr_counter   <= (others => '0');
            tras_counter  <= (others => '0');

        elsif rising_edge(Clk) then
------------------------------------------------------
            -- COUNTERS
------------------------------------------------------

            ------------------
            -- trcd_counter
            -- Временная задержка после ACTIVATE, банк
            -- и строка открываются через tRCD.
            ------------------
            if sdram_fsm_state = WAIT_tRCD then
                if trcd_counter /= conv_std_logic_vector(0, trcd_counter'length) then
                    trcd_counter <= trcd_counter - '1';
                end if;
            else -- if sdram_fsm_state = ACTIVATE then
                trcd_counter <= conv_std_logic_vector(TRCD_MAX-1, trcd_counter'length);
            end if;

            ------------------
            -- cl_counter
            -- Временная задержка после SET_READ, данные после 
            -- подачи команды появляются через CL тактов.
            ------------------
            if sdram_fsm_state = WAIT_CL then
                if cl_counter /= conv_std_logic_vector(0, cl_counter'length) then
                    cl_counter <= cl_counter - '1';
                end if;
            else -- if sdram_fsm_state = SET_READ then
                cl_counter <= conv_std_logic_vector(CL_MAX-1, cl_counter'length);
            end if;

            ------------------
            -- burst_counter
            ------------------
            if sdram_fsm_state = READING or sdram_fsm_state = WRITING then
                if burst_counter /= conv_std_logic_vector(0, burst_counter'length) then
                    burst_counter <= burst_counter - '1';
                end if;
            else -- if sdram_fsm_state = SET_WRITE or sdram_fsm_state = WAIT_CL then
                burst_counter <= conv_std_logic_vector(BURST_MAX-1, burst_counter'length);
            end if;

            ------------------
            -- twr_counter
            -- Временная задержка после WRITE, данные 
            -- записываются в память через tWR.
            ------------------
            if sdram_fsm_state = WAIT_tWR then
                if twr_counter /= conv_std_logic_vector(0, twr_counter'length) then
                    twr_counter <= twr_counter - '1';
                end if;
            else -- if sdram_fsm_state = WRITE then
                twr_counter <= conv_std_logic_vector(TWR_MAX-1, twr_counter'length);
            end if;

            ------------------
            -- tras_counter !!! Особенный, начинается в ACTIVATE и идет во всех состояниях
            -- Минимальное время которое надо выждать 
            -- от подачи ACTIVATE до подачи PRECHARGE.
            ------------------
            if tras_counter /= conv_std_logic_vector(0, tras_counter'length) then
                tras_counter <= tras_counter - '1';
            elsif sdram_fsm_state = ACTIVATE then
                tras_counter <= conv_std_logic_vector(TRAS_MAX-1, tras_counter'length);
            end if;
        end if; 
    end process sdram_logic_proc;


    fifo_fsm_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            fifo_fsm_state <= IDLE;
        
        elsif rising_edge(clk) then
            
            case fifo_fsm_state is
                ------------------
                -- IDLE
                ------------------
                when IDLE =>
                    if request_command_fifo_empty = '0' then
                        fifo_fsm_state <= RDEN_REQUEST_CMD_FIFO;
                    end if;

                ------------------
                -- RDEN_REQUEST_CMD_FIFO
                ------------------
                when RDEN_REQUEST_CMD_FIFO =>
                    fifo_fsm_state <= PREPARE_REQUEST;

                ------------------
                -- PREPARE_REQUEST TODO
                ------------------
                when PREPARE_REQUEST =>
                    if op_type = OP_READ then
                        fifo_fsm_state <= START_READ_OP;
                    else
                        fifo_fsm_state <= LOAD_WRITE_SHIFT_REG;
                    end if;

                ------------------
                -- START_READ_OP
                ------------------
                when START_READ_OP =>
                    fifo_fsm_state <= READING;

                ------------------
                -- READING
                ------------------
                when READING =>
                    if op_active_r = '0' then
                        fifo_fsm_state <= UNLOAD_READ_SHIFT_REG;
                    end if;

                ------------------
                -- UNLOAD_READ_SHIFT_REG TODO
                ------------------
                when UNLOAD_READ_SHIFT_REG =>
                    fifo_fsm_state <= PREPARE_RESPONSE;
               
                ------------------
                -- LOAD_WRITE_SHIFT_REG TODO
                ------------------
                when LOAD_WRITE_SHIFT_REG =>
                    fifo_fsm_state <= START_WRITE_OP;

                ------------------
                -- START_WRITE_OP
                ------------------
                when START_WRITE_OP =>
                    fifo_fsm_state <= WRITING;

                ------------------
                -- WRITING
                ------------------
                when WRITING =>
                    if op_active_r = '0' then
                        fifo_fsm_state <= PREPARE_RESPONSE;
                    end if;

                ------------------
                -- PREPARE_RESPONSE
                ------------------
                when PREPARE_RESPONSE =>
                    fifo_fsm_state <= WREN_RESPONSE_CMD_FIFO;

                ------------------
                -- WREN_RESPONSE_CMD_FIFO
                ------------------
                when WREN_RESPONSE_CMD_FIFO =>
                    if response_command_fifo_full = '0' then
                        fifo_fsm_state <= IDLE;
                    end if;
            end case;
        end if;
    end process fifo_fsm_proc;


    fifo_logic_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            -- регистры
            request_data_rden_r     <= '0';

            response_command_r      <= (others => '0');

            response_data_r         <= (others => '0');
            response_data_wren_r    <= '0';
    
            op_type_r    <= '0';
            bank_addr_r  <= (others => '0');
            row_addr_r   <= (others => '0');
            col_addr_r   <= (others => '0');
            fifo_words_r <= (others => '0');
            be_first_r   <= (others => '0');
            be_last_r    <= (others => '0');
            op_id_r      <= (others => '0');

        elsif rising_edge(clk) then

------------------------------------------------------
            -- FROM AVALON
------------------------------------------------------

            -- TODO

            -- request_data_rden_r 

------------------------------------------------------
            -- TO AVALON (CMD)
------------------------------------------------------

            if fifo_fsm_state = PREPARE_RESPONSE then
                response_command_r(19 downto 8) <= fifo_words_r;
                response_command_r(7 downto 0)  <= op_id_r;
            end if;

------------------------------------------------------
            -- TO AVALON (DATA)
------------------------------------------------------

            -- TODO

            -- response_data_wren_r
            -- response_data_r

------------------------------------------------------
            -- PREPARE_REQUEST 
------------------------------------------------------
            
            if fifo_fsm_state = PREPARE_REQUEST then
                op_type_r    <= op_type;
                bank_addr_r  <= bank_addr;
                row_addr_r   <= row_addr;

                col_addr_r <= (others => '0');
                col_addr_r(7 downto 0) <= col_addr;

                fifo_words_r <= fifo_words;
                be_first_r   <= be_first;
                be_last_r    <= be_last;
                op_id_r      <= op_id;
            end if;

        end if;
    end process fifo_logic_proc;

    notify_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            op_active_r <= '0';

        elsif rising_edge(clk) then

            if fifo_fsm_state = START_READ_OP or fifo_fsm_state = START_WRITE_OP then 
                op_active_r <= '1';
            elsif sdram_fsm_state = FINISH_OP then 
                op_active_r <= '0';
            end if;
        end if;
    end process notify_proc;
            
end rtl;
