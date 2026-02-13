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
        AddressWidth   : integer := 25;
        UsedWidth      : integer := 10
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
        request_command_fifo_read_en   : out std_logic;
        request_command_fifo_data      : in  std_logic_vector(61 downto 0);
        request_command_fifo_empty     : in  std_logic;

        request_data_fifo_read_en      : out std_logic;
        request_data_fifo_data         : in  std_logic_vector(63 downto 0);
        request_data_fifo_empty        : in  std_logic;

        -- Запись
        response_command_fifo_write_en : out std_logic;
        response_command_fifo_data     : out std_logic_vector(19 downto 0);
        response_command_fifo_full     : in  std_logic;

        response_data_fifo_write_en    : out std_logic;
        response_data_fifo_data        : out std_logic_vector(63 downto 0);
        response_data_fifo_full        : in std_logic;
        response_data_fifo_used        : in std_logic_vector(UsedWidth-1 downto 0);

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

        WAIT_tRAS
    );

    type t_fifo_fsm_state is (
        IDLE,

        READ_REQUEST_CMD_FIFO,

        PREPARE_CMD_FOR_OP,

        LOAD_WRITE_SHIFT_REG,
        WRITING,

        READING,
        UNLOAD_READ_SHIFT_REG,

        WRITE_RESPONSE_CMD_FIFO
    );

    -- состояния
    signal sdram_fsm_state : t_sdram_fsm_state;
    signal fifo_fsm_state  : t_fifo_fsm_state;
    signal external_state  : StateFSM_type;

------------------------------------------------------
            -- SDRAM_FSM
------------------------------------------------------

    -- максимальные задержки
    constant TRCD_MAX   : integer := tRCD_Cycles;
    constant CL_MAX     : integer := CAS_Latency;
    constant BURST_MAX  : integer := BurstLength;
    constant TWR_MAX    : integer := tWR_Cycles;
    constant TRAS_MAX   : integer := tRAS_Cycles;
    
    -- ширина счетчиков
    constant TRCD_WIDTH  : integer := integer(floor(log2(real(TRCD_MAX)))) + 1;
    constant CL_WIDTH    : integer := integer(floor(log2(real(CL_MAX)))) + 1;
    constant BURST_WIDTH : integer := integer(floor(log2(real(BURST_MAX)))) + 1;
    constant TWR_WIDTH   : integer := integer(floor(log2(real(TWR_MAX)))) + 1;
    constant TRAS_WIDTH  : integer := integer(floor(log2(real(TRAS_MAX)))) + 1;

    -- счетчики
    signal trcd_counter  : std_logic_vector(TRCD_WIDTH-1  downto 0);
    signal cl_counter    : std_logic_vector(CL_WIDTH-1   downto 0);
    signal burst_counter : std_logic_vector(BURST_WIDTH-1 downto 0);
    signal twr_counter   : std_logic_vector(TWR_WIDTH-1 downto 0);
    signal tras_counter  : std_logic_vector(TRAS_WIDTH-1 downto 0);
    
    signal nCS_r  : std_logic;
    signal nRAS_r : std_logic;
    signal nCAS_r : std_logic;
    signal nWE_r  : std_logic;
    signal CKE_r  : std_logic;
    signal DQ_r   : std_logic_vector(15 downto 0);
    signal DQM_r  : std_logic_vector(1 downto 0);
    signal BS_r   : std_logic_vector(1 downto 0);
    signal A_r    : std_logic_vector(11 downto 0);

    -- TODO Переделать под _r чтобы было удобно менять
    alias operation_type : std_logic                     is request_command_r(61);
    alias bank_addr      : std_logic_vector(1 downto 0)  is request_command_r(57 downto 56);
    alias row_addr       : std_logic_vector(11 downto 0) is request_command_r(55 downto 44);
    alias col_addr       : std_logic_vector(7 downto 0)  is request_command_r(43 downto 36);
    alias fifo_words     : std_logic_vector(11 downto 0) is request_command_r(35 downto 24);
    alias be_first       : std_logic_vector(7 downto 0)  is request_command_r(23 downto 16);
    alias be_last        : std_logic_vector(7 downto 0)  is request_command_r(15 downto 8);
    alias operation_id   : std_logic_vector(7 downto 0)  is request_command_r(7 downto 0);

------------------------------------------------------
            -- FIFO_FSM
------------------------------------------------------

    -- захваченная входная команда
    signal request_command_read_en_r   : std_logic;

    -- захваченные входные данные
    signal request_data_read_en_r      : std_logic;
    signal request_data_r              : std_logic_vector(63 downto 0);

    -- формируемый ответ-команда
    signal response_command_write_en_r : std_logic;
    signal response_command_r          : std_logic_vector(19 downto 0);

    -- формируемые выходные данные
    signal response_data_write_en_r    : std_logic;
    signal response_data_r             : std_logic_vector(63 downto 0);
    signal response_data_used_r        : std_logic_vector(UsedWidth-1 downto 0);

--    constant WORDS_PER_LOAD : integer := 64 / DataWidth;
--    constant BURST_BITS     : integer := DataWidth * BurstLength;
--    constant LOADS          : integer := (BURST_BITS + 63) / 64;
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
   

    state_fsm <= external_state;
    
    request_command_fifo_read_en   <= request_command_read_en_r;
    
    request_data_fifo_read_en      <= request_data_read_en_r;
    
    response_command_fifo_write_en <= response_command_write_en_r;
    response_command_fifo_data     <= response_command_r;
   
    response_data_fifo_write_en    <= response_data_write_en_r;
    response_data_fifo_data        <= response_data_r; 

    nCS  <= nCS_r;
    nRAS <= nRAS_r;
    nCAS <= nCAS_r;
    nWE  <= nWE_r;
    CKE  <= CKE_r;
    DQ   <= DQ_r;
    DQM  <= DQM_r;
    BS   <= BS_r;
    A    <= A_r;


    sdram_fsm_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            sdram_fsm_state <= IDLE;
        
        elsif rising_edge(clk) then
            
            case sdram_fsm_state is
                ------------------
                -- IDLE
                ------------------
                when Idle =>
                    if state_subsys = ValidOp then
                        sdram_fsm_state <= Waiting;
                    end if;

                ------------------
                -- NOP
                ------------------
                when NOP =>
                    if state_subsys = ValidOp and (op_start = '1') then
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
                        if operation_type = '0' then
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
                    -- burst_counter
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
                        sdram_fsm_state <= NOP;
                    end if;

            end case;
        end if;
    end process sdram_fsm_proc;


    sdram_logic_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            external_state <= Idle;

            -- счётчики
            trcd_counter  <= (others => '0');
            cl_counter    <= (others => '0');
            burst_counter <= (others => '0');
            twr_counter   <= (others => '0');
            tras_counter  <= (others => '0');

            nCS_r  <= '1';
            nRAS_r <= '1';
            nCAS_r <= '1';
            nWE_r  <= '1';
            CKE_r  <= '0';            
            DQ_r   <= (others => '0');
            DQM_r  <= "00";
            BS_r   <= (others => '0');
            A_r    <= (others => '0');

        elsif rising_edge(Clk) then
            -- пока что так
            CKE_r <= '1';
            DQ_r  <= (others => 'Z');
            DQM_r <= "00";

            -- Переделать комбинационно
            if sdram_fsm_state = IDLE then

                external_state <= Idle;
					 
			elsif sdram_fsm_state = NOP then
				
				external_state <= Waiting;

            elsif sdram_fsm_state = ACTIVATE                             or
                  sdram_fsm_state = WAIT_tRCD                            then

                external_state <= Activation;
            
            elsif sdram_fsm_state = SET_READ                             or
                  sdram_fsm_state = WAIT_CL                              or
                  sdram_fsm_state = READING                              or
                  (sdram_fsm_state = WAIT_tRAS and operation_type = '0') then

                external_state <= Reading;

            elsif sdram_fsm_state = SET_WRITE                            or
                  sdram_fsm_state = WRITING                              or
                  sdram_fsm_state = WAIT_tWR                             or
                  (sdram_fsm_state = WAIT_tRAS and operation_type = '1') then

                external_state <= Writing;
            
            end if;

------------------------------------------------------
            -- COUNTERS
------------------------------------------------------

            ------------------
            -- trcd_counter
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
            ------------------
            if sdram_fsm_state = WAIT_tWR then
                if twr_counter /= conv_std_logic_vector(0, twr_counter'length) then
                    twr_counter <= twr_counter - '1';
                end if;
            else -- if sdram_fsm_state = WRITE then
                twr_counter <= conv_std_logic_vector(TWR_MAX-1, twr_counter'length);
            end if;

            ------------------
            -- tras_counter !!! Особенный
            ------------------
            if tras_counter /= conv_std_logic_vector(0, tras_counter'length) then
                tras_counter <= tras_counter - '1';
            elsif sdram_fsm_state = ACTIVATE then
                tras_counter <= conv_std_logic_vector(TRAS_MAX-1, tras_counter'length);
            end if;

------------------------------------------------------
            -- TO ARBITER
------------------------------------------------------

            -- TODO Переделать без регистров, сразу комбинационно
            ------------------
            -- nCS_r
            ------------------
            if sdram_fsm_state = IDLE then
                nCS_r <= '1';
            else
                nCS_r <= '0';
            end if;

            ------------------
            -- nRAS_r
            ------------------
            if sdram_fsm_state = ACTIVATE then
                nRAS_r <= '0';
            else
                nRAS_r <= '1';
            end if;

            ------------------
            -- nCAS_r
            ------------------
            if sdram_fsm_state = SET_READ  or
               sdram_fsm_state = SET_WRITE then
                nCAS_r <= '0';
            else
                nCAS_r <= '1';
            end if;

            ------------------
            -- nWE_r
            ------------------
            if sdram_fsm_state = SET_WRITE then
                nWE_r <= '0';
            else
                nWE_r <= '1';
            end if;

            ------------------
            -- CKE_r
            ------------------
            -- TODO

            ------------------
            -- DQ_r
            ------------------
            -- TODO

            ------------------
            -- DQM_r
            ------------------
            -- TODO

            ------------------
            -- BS_r
            ------------------
            if sdram_fsm_state = ACTIVATE  or
               sdram_fsm_state = SET_READ  or
               sdram_fsm_state = SET_WRITE then
                BS_r <= bank_addr;
            end if;

            ------------------
            -- A_r
            ------------------
            if sdram_fsm_state = ACTIVATE then
                A_r <= row_addr;
            elsif sdram_fsm_state = SET_READ or
                  sdram_fsm_state = SET_WRITE then
                A_r(11 downto 0) <= (others => '0');
                A_r(7 downto 0)  <= col_addr;
            end if;
        end if;
    end process sdram_logic_proc;



    fifo_fsm_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            fifo_fsm_state <= IDLE;
        
        elsif rising_edge(clk) then
            
            case sdram_fsm_state is
                ------------------
                -- IDLE
                ------------------
                when IDLE =>
                    if request_command_fifo_empty = '0' then
                        fifo_fsm_state <= READ_REQUEST_CMD_FIFO;
                    end if;

                ------------------
                -- READ_REQUEST_CMD_FIFO
                ------------------
                when READ_REQUEST_CMD_FIFO =>
                    fifo_fsm_state <= PREPARE_CMD_FOR_OP;

                ------------------
                -- PREPARE_CMD_FOR_OP
                ------------------
                when PREPARE_CMD_FOR_OP =>
                    -- TODO Сделать константу для op_type
                    if operation_type = '0' then
                        fifo_fsm_state <= READING;
                    else
                        fifo_fsm_state <= LOAD_WRITE_SHIFT_REG;
                    end if;

                ------------------
                -- READING
                ------------------
                when READING =>
                    if op_end = '1' then
                        sdram_fsm_state <= UNLOAD_READ_SHIFT_REG;
                    end if;

                ------------------
                -- UNLOAD_READ_SHIFT_REG
                ------------------
                when UNLOAD_READ_SHIFT_REG =>
                    fifo_fsm_state <= WRITE_RESPONSE_CMD_FIFO;
               
                ------------------
                -- LOAD_WRITE_SHIFT_REG
                ------------------
                when LOAD_WRITE_SHIFT_REG =>
                    fifo_fsm_state <= WRITING;

                ------------------
                -- WRITING
                ------------------
                when WRITING =>
                    if op_end = '1' then
                        fifo_fsm_state <= WRITE_RESPONSE_CMD_FIFO;
                    end if;

                ------------------
                -- WRITE_RESPONSE_CMD_FIFO
                ------------------
                when WRITE_RESPONSE_CMD_FIFO =>
                    if response_command_fifo_full = '0' then
                        sdram_fsm_state <= IDLE;
                    else
                        sdram_fsm_state <= WRITE_RESPONSE_CMD_FIFO;
                    end if;

            end case;
        end if;
    end process cmd_fsm_proc;


    fifo_logic_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            -- регистры
            request_command_r      <= (others => '0');
            request_command_read_en_r   <= '0';

            request_data_r              <= (others => '0');
            request_data_read_en_r      <= '0';

            response_command_r     <= (others => '0');
            response_command_write_en_r <= '0';

            response_data_r             <= (others => '0');
            response_data_used_r        <= (others => '0');
            response_data_write_en_r    <= '0';

        elsif rising_edge(clk) then
        
        end if;
    end process fifo_logic_proc;
            
end rtl;






















------------------------------------------------------
            -- FROM AVALON (CMD)
------------------------------------------------------

            ------------------
            -- request_command_read_en_r
            ------------------
            if sdram_fsm_state = ENABLE_REQUEST_CMD_FIFO then
                request_command_read_en_r <= '1';
            else
                request_command_read_en_r <= '0';
            end if;
            
            ------------------
            -- request_command_r
            ------------------
            if sdram_fsm_state = READ_REQUEST_CMD_FIFO then
               request_command_r <= request_command_fifo_data; 
            end if;

------------------------------------------------------
            -- FROM AVALON (DATA)
------------------------------------------------------

            ------------------
            -- request_data_read_en_r
            ------------------
            if sdram_fsm_state = ENABLE_REQUEST_DATA_FIFO then
                request_data_read_en_r <= '1';
            else
                request_data_read_en_r <= '0';
            end if;

            ------------------
            -- request_data_r
            ------------------
            -- ВОТ ТУТ НАДО КАК ТО ПЕРЕДЕЛАТЬ ЧТОБЫ СЧИТЫВАТЬ ДАННЫЕ В МАССИВ data_r 
            if sdram_fsm_state = READ_REQUEST_DATA_FIFO then
                request_data_r <= request_data_fifo_data; 
            end if;

            
            
------------------------------------------------------
            -- TO AVALON (CMD)
------------------------------------------------------

            ------------------
            -- response_command_write_en_r
            ------------------
            if sdram_fsm_state = WRITE_RESPONSE_CMD_FIFO and response_command_fifo_full = '0' then
                response_command_write_en_r <= '1';
            else
                response_command_write_en_r <= '0';
            end if;

            ------------------
            -- response_command_r
            ------------------
            if sdram_fsm_state = WRITE_RESPONSE_CMD_FIFO and response_command_fifo_full = '0' then
                response_command_r(19 downto 8) <= data_len;
                response_command_r(7 downto 0)  <= operation_id;
            end if;

------------------------------------------------------
            -- TODO TO AVALON (DATA)
------------------------------------------------------

--          ------------------     
--          -- response_data_write_en_r
--          ------------------
--          if sdram_fsm_state = WRITE_RESPONSE_DATA_FIFO then
--              request_data_write_en_r <= '1';
--          else
--              request_data_write_en_r <= '0';
--          end if;
--            
--          ------------------
--          -- response_data_r
--          ------------------
--          if sdram_fsm_state = WRITE_RESPONSE_DATA_FIFO then
--             request_data_r <= ??? 
--          end if;

            
end rtl;
