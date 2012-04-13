
library IEEE;
use ieee.std_logic_1164.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.headerPkg;

package hwt_functional_block_pkg is

	-- The number of bits used to represent an IDP
	constant idpWidth : integer := 32;
	
	-- The number of parallel bits in the up- and downstream
	constant dataWidth : integer := headerPkg.dataWidth;
	
	-- The number of bits used to represent a priority
	constant priorityWidth : integer := headerPkg.priorityWidth;

end hwt_functional_block_pkg;

package body hwt_functional_block_pkg is
	
end hwt_functional_block_pkg;
