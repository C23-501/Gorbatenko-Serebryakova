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
        BurstLength    : integer := 4;
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
        nCS  : out   std_logic;
        nRAS : out   std_logic;
        nCAS : out   std_logic;
        nWE  : out   std_logic;
        CKE  : out   std_logic;
        DQ   : inout std_logic_vector(15 downto 0);
        DQM  : out   std_logic_vector(1 downto 0);
        BS   : out   std_logic_vector(1 downto 0);
        A    : out   std_logic_vector(11 downto 0)
    );
end SdramFsm;

architecture rtl of SdramFsm is
  
    type t_fifo_fsm_state is (
        IDLE,

        RDEN_REQUEST_CMD_FIFO,
        PREPARE_REQUEST,
        
        START_READ_OP,
        READING,
        UNLOAD_READ_SHIFT_REG,
       
        RDEN_REQUEST_DATA_FIFO,
        LOAD_WRITE_SHIFT_REG,
        START_WRITE_OP,
        WRITING,
        
        DECREMENT_WORDS64_COUNTER,
        CHECK_REQUEST_DONE,
        PREPARE_RESPONSE,
        WREN_RESPONSE_DATA_FIFO,
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

    signal request_command_rden_r : std_logic;

    signal request_data_rden_r : std_logic;
    
    signal response_command_wren_r : std_logic;
    signal response_command_r : std_logic_vector(19 downto 0);


    signal response_data_wren_r : std_logic;
    signal response_data_r    : std_logic_vector(63 downto 0);

------------------------------------------------------
            -- COMMON
------------------------------------------------------
    -- Удобные константы
    constant OP_READ   : std_logic := '0';
    constant OP_WRITE  : std_logic := '1';

    alias op_type   : std_logic                     is request_command_fifo_data(61);
    alias bank_addr : std_logic_vector(1 downto 0)  is request_command_fifo_data(57 downto 56);
    alias row_addr  : std_logic_vector(11 downto 0) is request_command_fifo_data(55 downto 44);
    alias col_addr  : std_logic_vector(7 downto 0)  is request_command_fifo_data(43 downto 36);
    alias words64   : std_logic_vector(11 downto 0) is request_command_fifo_data(35 downto 24);
    alias be_first  : std_logic_vector(7 downto 0)  is request_command_fifo_data(23 downto 16);
    alias be_last   : std_logic_vector(7 downto 0)  is request_command_fifo_data(15 downto 8);
    alias op_id     : std_logic_vector(7 downto 0)  is request_command_fifo_data(7 downto 0);
   
    -- Команда
    signal op_type_r    : std_logic;
    signal bank_addr_r  : std_logic_vector(1 downto 0);
    signal row_addr_r   : std_logic_vector(11 downto 0);
    signal col_addr_r   : std_logic_vector(7 downto 0); -- на самом деле от 7 до 0
    signal words64_r    : std_logic_vector(11 downto 0);
    signal be_first_r   : std_logic_vector(7 downto 0);
    signal be_last_r    : std_logic_vector(7 downto 0);
    signal op_id_r      : std_logic_vector(7 downto 0);

    -- constant BURST_BITS : integer := DataWidth * BurstLength;

    signal write_sreg_load  : std_logic;
    signal write_sreg_shift : std_logic;

    signal write_sreg_idxPart : std_logic_vector(2 downto 0);
    signal write_sreg_idxWord : std_logic_vector(3 downto 0);
    
    signal read_sreg_load  : std_logic;
    signal read_sreg_shift : std_logic;
    
    signal request_done_r : std_logic;
    signal first_prepare_done_r : std_logic;

    signal words64_counter : std_logic_vector(11 downto 0);

    signal dq_in  : std_logic_vector(DataWidth-1 downto 0);
    signal dq_out : std_logic_vector(DataWidth-1 downto 0);
    signal dq_out_r : std_logic_vector(DataWidth-1 downto 0);

    signal resp_data_reg : std_logic_vector(63 downto 0);

------------------------------------------------------
            -- NOTIFY
------------------------------------------------------
    signal op_active_r  : std_logic;

begin

    assert(DataWidth * BurstLength = 64) report "DataWidth * BurstLength must be equal 64" severity error;

    --  Проверка generic
--    assert (DataWidth = 8 or DataWidth = 16 or DataWidth = 32 or DataWidth = 64)
--        report "Data width must be equal 8, 16, 32 or 64" severity error;

--    assert (BurstLength = 1 or BurstLength = 2 or BurstLength = 4 or BurstLength = 8 or BurstLength = 16)
--        report "Burst length must be equal 1, 2, 4, 8 or 16 (full page)" severity error;

--    assert (CAS_Latency = 2 or CAS_Latency = 3)
--        report "CAS_Latency must be equal 2 or 3" severity error;
   

    u_write_shift_reg : entity work.write_shift_reg
        generic map (
            WORD_WIDTH => DataWidth,
            BURST      => BurstLength
        )
        port map (
            Clk     => clk,
            nRst    => nRst,

            Load    => write_sreg_load,
            Shift   => write_sreg_shift,

            IdxPart => write_sreg_idxPart,
            IdxWord => write_sreg_idxWord,

            DataIn  => request_data_fifo_data,

            WordOut => dq_out
        );

    u_read_shift_reg : entity work.read_shift_reg
        generic map (
            WORD_WIDTH => DataWidth,
            BURST      => BurstLength
        )
        port map (
            Clk     => clk,
            nRst    => nRst,

            Load    => read_sreg_load,
            Shift   => read_sreg_shift,

            DataIn  => dq_in,

            DataOut => resp_data_reg
        );


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

    request_command_fifo_rden  <= request_command_rden_r;
    
    request_data_fifo_rden     <= request_data_rden_r;
    
    response_command_fifo_wren <= response_command_wren_r;
    response_command_fifo_data <= response_command_r;
   
    response_data_fifo_wren    <= response_data_wren_r;
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
    
    DQ <= dq_out_r
          when (sdram_fsm_state = SET_WRITE or
                sdram_fsm_state = WRITING or
                sdram_fsm_state = WAIT_tWR)
          else (others => 'Z');

    dq_in <= DQ;
    
    DQM  <= "00";
    
    BS   <= bank_addr_r;
    
    A    <= row_addr_r when sdram_fsm_state = ACTIVATE else ("0000" & col_addr_r);

    read_sreg_load <= '1' when (sdram_fsm_state = READING) else '0';
    write_sreg_shift <= '1' when (sdram_fsm_state = WRITING) else '0';


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

--            write_sreg_shift <= '0';

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
            else -- if sdram_fsm_state = SET_WRITE or sdram_fsm_state = SET_READ then
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

            ------------------
            -- write_sreg_shift
            ------------------
--            if sdram_fsm_state = SET_WRITE or sdram_fsm_state = WRITING then
--                write_sreg_shift <= '1';
--            else
--                write_sreg_shift <= '0';
--            end if;

            ------------------
            -- read_sreg_shift
            ------------------
--            if sdram_fsm_state = WAIT_CL and READING then
--                read_sreg_load <= '1';
--            else
--                read_sreg_load <= '0';
--            end if;
        end if; 
    end process sdram_logic_proc;

    process(clk, nRst)
    begin
        if nRst = '0' then
            dq_out_r <= (others => '0');

        elsif falling_edge(clk) then
            -- Обновляем данные для записи
            if sdram_fsm_state = SET_WRITE or
               sdram_fsm_state = WRITING then

                dq_out_r <= dq_out;

            end if;
        end if;
    end process;

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
                -- PREPARE_REQUEST
                ------------------
                when PREPARE_REQUEST =>
                    if request_done_r = '1' then
                        fifo_fsm_state <= PREPARE_RESPONSE;
                    else
                        if op_type = OP_READ then
                            fifo_fsm_state <= START_READ_OP;
                        else
                            if request_data_fifo_empty = '0' then
                                fifo_fsm_state <= RDEN_REQUEST_DATA_FIFO;
                            else
                                fifo_fsm_state <= PREPARE_RESPONSE;
                            end if;
                        end if;
                    end if;

------------------------------------------------
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
                -- UNLOAD_READ_SHIFT_REG
                ------------------
                when UNLOAD_READ_SHIFT_REG =>
                    if response_data_fifo_full = '0' then
                        fifo_fsm_state <= WREN_RESPONSE_DATA_FIFO;
                    end if;

                ------------------
                -- WREN_RESPONSE_DATA_FIFO
                ------------------
                when WREN_RESPONSE_DATA_FIFO =>
                    fifo_fsm_state <= DECREMENT_WORDS64_COUNTER;

------------------------------------------------

------------------------------------------------
                ------------------
                -- RDEN_REQUEST_DATA_FIFO
                ------------------
                when RDEN_REQUEST_DATA_FIFO =>
                    fifo_fsm_state <= LOAD_WRITE_SHIFT_REG;

                ------------------
                -- LOAD_WRITE_SHIFT_REG TODO (LOGIC)
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
                        fifo_fsm_state <= DECREMENT_WORDS64_COUNTER;
                    end if;
------------------------------------------------

                ------------------
                -- DECREMENT_WORDS64_COUNTER
                ------------------
                when DECREMENT_WORDS64_COUNTER =>
                    fifo_fsm_state <= CHECK_REQUEST_DONE;

                ------------------
                -- CHECK_REQUEST_DONE
                ------------------
                when CHECK_REQUEST_DONE =>
                    fifo_fsm_state <= PREPARE_REQUEST;

               ------------------
                -- PREPARE_RESPONSE
                ------------------
                when PREPARE_RESPONSE =>
                    if response_command_fifo_full = '0' then
                        fifo_fsm_state <= WREN_RESPONSE_CMD_FIFO;
                    end if;

                ------------------
                -- WREN_RESPONSE_CMD_FIFO
                ------------------
                when WREN_RESPONSE_CMD_FIFO =>
                    fifo_fsm_state <= IDLE;

            end case;
        end if;
    end process fifo_fsm_proc;


    fifo_logic_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            -- регистры
            request_command_rden_r <= '0';
            
            request_data_rden_r <= '0';

            response_command_wren_r <= '0';
            response_command_r   <= (others => '0');

            response_data_r <= (others => '0');

            op_type_r    <= '0';
            bank_addr_r  <= (others => '0');
            row_addr_r   <= (others => '0');
            col_addr_r   <= (others => '0');
            words64_r <= (others => '0');
            be_first_r   <= (others => '0');
            be_last_r    <= (others => '0');
            op_id_r      <= (others => '0');

            write_sreg_load <= '0';
            read_sreg_shift <= '0';

            write_sreg_idxPart <= (others => '0');
            write_sreg_idxWord <= (others => '0');

            request_done_r <= '0';
            first_prepare_done_r <= '0';

            words64_counter <= (others => '0');

        elsif rising_edge(clk) then

            ------------------
            -- request_command_rden_r
            ------------------
            if fifo_fsm_state = IDLE and request_command_fifo_empty = '0' then
                request_command_rden_r <= '1';
            else
                request_command_rden_r <= '0';
            end if;

            ------------------
            -- request_data_rden_r
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST and request_done_r = '0' and 
               op_type = OP_WRITE and request_data_fifo_empty = '0' then
                request_data_rden_r <= '1';
            else
                request_data_rden_r <= '0';
            end if;
    
            ------------------
            -- response_command_wren_r
            ------------------
            if fifo_fsm_state = PREPARE_RESPONSE and response_command_fifo_full = '0' then
                response_command_wren_r <= '1';
            else
                response_command_wren_r <= '0';
            end if;

            ------------------
            -- response_command_r
            ------------------
            if fifo_fsm_state = PREPARE_RESPONSE then
                response_command_r(19 downto 8) <= words64_r;
                response_command_r(7  downto 0) <= op_id_r;
            end if;

            ------------------
            -- response_data_wren_r
            ------------------
            if fifo_fsm_state = UNLOAD_READ_SHIFT_REG and response_data_fifo_full = '0' then
                response_data_wren_r <= '1';
            else
                response_data_wren_r <= '0';
            end if;

            ------------------
            -- response_data_r
            ------------------
            if fifo_fsm_state = UNLOAD_READ_SHIFT_REG then
                response_data_r <= resp_data_reg;
            end if;            

            ------------------
            -- op_type_r
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    op_type_r <= op_type;
                end if;
            end if;

            ------------------
            -- bank_add_r 
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    bank_addr_r <= bank_addr;
                elsif row_addr_r + conv_std_logic_vector(1, row_addr_r'length) < row_addr_r then
                    bank_addr_r <= bank_addr_r + 1;
                end if;
            end if;

            ------------------
            -- row_addr_r 
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    row_addr_r <= row_addr;
                elsif col_addr_r + conv_std_logic_vector(BurstLength, col_addr_r'length) < col_addr_r then
                    row_addr_r <= row_addr_r + 1;
                end if;
            end if;

            ------------------
            -- col_addr_r 
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    col_addr_r <= col_addr;
                else
                    col_addr_r <= col_addr_r + conv_std_logic_vector(BurstLength, col_addr_r'length);
                end if;
            end if;

            ------------------
            -- words64_r
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    words64_r <= words64;
                elsif request_done_r = '0' and op_type = OP_WRITE and
                      request_data_fifo_empty = '1' then
                    words64_r <= conv_std_logic_vector(0, words64_r'length);
                end if;
            end if;

            ------------------
            -- be_first_r
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    be_first_r <= be_first;
                end if;
            end if;
            
            ------------------
            -- be_last_r
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    be_last_r <= be_last;
                end if;
            end if;

            ------------------
            -- op_id_r
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    op_id_r <= op_id;
                end if;
            end if;
            
            ------------------
            -- write_sreg_load
            ------------------
            if fifo_fsm_state = RDEN_REQUEST_DATA_FIFO then
                write_sreg_load <= '1';
            else
                write_sreg_load <= '0';
            end if;

            ------------------
            -- read_sreg_shift
            ------------------
            if fifo_fsm_state = READING and op_active_r = '0' then
                read_sreg_shift <= '1';
            else
                read_sreg_shift <= '0';
            end if;

            ------------------
            -- request_done_r
            ------------------
            if fifo_fsm_state = CHECK_REQUEST_DONE and 
            words64_counter = conv_std_logic_vector(0, words64_counter'length) then
                request_done_r <= '1';
            else
                request_done_r <= '0';
            end if;

            ------------------
            -- first_prepare_done_r
            ------------------
            if fifo_fsm_state = IDLE then
                first_prepare_done_r <= '0';
            elsif fifo_fsm_state = PREPARE_REQUEST then
                first_prepare_done_r <= '1';
            end if;

            ------------------
            -- words64_counter
            ------------------
            if fifo_fsm_state = PREPARE_REQUEST then
                if first_prepare_done_r = '0' then
                    words64_counter <= words64;
                end if;
            elsif fifo_fsm_state = DECREMENT_WORDS64_COUNTER then
                if words64_counter /= conv_std_logic_vector(0, words64_counter'length) then
                    words64_counter <= words64_counter - 1;
                end if;
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
