LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
LIBRARY work;
USE work.sdram_subsys_package.ALL;

ENTITY SdramArbiter IS
   PORT( 
      -- Общие
      nRst        : IN     std_logic;
      CLK         : IN     std_logic;
      -- От FSM
      StateFSM    : IN     StateFSM_type;
      nCS_FSM     : IN     std_logic;
      nRAS_FSM    : IN     std_logic;
      nCAS_FSM    : IN     std_logic;
      nWE_FSM     : IN     std_logic;
      CKE_FSM     : IN     std_logic;
      DQM_FSM     : IN     std_logic_vector (1 DOWNTO 0);
      BS_FSM      : IN     std_logic_vector (1 DOWNTO 0);
      A_FSM       : IN     std_logic_vector (11 DOWNTO 0);
      --  От подсистемы
      nCS_Subsys  : IN     std_logic;
      nRAS_Subsys : IN     std_logic;
      nCAS_Subsys : IN     std_logic;
      nWE_Subsys  : IN     std_logic;
      CKE_Subsys  : IN     std_logic;
      DQM_Subsys  : IN     std_logic_vector(1 DOWNTO 0);
      BS_Subsys   : IN     std_logic_vector (1 DOWNTO 0);
      A_Subsys    : IN     std_logic_vector (11 DOWNTO 0);
      --  Выходы на SDRAM
      nCS         : OUT    std_logic;
      nRAS        : OUT    std_logic;
      nCAS        : OUT    std_logic;
      nWE         : OUT    std_logic;
      CKE         : OUT    std_logic;
      DQM         : OUT    std_logic_vector (1 DOWNTO 0);
      BS          : OUT    std_logic_vector (1 DOWNTO 0);
      A           : OUT    std_logic_vector (11 DOWNTO 0)
   );

-- Declarations

END SdramArbiter ;

--
ARCHITECTURE rtl OF SdramArbiter IS
  --
  signal nCS_r           :  std_logic;
  signal nRAS_r          :  std_logic;
  signal nCAS_r          :  std_logic;
  signal nWE_r           :  std_logic;
  signal CKE_r           :  std_logic;
  signal DQM_r           :  std_logic_vector(1 downto 0);
  signal BS_r            :  std_logic_vector(1 downto 0);
  signal A_r             :  std_logic_vector(11 downto 0);
  --
BEGIN
  --
  nCS <= nCS_r;
  nRAS <= nRAS_r;
  nCAS <= nCAS_r;
  nWE <= nWE_r;
  CKE <= CKE_r;
  DQM <= DQM_r;
  BS <= BS_r;
  A <= A_r;
  --

  process(nRst, CLK) is
  begin
    if (nRst = '0') then
      nCS_r <= '0';
      nRAS_r <= '0';
      nCAS_r <= '0';
      nWE_r <= '0';
      CKE_r <= '0';
      DQM_r <= "00";
      BS_r <= (others => '0');
      A_r <= (others => '0');
    elsif (rising_edge(CLK)) then
      if (StateFSM = Waiting or StateFSM = Idle) then
        nCS_r <= nCS_Subsys;
        nRAS_r <= nRAS_Subsys;
        nCAS_r <= nCAS_Subsys;
        nWE_r <= nWE_Subsys;
        CKE_r <= CKE_Subsys;
        DQM_r <= DQM_Subsys;
        BS_r <= BS_Subsys;
        A_r <= A_Subsys;
      else
        nCS_r <= nCS_FSM;
        nRAS_r <= nRAS_FSM;
        nCAS_r <= nCAS_FSM;
        nWE_r <= nWE_FSM;
        CKE_r <= CKE_FSM;
        DQM_r <= DQM_FSM;
        BS_r <= BS_FSM;
        A_r <= A_FSM;
      end if;
    end if;
  end process;
END ARCHITECTURE rtl;