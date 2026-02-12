LIBRARY ieee;
USE ieee.std_logic_1164.all;

PACKAGE sdram_subsys_package IS
  type StateFSM_type is (Idle, Waiting, Nop, Reading, ReadingRequest, WritingResponse, Writing, Activation);
  type StateSubsys_type is (Idle, Ctr_request, Precharge, SetMR, Refresh, ValidOp, Waiting_precharge, Waiting_SetMR, Waiting_refresh);
END sdram_subsys_package;
