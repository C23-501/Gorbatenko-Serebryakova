library ieee;
use ieee.std_logic_1164.all;

entity read_shift_reg_tb is
end entity;

architecture sim of read_shift_reg_tb is
begin

  T_8_1 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 8, BURST => 1 );

  T_8_2 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 8, BURST => 2 );

  T_8_4 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 8, BURST => 4 );

  T_8_8 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 8, BURST => 8 );

  T_16_1 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 16, BURST => 1 );

  T_16_2 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 16, BURST => 2 );

  T_16_4 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 16, BURST => 4 );

  T_16_8 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 16, BURST => 8 );

  T_32_1 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 32, BURST => 1 );

  T_32_2 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 32, BURST => 2 );

  T_32_4 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 32, BURST => 4 );

  T_32_8 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 32, BURST => 8 );

  T_64_1 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 64, BURST => 1 );

  T_64_2 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 64, BURST => 2 );

  T_64_4 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 64, BURST => 4 );

  T_64_8 : entity work.read_shift_reg_tester
    generic map ( WORD_WIDTH => 64, BURST => 8 );

end architecture;

