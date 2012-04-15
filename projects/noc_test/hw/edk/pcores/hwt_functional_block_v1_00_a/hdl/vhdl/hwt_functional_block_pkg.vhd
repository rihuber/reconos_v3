
library IEEE;
use ieee.std_logic_1164.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.headerPkg;
use noc_switch_v1_00_a.utilPkg.all;

package hwt_functional_block_pkg is

	-- The number of bits used to represent an IDP
	constant idpWidth : integer := 32;
	
	-- The number of bytes used to represent an IDP
	constant idpBytes : integer := idpWidth/dataWidth;
	
	subtype idpByteCounter is unsigned(toLog2Ceil(idpBytes) downto 0); 
	constant idpByteCounterMax : idpByteCounter := to_unsigned(idpBytes-1, toLog2Ceil(idpBytes));
	
	-- The number of parallel bits in the up- and downstream
	constant dataWidth : integer := headerPkg.dataWidth;
	
	-- The number of bits used to represent a priority
	constant priorityWidth : integer := headerPkg.priorityWidth;
	
	-- The position of the direction bit
	constant directionBit : integer := 0;
	
	-- The position of the 'latency critical' bit
	constant latencyCriticalBit : integer := 1;

end hwt_functional_block_pkg;

package body hwt_functional_block_pkg is
	
end hwt_functional_block_pkg;
