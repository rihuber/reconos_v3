library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ana_v1_00_a;
use ana_v1_00_a.anaPkg.all;

entity packetEncoder is
	port (
		clk 					: in  std_logic;
		reset 					: in  std_logic;
		
		-- Signals to the switch
		upstreamFull			: in  std_logic;
		upstreamData			: out std_logic_vector(dataWidth downto 0);
		upstreamWriteEnable 	: out std_logic;
		
		-- Decoded values of the packet
		startOfPacket			: in  std_logic; 									-- Indicates the start of a new packet
		endOfPacket				: in  std_logic; 									-- Indicates the end of the packet
		data					: in  std_logic_vector(dataWidth-1 downto 0); 		-- The current data byte
		dataValid				: in  std_logic; 									-- '1' if the data are valid, '0' else
		globalAddress			: in  std_logic_vector(globalAddrWidth-1 downto 0);	-- The global hardware address of the destination
		localAddress			: in  std_logic_vector(localAddrWidth-1 downto 0);	-- The local hardware address of the destination
		direction				: in  std_logic; 									-- '1' for egress, '0' for ingress
		priority				: in  std_logic_vector(priorityWidth-1 downto 0); 	-- The priority of the packet
		latencyCritical			: in  std_logic; 									-- '1' if this packet is latency critical
		srcIdp					: in  std_logic_vector(idpWidth-1 downto 0); 		-- The source IDP
		dstIdp					: in  std_logic_vector(idpWidth-1 downto 0); 		-- The destination IDP
		readEnable				: out std_logic										-- Read enable for the applied data
	);
end entity packetEncoder;

architecture rtl of packetEncoder is
	
	type state_t is ( STATE_IDLE,
					STATE_ENCODE_HEADER_1,
					STATE_ENCODE_HEADER_2,
					STATE_ENCODE_SRC_IDP,
					STATE_ENCODE_DST_IDP,
					STATE_PACKET_TRANSFER );
	
	signal state_n, state_p						: state_t;
	signal direction_n, direction_p 			: std_logic;
	signal priority_n, priority_p 				: std_logic_vector(priorityWidth-1 downto 0);
	signal latencyCritical_n, latencyCritical_p	: std_logic;
	signal srcIdp_n, srcIdp_p					: std_logic_vector(idpWidth-1 downto 0);
	signal dstIdp_n, dstIdp_p					: std_logic_vector(idpWidth-1 downto 0);
	signal idpByteCounter_n, idpByteCounter_p	: idpByteCounter;
	signal globalAddress_n, globalAddress_p		: std_logic_vector(globalAddrWidth-1 downto 0);
	signal localAddress_n, localAddress_p		: std_logic_vector(localAddrWidth-1 downto 0);
	
	function createHeaderByte1(prio: std_logic_vector(priorityWidth-1 downto 0);
							   globAddr: std_logic_vector(globalAddrWidth-1 downto 0);
							   locAddr: std_logic_vector(localAddrWidth-1 downto 0)) return std_logic_vector is
		variable result : std_logic_vector(dataWidth-1 downto 0);
	begin
		result(dataWidth-1 downto dataWidth-priorityWidth) := prio;
		result(dataWidth-priorityWidth-1 downto dataWidth-priorityWidth-globalAddrWidth) := globAddr;
		result(dataWidth-priorityWidth-globalAddrWidth-1 downto dataWidth-priorityWidth-globalAddrWidth-localAddrWidth) := locAddr;
		return result;
	end createHeaderByte1;
	
	function createHeaderByte2(dir: std_logic; latCrit: std_logic) return std_logic_vector is
		variable result : std_logic_vector(dataWidth-1 downto 0) := (others => '-');
	begin
		result(directionBit) := dir;
		result(latencyCriticalBit) := latCrit;
		return result;
	end createHeaderByte2;
	
	
begin

	-- output
	nomem_output : process(state_p, priority_p, globalAddress_p, localAddress_p, direction_p, latencyCritical_p, srcIdp_p, idpByteCounter_p, dstIdp_p, data, endOfPacket, dataValid, upstreamFull)
	begin
		-- default assingents
		upstreamData(dataWidth-1 downto 0) <= (others => '-');
		upstreamData(dataWidth) <= '-';
		upstreamWriteEnable <= '0';
		readEnable <= '0';
		
		case state_p is
			when STATE_IDLE =>
				
			when STATE_ENCODE_HEADER_1 =>
				upstreamData(dataWidth-1 downto 0) <= createHeaderByte1(priority_p, globalAddress_p, localAddress_p);
				upstreamData(dataWidth) <= '0';
				upstreamWriteEnable <= '1';
				
			when STATE_ENCODE_HEADER_2 =>
				upstreamData(dataWidth-1 downto 0) <= createHeaderByte2(direction_p, latencyCritical_p);
				upstreamData(dataWidth) <= '0';
				upstreamWriteEnable <= '1';
			
			when STATE_ENCODE_SRC_IDP =>	
				upstreamData(dataWidth-1 downto 0) <= srcIdp_p((to_integer(idpByteCounter_p)*dataWidth) + (dataWidth-1) downto to_integer(idpByteCounter_p)*dataWidth);
				upstreamData(dataWidth) <= '0';
				upstreamWriteEnable <= '1';
			
			when STATE_ENCODE_DST_IDP =>	
				upstreamData(dataWidth-1 downto 0) <= dstIdp_p((to_integer(idpByteCounter_p)*dataWidth) + (dataWidth-1) downto to_integer(idpByteCounter_p)*dataWidth);
				upstreamData(dataWidth) <= '0';
				upstreamWriteEnable <= '1';
				
			when STATE_PACKET_TRANSFER =>
				upstreamData(dataWidth-1 downto 0) <= data;
				upstreamData(dataWidth) <= endOfPacket;
				upstreamWriteEnable <= dataValid;
				if dataValid = '1' then
					readEnable <= not upstreamFull;
				else
					readEnable <= '0';
				end if;
		end case;
	end process nomem_output;
	
	-- local address
	localAddress_n <= localAddress when dataValid = '1' and state_p = STATE_IDLE
				  else localAddress_p;
				  
  	-- global address
	globalAddress_n <= globalAddress when dataValid = '1' and state_p = STATE_IDLE
				  else globalAddress_p;
	
	-- priority
	priority_n <= priority when dataValid = '1' and state_p = STATE_IDLE
				  else priority_p;
	
	--direction
	direction_n <= direction when dataValid = '1' and state_p = STATE_IDLE
				   else direction_p;

	-- latency critical
	latencyCritical_n <= latencyCritical when dataValid = '1' and state_p = STATE_IDLE
						 else latencyCritical_p;
	
	-- src idp
	srcIdp_n <= srcIdp when dataValid = '1' and state_p = STATE_IDLE
				else srcIdp_p;
	
	-- dst idp
	dstIdp_n <= dstIdp when dataValid = '1' and state_p = STATE_IDLE
				else dstIdp_p;
	
	nomem_idpByteCounter : process(state_p, idpByteCounter_p, upstreamFull)
	begin
		idpByteCounter_n <= idpByteCounterMax;
		if state_p = STATE_ENCODE_SRC_IDP or state_p = STATE_ENCODE_DST_IDP then
			if upstreamFull = '0' and idpByteCounter_p /= 0 then
				idpByteCounter_n <= idpByteCounter_p - 1;
			end if;
		end if;
	end process nomem_idpByteCounter;

	nomem_nextState : process(state_p, dataValid, startOfPacket, upstreamFull, idpByteCounter_p, endOfPacket)
	begin
		-- Default: keep current state
		state_n <= state_p;
		
		case state_p is
			when STATE_IDLE =>
				if dataValid = '1' and startOfPacket = '1' then
					state_n <= STATE_ENCODE_HEADER_1;
				end if;
				
			when STATE_ENCODE_HEADER_1 =>
				if upstreamFull = '0' then
					state_n <= STATE_ENCODE_HEADER_2;
				end if;
				
			when STATE_ENCODE_HEADER_2 =>
				if upstreamFull = '0' then
					state_n <= STATE_ENCODE_SRC_IDP;
				end if;
			
			when STATE_ENCODE_SRC_IDP =>
				if upstreamFull = '0' and idpByteCounter_p = 0 then
					state_n <= STATE_ENCODE_DST_IDP;
				end if;
			
			when STATE_ENCODE_DST_IDP =>
				if upstreamFull = '0' and idpByteCounter_p = 0 then
					state_n <= STATE_PACKET_TRANSFER;
				end if;
				
			when STATE_PACKET_TRANSFER =>
				if upstreamFull = '0' and endOfPacket = '1' then
					state_n <= STATE_IDLE;
				end if;
		end case;
		
	end process nomem_nextState;

	mem_stateTransition : process(clk, reset)
	begin
		if reset = '1' then
			state_p <= STATE_IDLE;
			direction_p <= '-';
			priority_p <= (others => '-');
			idpByteCounter_p <= idpByteCounterMax;
			srcIdp_p <= (others => '-');
			dstIdp_p <= (others => '-');
			latencyCritical_p <= '-';
			globalAddress_p <= (others => '-');
			localAddress_p <= (others => '-');
		elsif rising_edge(clk) then
			state_p <= state_n;
			direction_p <= direction_n;
			priority_p <= priority_n;
			idpByteCounter_p <= idpByteCounter_n;
			latencyCritical_p <= latencyCritical_n;
			srcIdp_p <= srcIdp_n;
			dstIdp_p <= dstIdp_n;
			globalAddress_p <= globalAddress_n;
			localAddress_p <= localAddress_n;
		end if;
	end process mem_stateTransition;

end architecture rtl;

