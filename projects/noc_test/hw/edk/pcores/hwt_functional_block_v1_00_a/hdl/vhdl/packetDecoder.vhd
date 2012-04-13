library ieee;
use ieee.std_logic_1164.all;

library hwt_functional_block_v1_00_a;
use hwt_functional_block_v1_00_a.hwt_functional_block_pkg.all;

entity packetDecoder is
	port (
		clk 					: in  std_logic;
		reset 					: in  std_logic;
		
		-- Signals from the switch
		downstreamEmpty			: in  std_logic;
		downstreamData			: in  std_logic_vector(dataWidth-1 downto 0);
		downstreamReadEnable 	: out std_logic;
		
		-- Decoded values of the packet
		startOfPacket			: out std_logic; 									-- Indicates the start of a new packet
		endOfPacket				: out std_logic; 									-- Indicates the end of the packet
		data					: out std_logic_vector(dataWidth-1 downto 0); 		-- The current data byte
		dataValid				: out std_logic; 									-- '1' if the data are valid, '0' else
		direction				: out std_logic; 									-- '1' for egress, '0' for ingress
		priority				: out std_logic_vector(priorityWidth-1 downto 0); 	-- The priority of the packet
		latencyCritical			: out std_logic; 									-- '1' if this packet is latency critical
		srcIdp					: out std_logic_vector(idpWidth-1 downto 0); 		-- The source IDP
		dstIdp					: out std_logic_vector(idpWidth-1 downto 0); 		-- The destination IDP
		readEnable				: in  std_logic										-- Read enable for the functional block
	);
end entity packetDecoder;

architecture rtl of packetDecoder is
	
	type state_t is ( STATE_IDLE,
					STATE_DECODE_HEADER_1,
					STATE_DECODE_HEADER_2,
					STATE_DECODE_SRC_IDP,
					STATE_DECODE_DST_IDP,
					STATE_START_PACKET_TRANSFER,
					STATE_PACKET_TRANSFER );
	
	signal state_n, state_p						: state_t;
	signal direction_n, direction_p 			: std_logic;
	signal priority_n, priority_p 				: std_logic_vector(priorityWidth-1 downto 0);
	signal latencyCritical_n, latencyCritical_p	: std_logic;
	signal srcIdp_n, srcIdp_p					: std_logic_vector(idpWidth-1 downto 0);
	signal dstIdp_n, dstIdp_p					: std_logic_vector(idpWidth-1 downto 0);
	
begin

	

end architecture rtl;
