library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;
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

    type t_internal_state is (
-- external_state <= Idle
        IDLE,
        NOP,

-- external_state <= Waiting
        WAIT_SUBSYS,

-- external_state <= ReadingRequest
        ENABLE_REQUEST_CMD_FIFO,
        READ_REQUEST_CMD_FIFO,

        -- ENABLE_REQUEST_DATA_FIFO,
        -- READ_REQUEST_DATA_FIFO,

        WAIT_FOR_SPACE_IN_RESPONSE_DATA_FIFO,
REQUEST_SYNC_POINT,

-- external_state <= Activation
        ACTIVATE,
        WAIT_tRCD,

-- external_state <= Reading
        SET_READ,
        WAIT_CL,
        READING,

-- external_state <= Writing
        SET_WRITE,
        WRITING,
        WAIT_tWR,
        
-- external_state <= Rading or Writing
        WAIT_tRAS,

-- external_state <= WritingResponse
        RESPONSE_SYNC_POINT,

        WRITE_RESPONSE_CMD_FIFO
        -- WRITE_RESPONSE_DATA_FIFO,
    );

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
    
    -- регистры
    signal prev_internal_state : t_internal_state;
    signal      internal_state : t_internal_state;
    signal      external_state : StateFSM_type; -- для подсистемы

    -- захваченная входная команда
    signal request_command_read_en_r   : std_logic;
    signal request_command_r           : std_logic_vector(61 downto 0);

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

    signal nCS_r  : std_logic;
    signal nRAS_r : std_logic;
    signal nCAS_r : std_logic;
    signal nWE_r  : std_logic;
    signal CKE_r  : std_logic;
    signal DQ_r   : std_logic_vector(15 downto 0);
    signal DQM_r  : std_logic_vector(1 downto 0);
    signal BS_r   : std_logic_vector(1 downto 0);
    signal A_r    : std_logic_vector(11 downto 0);

    alias operation_type : std_logic                     is request_command_r(61);
    alias bank_addr      : std_logic_vector(1 downto 0)  is request_command_r(57 downto 56);
    alias row_addr       : std_logic_vector(11 downto 0) is request_command_r(55 downto 44);
    alias col_addr       : std_logic_vector(7 downto 0)  is request_command_r(43 downto 36);
    alias data64_len     : std_logic_vector(11 downto 0) is request_command_r(35 downto 24);
    alias be_first       : std_logic_vector(7 downto 0)  is request_command_r(23 downto 16);
    alias be_last        : std_logic_vector(7 downto 0)  is request_command_r(15 downto 8);
    alias operation_id   : std_logic_vector(7 downto 0)  is request_command_r(7 downto 0);

    signal data64_counter : std_logic_vector(11 downto 0); -- Счетчик слов от Avalon



    constant BURST_BITS : integer := BurstLength * DataWidth;
    constant VEC64_NUM  : integer := ceil_div(BURST_BITS, 64);

    type t_vec64_array is array (0 to NUM64-1) of std_logic_vector(63 downto 0);
    signal buf64 : t_vec64_array;
    
    signal word64_counter : std_logic_vector(VEC64_NUM-1 downto 0); -- Счетчик 64 битных слов для загрузки в сдвиговый регистр
    signal frag_counter   : std_logic_vector(7 downto 0);
    
    -------------------------------------------------------------------------
    -- DATA PACKER (buf64[]) для 1 burst
    -------------------------------------------------------------------------




    signal start_new_cmd  : std_logic;
    signal start_fill     : std_logic;
    signal fill_active    : std_logic;
    signal fill_done      : std_logic;

    signal rem64_cnt      : unsigned(11 downto 0); -- сколько 64b слов ещё можно взять из FIFO по запросу

    signal buf_idx        : integer range 0 to NUM64-1;
    signal buf_bit        : integer range 0 to 63;
    signal filled_bits    : integer range 0 to BURST_BITS;

    signal fifo_cache       : std_logic_vector(63 downto 0);
    signal fifo_cache_valid : std_logic;
    signal fifo_bit_ptr     : integer range 0 to 63;

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

    fsm_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            prev_internal_state <= IDLE;
                 internal_state <= IDLE;
        
        elsif rising_edge(clk) then
            
            if internal_state /= WAIT_SUBSYS then
                prev_internal_state <= internal_state;
            end if;

            case internal_state is
                ------------------
                -- IDLE
                ------------------
                when IDLE =>
                    if state_subsys = ValidOp then
                        internal_state <= NOP;
                    else
                        internal_state <= WAIT_SUBSYS;
                    end if;

                ------------------
                -- NOP
                ------------------
                when NOP =>
                    if state_subsys = ValidOp then
                        if request_command_fifo_empty = '0' then
                            internal_state <= ENABLE_REQUEST_CMD_FIFO;
                        else
                            internal_state <= NOP;
                        end if;
                    else
                        internal_state <= WAIT_SUBSYS;
                    end if;

                ------------------
                -- WAIT_SUBSYS
                ------------------
                when WAIT_SUBSYS =>
                    if state_subsys = ValidOp then
                        if prev_internal_state = NOP or
			   prev_internal_state = IDLE then
                            internal_state <= NOP;
                        elsif prev_internal_state = WAIT_tRAS then 
                            internal_state <= RESPONSE_SYNC_POINT;
                        else
                            internal_state <= IDLE; -- для отладки
                        end if;
                    else
                        internal_state <= WAIT_SUBSYS;
                    end if;
                
                ------------------
                -- ENABLE_REQUEST_CMD_FIFO
                ------------------
                when ENABLE_REQUEST_CMD_FIFO =>
                    internal_state <= READ_REQUEST_CMD_FIFO;

                ------------------
                -- READ_REQUEST_CMD_FIFO
                ------------------
                when READ_REQUEST_CMD_FIFO =>
                    internal_state <= WAIT_FOR_SPACE_IN_RESPONSE_DATA_FIFO;

                ------------------
                -- WAIT_FOR_SPACE_IN_RESPONSE_DATA_FIFO
                ------------------
                -- TODO
                when WAIT_FOR_SPACE_IN_RESPONSE_DATA_FIFO =>
                    internal_state <= REQUEST_SYNC_POINT;
--                    if operation_type = '1' then
--                        internal_state <= REQUEST_SYNC_POINT;
--                    
--                    else
--                        if (all - used) < data_len then
--                            internal_state <= WAIT_FOR_SPACE_IN_RESPONSE_DATA_FIFO;
--                        else
--                            internal_state <= REQUEST_SYNC_POINT;
--                        end if;
--                    end if;

                ------------------
                -- REQUEST_SYNC_POINT
                ------------------
                when REQUEST_SYNC_POINT =>
                    internal_state <= ACTIVATE;

                ------------------
                -- ACTIVATE
                ------------------
                when ACTIVATE =>
                    internal_state <= WAIT_tRCD;

                ------------------
                -- WAIT_tRCD
                ------------------
                when WAIT_tRCD =>
                    if trcd_counter = conv_std_logic_vector(0, trcd_counter'length) then
                        if operation_type = '0' then
                            internal_state <= SET_READ;
                        else
                            internal_state <= SET_WRITE;
                        end if;
                    else
                        internal_state <= WAIT_tRCD;
                    end if;

                ------------------
                -- SET_READ
                ------------------
                when SET_READ =>
                    internal_state <= WAIT_CL;

                ------------------
                -- WAIT_CL
                ------------------
                when WAIT_CL =>
                    if cl_counter = conv_std_logic_vector(0, cl_counter'length) then
                        internal_state <= READING;
                    else
                        internal_state <= WAIT_CL;
                    end if;

                ------------------
                -- READ
                ------------------
                when READING =>
                    -- burst_counter
                    if burst_counter = conv_std_logic_vector(0, burst_counter'length) then
                        internal_state <= WAIT_tRAS;
                    else
                        internal_state <= READING;
                    end if;

                ------------------
                -- SET_WRITE
                ------------------
                when SET_WRITE =>
                    internal_state <= WRITING;

                ------------------
                -- WRITE
                ------------------
                when WRITING =>
                    -- burst_counter
                    if burst_counter = conv_std_logic_vector(0, burst_counter'length) then
                        internal_state <= WAIT_tWR;
                    else
                        internal_state <= WRITING;
                    end if;
                
                ------------------
                -- WAIT_tWR
                ------------------
                when WAIT_tWR =>
                    if twr_counter = conv_std_logic_vector(0, twr_counter'length) then
                        internal_state <= WAIT_tRAS;
                    else
                        internal_state <= WAIT_tWR;
                    end if;

                ------------------
                -- WAIT_tRAS
                ------------------
                when WAIT_tRAS =>
                    if tras_counter = conv_std_logic_vector(0, tras_counter'length) then
                        internal_state <= WAIT_SUBSYS;
                    else
                        internal_state <= WAIT_tRAS;
                    end if;


                ------------------
                -- RESPONSE_SYNC_POINT
                ------------------
                when RESPONSE_SYNC_POINT =>
                    internal_state <= WRITE_RESPONSE_CMD_FIFO;

                ------------------
                -- WRITE_RESPONSE_CMD_FIFO
                ------------------
                when WRITE_RESPONSE_CMD_FIFO =>
                    if response_command_fifo_full = '0' then
                        internal_state <= NOP;
                    else
                        internal_state <= WRITE_RESPONSE_CMD_FIFO;
                    end if;

                when others =>
                    internal_state <= IDLE;
            end case;
        end if;
    end process fsm_proc;

    logic_proc : process(clk, nRst)
    begin
        if nRst = '0' then
            external_state <= IDLE;

            -- счётчики
            trcd_counter  <= (others => '0');
            cl_counter    <= (others => '0');
            burst_counter <= (others => '0');
            twr_counter   <= (others => '0');
            tras_counter  <= (others => '0');

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

            -- TODO Лучше сделать отдельный процесс external_state_proc???
            -- или оставить как есть
            if internal_state = IDLE then

                external_state <= Idle;
					 
				elsif internal_state = NOP then
				
					 external_state <= Nop;

            elsif internal_state = WAIT_SUBSYS then

                external_state <= Waiting;

            elsif internal_state = ENABLE_REQUEST_CMD_FIFO              or
                  internal_state = READ_REQUEST_CMD_FIFO                or 
                  internal_state = WAIT_FOR_SPACE_IN_RESPONSE_DATA_FIFO or
                  internal_state = REQUEST_SYNC_POINT                   then

                external_state <= ReadingRequest;

            elsif internal_state = ACTIVATE                             or
                  internal_state = WAIT_tRCD                            then

                external_state <= Activation;
            
            elsif internal_state = SET_READ                             or
                  internal_state = WAIT_CL                              or
                  internal_state = READING                              or
                  (internal_state = WAIT_tRAS and operation_type = '0') then

                external_state <= Reading;

            elsif internal_state = SET_WRITE                            or
                  internal_state = WRITING                              or
                  internal_state = WAIT_tWR                             or
                  (internal_state = WAIT_tRAS and operation_type = '1') then

                external_state <= Writing;

            elsif internal_state = RESPONSE_SYNC_POINT                  or
                  internal_state = WRITE_RESPONSE_CMD_FIFO              then

                external_state <= WritingResponse;
            
            end if;

------------------------------------------------------
            -- COUNTERS
------------------------------------------------------

            ------------------
            -- trcd_counter
            ------------------
            if internal_state = WAIT_tRCD then
                if trcd_counter /= conv_std_logic_vector(0, trcd_counter'length) then
                    trcd_counter <= trcd_counter - 1;
                end if;
            else -- if internal_state = ACTIVATE then
                trcd_counter <= conv_std_logic_vector(TRCD_MAX-1, trcd_counter'length);
            end if;

            ------------------
            -- cl_counter
            ------------------
            if internal_state = WAIT_CL then
                if cl_counter /= conv_std_logic_vector(0, cl_counter'length) then
                    cl_counter <= cl_counter - 1;
                end if;
            else -- if internal_state = SET_READ then
                cl_counter <= conv_std_logic_vector(CL_MAX-1, cl_counter'length);
            end if;

            ------------------
            -- burst_counter
            ------------------
            if internal_state = READING or internal_state = WRITING then
                if burst_counter /= conv_std_logic_vector(0, burst_counter'length) then
                    burst_counter <= burst_counter - 1;
                end if;
            else -- if internal_state = SET_WRITE or internal_state = WAIT_CL then
                burst_counter <= conv_std_logic_vector(BURST_MAX-1, burst_counter'length);
            end if;

            ------------------
            -- twr_counter
            ------------------
            if internal_state = WAIT_tWR then
                if twr_counter /= conv_std_logic_vector(0, twr_counter'length) then
                    twr_counter <= twr_counter - 1;
                end if;
            else -- if internal_state = WRITE then
                twr_counter <= conv_std_logic_vector(TWR_MAX-1, twr_counter'length);
            end if;

            ------------------
            -- tras_counter !!! Особенный
            ------------------
            if tras_counter /= conv_std_logic_vector(0, tras_counter'length) then
                tras_counter <= tras_counter - 1;
            elsif internal_state = ACTIVATE then
                tras_counter <= conv_std_logic_vector(TRAS_MAX-1, tras_counter'length);
            end if;


------------------------------------------------------
            -- FROM AVALON (CMD)
------------------------------------------------------

            ------------------
            -- request_command_read_en_r
            ------------------
            if internal_state = ENABLE_REQUEST_CMD_FIFO then
                request_command_read_en_r <= '1';
            else
                request_command_read_en_r <= '0';
            end if;
            
            ------------------
            -- request_command_r
            ------------------
            if internal_state = READ_REQUEST_CMD_FIFO then
               request_command_r <= request_command_fifo_data; 
            end if;

------------------------------------------------------
            -- TODO FROM AVALON (DATA)
------------------------------------------------------

--          ------------------
--          -- request_data_read_en_r
--          ------------------
--          if internal_state = ENABLE_REQUEST_DATA_FIFO then
--              request_data_read_en_r <= '1';
--          else
--              request_data_read_en_r <= '0';
--          end if;
--            
--          ------------------
--          -- request_data_r
--          ------------------
--          if internal_state = READ_REQUEST_DATA_FIFO then
--             request_data_r <= request_data_fifo_data; 
--          end if;
            
------------------------------------------------------
            -- TO AVALON (CMD)
------------------------------------------------------

            ------------------
            -- response_command_write_en_r
            ------------------
            if internal_state = WRITE_RESPONSE_CMD_FIFO and response_command_fifo_full = '0' then
                response_command_write_en_r <= '1';
            else
                response_command_write_en_r <= '0';
            end if;

            ------------------
            -- response_command_r
            ------------------
            if internal_state = WRITE_RESPONSE_CMD_FIFO and response_command_fifo_full = '0' then
                response_command_r(19 downto 8) <= data_len;
                response_command_r(7 downto 0)  <= operation_id;
            end if;

------------------------------------------------------
            -- TODO TO AVALON (DATA)
------------------------------------------------------

--          ------------------     
--          -- response_data_write_en_r
--          ------------------
--          if internal_state = WRITE_RESPONSE_DATA_FIFO then
--              request_data_write_en_r <= '1';
--          else
--              request_data_write_en_r <= '0';
--          end if;
--            
--          ------------------
--          -- response_data_r
--          ------------------
--          if internal_state = WRITE_RESPONSE_DATA_FIFO then
--             request_data_r <= ??? 
--          end if;

------------------------------------------------------
            -- TO ARBITER
------------------------------------------------------

            ------------------
            -- nCS_r
            ------------------
            if internal_state = IDLE then
                nCS_r <= '1';
            else
                nCS_r <= '0';
            end if;

            ------------------
            -- nRAS_r
            ------------------
            if internal_state = ACTIVATE then
                nRAS_r <= '0';
            else
                nRAS_r <= '1';
            end if;

            ------------------
            -- nCAS_r
            ------------------
            if internal_state = SET_READ  or
               internal_state = SET_WRITE then
                nCAS_r <= '0';
            else
                nCAS_r <= '1';
            end if;

            ------------------
            -- nWE_r
            ------------------
            if internal_state = SET_WRITE then
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
            if internal_state = ACTIVATE  or
               internal_state = SET_READ  or
               internal_state = SET_WRITE then
                BS_r <= bank_addr;
            end if;

            ------------------
            -- A_r
            ------------------
            if internal_state = ACTIVATE then
                A_r <= row_addr;
            elsif internal_state = SET_READ or
                  internal_state = SET_WRITE then
                A_r(11 downto 0) <= (others => '0');
                A_r(7 downto 0)  <= col_addr;
            end if;
        end if;
    end process logic_proc;


    packer_proc : process(clk, nRst)
    begin
        if nRst = '0' then
             
        elsif rising_edge(clk) then

end rtl;
