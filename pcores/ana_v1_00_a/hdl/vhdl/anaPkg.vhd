
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package anaPkg is

	constant addressWidth 	: integer := 6;

	-- The number of bits used to represent an IDP
	constant idpWidth : integer := 32;
	
	-- The number of parallel bits in the up- and downstream
	constant dataWidth : integer := 8;
	
	-- The number of bytes used to represent an IDP
	constant idpBytes : integer := idpWidth/dataWidth;
	
	function toLog2Ceil (x: integer) return integer;
	
	subtype idpByteCounter is unsigned(toLog2Ceil(idpBytes)-1 downto 0); 
	constant idpByteCounterMax : idpByteCounter := to_unsigned(idpBytes-1, toLog2Ceil(idpBytes));
	
	-- The number of bits of the local address
	constant localAddrWidth : integer := 2;
	
	-- The number of bits of the global address
	constant globalAddrWidth : integer := addressWidth - localAddrWidth;
	
	-- The number of bits used to represent a priority
	constant priorityWidth : integer := dataWidth - addressWidth;
	
	-- The position of the direction bit
	constant directionBit : integer := 0;
	
	-- The position of the 'latency critical' bit
	constant latencyCriticalBit : integer := 1;
	
	-- The size of the ring buffer used to send data from software to hardware
	constant sw2hwRamSize : integer := 64;
	
	
end anaPkg;

package body anaPkg is
	
	function toLog2Ceil (x: integer) return integer is
	  variable y,z: integer;
	begin
	  y := 1;
	  z := 2;
	  while x > z loop
	  	y := y + 1;
	  	z := z * 2;
	  end loop;
	  return y;
	end toLog2Ceil;
	
end anaPkg;
