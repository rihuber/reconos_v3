library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwt_functional_block_v1_00_a;
use hwt_functional_block_v1_00_a.hwt_functional_block_pkg.all;

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
end entity packetDecoder;

architecture rtl of packetDecoder is
	
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
	
begin

	-- output
	nomem_output : process(state_p)
	begin
		-- default assingents
		upstreamData(dataWidth-1 downto 0) <= (others => '-');
		upstreamData(dataWidth) <= '0';
		upstreamWriteEnable <= '0';
		readEnable <= '0';
		
		case state_p is
			when STATE_IDLE =>
				
			when STATE_DECODE_HEADER_1 =>
				upstreamData(dataWidth-1 downto dataWidth-prioWidth) <= 
		end case;
		if state_p = STATE_DECODE_DST_IDP then
			dstIdp_n((to_integer(idpByteCounter_p)*dataWidth) + (dataWidth-1) downto to_integer(idpByteCounter_p)*dataWidth) <= downstreamData(dataWidth-1 downto 0);
		end if;
	end process nomem_dstIdp;
	
	srcIdp <= srcIdp_p;
	dstIdp <= dstIdp_p;
	latencyCritical <= latencyCritical_p;
	priority <= priority_p;
	data <= downstreamData(dataWidth-1 downto 0);
	startOfPacket <= '1' when state_p = STATE_START_PACKET_TRANSFER else '0';
	endOfPacket <= downstreamData(dataWidth);
	downstreamReadEnable <= readEnable when state_p = STATE_START_PACKET_TRANSFER or state_p = STATE_PACKET_TRANSFER else '1';
	dataValid <= not downstreamEmpty when state_p = STATE_START_PACKET_TRANSFER or state_p = STATE_PACKET_TRANSFER else '0';
	direction <= direction_p;
	
	-- priority
	priority_n <= priority when dataValid = '1'
				  else priority_p;
	
	--direction
	direction_n <= direction when dataValid = '1'
				   else direction_p;

	-- latency critical
	latencyCritical_n <= latencyCritical when dataValid = '1'
						 else latencyCritical_p;
						 
	
	-- src idp
	srcIdp_n <= srcIdp when dataValid = '1'
				else srcIdp_p;
	
	-- dst idp
	dstIdp_n <= dstIdp when dataValid = '1'
				else dstIdp_p;
	
	-- srcIdp
	nomem_srcIdp : process(state_p, srcIdp_p, downstreamData, idpByteCounter_p)
	begin
		srcIdp_n <= srcIdp_p;
		if state_p = STATE_DECODE_SRC_IDP then
			srcIdp_n((to_integer(idpByteCounter_p)*dataWidth) + (dataWidth-1) downto to_integer(idpByteCounter_p)*dataWidth) <= downstreamData(dataWidth-1 downto 0);
		end if;
	end process nomem_srcIdp;
	
	nomem_dstIdp : process(state_p, dstIdp_p, downstreamData, idpByteCounter_p)
	begin
		dstIdp_n <= dstIdp_p;
		if state_p = STATE_DECODE_DST_IDP then
			dstIdp_n((to_integer(idpByteCounter_p)*dataWidth) + (dataWidth-1) downto to_integer(idpByteCounter_p)*dataWidth) <= downstreamData(dataWidth-1 downto 0);
		end if;
	end process nomem_dstIdp;
	
	nomem_idpByteCounter : process(state_p, idpByteCounter_p, downstreamEmpty)
	begin
		idpByteCounter_n <= idpByteCounterMax;
		if state_p = STATE_DECODE_SRC_IDP or state_p = STATE_DECODE_DST_IDP then
			if downstreamEmpty = '0' and idpByteCounter_p /= 0 then
				idpByteCounter_n <= idpByteCounter_p - 1;
			end if;
		end if;
	end process nomem_idpByteCounter;

	nomem_nextState : process(state_p, dataValid)
	begin
		-- Default: keep current state
		state_n <= state_p;
		
		if dataValid = '1' and upstreamFull = '0' then
			case state_p is
				when STATE_IDLE =>
					state_n <= STATE_ENCODE_HEADER_1;
					
				when STATE_ENCODE_HEADER_1 =>
					state_n <= STATE_DECODE_HEADER_2;
					
				when STATE_ENCODE_HEADER_2 =>
						state_n <= STATE_ENCODE_SRC_IDP;
				
				when STATE_ENCODE_SRC_IDP =>
					if idpByteCounter_p = 0 then
						state_n <= STATE_ENCODE_DST_IDP;
					end if;
				
				when STATE_ENCODE_DST_IDP =>
					if idpByteCounter_p = 0 then
						state_n <= STATE_PACKET_TRANSFER;
					end if;
					
				when STATE_PACKET_TRANSFER =>
					if endOfPacket = '1' then
						state_n <= STATE_IDLE;
					end if;
			end case;
		end if;
		
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
		elsif rising_edge(clk) then
			state_p <= state_n;
			direction_p <= direction_n;
			priority_p <= priority_n;
			idpByteCounter_p <= idpByteCounter_n;
			latencyCritical_p <= latencyCritical_n;
			srcIdp_p <= srcIdp_n;
			dstIdp_p <= dstIdp_n;
		end if;
	end process mem_stateTransition;

end architecture rtl;
