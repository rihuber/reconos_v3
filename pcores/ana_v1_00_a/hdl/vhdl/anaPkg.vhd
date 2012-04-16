
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.headerPkg;
use noc_switch_v1_00_a.utilPkg.all;

package anaPkg is

	-- The number of bits used to represent an IDP
	constant idpWidth : integer := 32;
	
	-- The number of bytes used to represent an IDP
	constant idpBytes : integer := idpWidth/headerPkg.dataWidth;
	
	subtype idpByteCounter is unsigned(toLog2Ceil(idpBytes)-1 downto 0); 
	constant idpByteCounterMax : idpByteCounter := to_unsigned(idpBytes-1, toLog2Ceil(idpBytes));
	
	-- The number of parallel bits in the up- and downstream
	constant dataWidth : integer := headerPkg.dataWidth;
	
	-- The number of bits of the global address
	constant globalAddrWidth : integer := headerPkg.globalAddrWidth;
	
	-- The number of bits of the local address
	constant localAddrWidth : integer := headerPkg.localAddrWidth;
	
	-- The number of bits used to represent a priority
	constant priorityWidth : integer := headerPkg.priorityWidth;
	
	-- The position of the direction bit
	constant directionBit : integer := 0;
	
	-- The position of the 'latency critical' bit
	constant latencyCriticalBit : integer := 1;

end anaPkg;

package body anaPkg is
	
end anaPkg;
