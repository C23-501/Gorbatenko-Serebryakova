LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;

LIBRARY work;
USE work.sdram_subsys_package.ALL;

ENTITY SdramSubsys IS
   GENERIC( 
      Burst_length : integer := 8;
      CAS_Latency  : integer := 3;
      CLK_Freq_MHz : integer := 160
   );
   PORT( 
      -- Общие
      nRst      : IN     std_logic;
      CLK       : IN     std_logic;
      -- Входы с FSM
      StateFSM  : IN     StateSdramFsm_type;
      A_FSM     : IN     std_logic_vector (11 DOWNTO 0);
      -- Выходы на арбитр
      nCS       : OUT    std_logic;
      nRAS      : OUT    std_logic;
      nCAS      : OUT    std_logic;
      nWE       : OUT    std_logic;
      CKE       : OUT    std_logic;
      DQM       : OUT    std_logic_vector (1 DOWNTO 0);
      BS        : OUT    std_logic_vector (1 DOWNTO 0);
      A         : OUT    std_logic_vector (11 DOWNTO 0);
      State_out : OUT    StateSubsys_type
   );

-- Declarations

END SdramSubsys ;

--
ARCHITECTURE rtl OF SdramSubsys IS
  
  -- state
  signal State           :  StateSubsys_type := Idle;
  signal PrevStateFSM    :  StateFSM_type;
  
  -- constants

  constant REF_TIME : integer := 64_000 * CLK_Freq_MHz / 4096;
  constant INIT_COUNTER_MAX : integer := 200 * CLK_Freq_MHz;
  constant Addr_default : std_logic_vector(11 downto 0) := "010000000000";

  signal Wait_counter : std_logic_vector(integer(floor(log2(real(INIT_COUNTER_MAX)))) downto 0);
  
  -- refresh
  signal Ref_clk_counter    :  std_logic_vector(3 downto 0);
  
  -- precharge
  signal PrechargeDone_flag :  std_logic;
  signal PrechargetoActive_r : std_logic;
  
  -- Инициализация SDRAM
  signal Ref_cycles_counter : std_logic_vector(2 downto 0);
  signal MRSetDone : std_logic;

  -- Mode Register value (A[11:0]) для команды Load Mode Register
  signal MR_value : std_logic_vector(11 downto 0);
  --
BEGIN
  --  Проверка generic
  assert (Burst_length = 1 or Burst_length = 2 or Burst_length = 4 or Burst_length = 8 or Burst_length = 16)
    report "Burst length must be equal 1, 2, 4, 8 or 16 (full page)" severity error;

  assert (CAS_Latency = 2 or CAS_Latency = 3)
    report "CAS_Latency must be equal 2 or 3" severity error;

  assert (CLK_Freq_MHz > 0)
    report "CLK_Freq_MHz must be positive" severity error;
  --
  --
  State_out <= State;
  nCS <= '0' when State = Refresh or State = Precharge or State = SetMR else '1';
  nRAS <= '0' when State = Precharge or State = Refresh or State = SetMR else '1';
  nCAS <= '0' when State = SetMR or State = Refresh else '1';
  nWE <= '0' when State = SetMR or State = Precharge else '1';
  A <= MR_value when State = SetMR else Addr_default;
  BS <= (others => '0');
  CKE <= '1';
  DQM <= "11";
  --
  -------------------  Mode Register ----------------------------
  -- Burst Length
  MR_value(2 downto 0) <= "000" when burst_length = 1 else
                          "001" when burst_length = 2 else
                          "010" when burst_length = 4 else
                          "011" when burst_length = 8 else
                          "111" when burst_length = 256 else
                          "000";

  -- Addressing mode (Sequential)
  MR_value(3) <= '0';

  -- CAS Latency
  MR_value(6 downto 4) <= "010" when cas_latency = 2 else
                          "011" when cas_latency = 3 else
                          "000";

  -- Write mode (Burst read and burst write)
  MR_value(9) <= '0';

  -- Reserved
  MR_value(8 downto 7)   <= "00";
  MR_value(11 downto 10) <= "00";

  ---------------------------------------------------------------

  States : process(nRst, CLK)
  begin
    if (nRst = '0') then
      State <= Idle;
    elsif rising_edge(CLK) then
      case State is
        
            ----------------------------------------------------------------------
            -- IDLE
            ----------------------------------------------------------------------
            when Idle =>
                -- Переход в Ctr_request, когда Wait_counter = 0
                if Wait_counter = conv_std_logic_vector(0, Wait_counter'length) then
                    State <= Ctr_request;
                else
                    State <= Idle;
                end if;

            ----------------------------------------------------------------------
            -- Ctr_request
            ----------------------------------------------------------------------
            when Ctr_request =>
                -- Переход возможен только когда StateFSM = Waiting
                if StateFSM = Waiting then
                    -- Precharge
                    if (PrechargeDone_flag = '0' or MRSetDone = '0') then
                        State <= Precharge;
                    -- Refresh
                    elsif (PrechargeDone_flag = '1' and Wait_counter = conv_std_logic_vector(0, Wait_counter'length)) then
                        State <= Refresh;
                    end if;
                else
                    State <= Ctr_request;
                end if;

            ----------------------------------------------------------------------
            -- Precharge
            ----------------------------------------------------------------------
            when Precharge =>
                State <= Waiting_precharge;

            ----------------------------------------------------------------------
            -- Waiting_precharge
            ----------------------------------------------------------------------
            when Waiting_precharge =>
                -- Переход только при PrechargetoActive_r = '0'
                if PrechargetoActive_r = '0' then
                    -- SetMR
                    if MRSetDone = '0' then
                        State <= SetMR;
                    -- Refresh
                    elsif Wait_counter = conv_std_logic_vector(0, Wait_counter'length) then
                        State <= Refresh;
                    else
                        State <= ValidOP;
                    end if;
                else
                    State <= Waiting_precharge;
                end if;
                
            ----------------------------------------------------------------------
            -- SetMR
            ----------------------------------------------------------------------
            when SetMR =>
                State <= Waiting_SetMR;

            ----------------------------------------------------------------------
            -- Waiting_SetMR
            ----------------------------------------------------------------------
            when Waiting_SetMR =>
                State <= Refresh;

            ----------------------------------------------------------------------
            -- Refresh
            ----------------------------------------------------------------------
            when Refresh =>
                State <= Waiting_refresh;

            ----------------------------------------------------------------------
            -- Waiting_refresh
            ----------------------------------------------------------------------
            when Waiting_refresh =>
              if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
                if (Ref_cycles_counter = conv_std_logic_vector(0, Ref_cycles_counter'length)) then
                  State <= ValidOp;
                else
                  State <= Refresh;
                end if;
              end if;
              
            ----------------------------------------------------------------------
            -- ValidOp
            ----------------------------------------------------------------------
            when ValidOp =>
                -- ValidOp -> Ctr_request
                if (Wait_counter = conv_std_logic_vector(0, Wait_counter'length)) or
                   ((StateFSM /= PrevStateFSM) and
                    (PrevStateFSM = Reading or PrevStateFSM = Writing) and
                    PrechargeDone_flag = '0') then
                    State <= Ctr_request;
                else
                    State <= ValidOp;
                end if;

            when others =>
                State <= Idle;

        end case;
    end if;
  end process;
  
  --------------------------------------------------------------------
  -- Основная логика: инициализация / refresh / precharge
  --------------------------------------------------------------------
  
  Main_synch_logic: process(nRst, CLK) is
    
  begin
    if (nRst = '0') then
      -- внутренняя логика
      Wait_counter <= conv_std_logic_vector(INIT_COUNTER_MAX, Wait_counter'length);
      MRSetDone <= '0';
      PrechargeDone_flag <= '0';
      Ref_cycles_counter <= conv_std_logic_vector(7, Ref_cycles_counter'length);
      Ref_clk_counter <= conv_std_logic_vector(9, Ref_clk_counter'length);
      PrechargetoActive_r <= '1';
    elsif (rising_edge(CLK)) then
      PrevStateFSM <= StateFSM;
      
------------------------------------------------------------------------------------------------------------- Флаги

      --  PrechargeDone_flag  (флаг, показывающий, был ли сделан precharge)
      if (StateFSM = Reading or StateFSM = Writing) then   -- Чтение или запись с autoprecharge
        if (A_FSM(10) = '1') then
          PrechargeDone_flag <= '1';
        elsif (StateFSM /= PrevStateFSM) then
          PrechargeDone_flag <= '0';
        end if;
      elsif (State = Precharge) then   --  Precharge
        PrechargeDone_flag <= '1';
      end if;
      --  MRSetDone
      --if (MRSet_counter = conv_std_logic_vector(0, MRSet_counter'length)) then
      if State = Waiting_SetMR then
        MRSetDone <= '1';
      end if;
      
------------------------------------------------------------------------------------------------------------- Счётчики
      --  Wait_counter (счётчик времени до следующего цикла auto-refresh 64 мс / 4096 и счётчик инициализации 200 мкс)
      if (State /= Refresh and State /= Waiting_refresh) then
        if (Wait_counter /= conv_std_logic_vector(0, Wait_counter'length)) then
          Wait_counter <= Wait_counter - '1';
        end if;
      else
        Wait_counter <= conv_std_logic_vector(REF_TIME, Wait_counter'length);
      end if;
      --  Ref_clk_counter  (счётчик тактов цикла auto-refresh - tRC)
      if (State = Waiting_refresh) then
        if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
          Ref_clk_counter <= conv_std_logic_vector(8, Ref_clk_counter'length);
        else
          Ref_clk_counter <= Ref_clk_counter - '1';
        end if;
      else
        Ref_clk_counter <= conv_std_logic_vector(8, Ref_clk_counter'length);
      end if;
      --  Ref_cycles_counter  (счётчик циклов auto-refresh после установки Mode Register)
      if (State = Waiting_refresh) then
        if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
          Ref_cycles_counter <= Ref_cycles_counter - '1';
        end if;
      elsif (State = ValidOp) then
        Ref_cycles_counter <= conv_std_logic_vector(0, Ref_cycles_counter'length);
      end if;
      -- PrechargetoActive logic (tRP)
      if (State = Waiting_precharge) then
        PrechargetoActive_r <= not PrechargetoActive_r;
      end if;
    end if;
  end process;

END ARCHITECTURE rtl;
