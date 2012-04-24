library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library ana_v1_00_a;
use ana_v1_00_a.anaPkg.all;

entity userLogic is
	generic(
		C_LOCAL_RAM_ADDRESS_WIDTH : integer
	);
	port(
		clk						: in  std_logic;
		reset					: in  std_logic;
		
		-- The local memory port
		localRAMReader_addr		: out std_logic_vector(C_LOCAL_RAM_ADDRESS_WIDTH-1 downto 0);
		localRAMReader_dout		: in  std_logic_vector(31 downto 0);
		
		-- The memory address up to which the data in the local RAM are valid
		localRAMValidPointer	: in  std_logic_vector(C_LOCAL_RAM_ADDRESS_WIDTH-1 downto 0);
		
		-- The upstream port
		upstreamWriteEnable		: out std_logic;
		upstreamData			: out std_logic_vector(dataWidth downto 0);
		upstreamFull 			: in  std_logic
	);
end userLogic;



architecture rtl of userLogic is

	type state_t is (STATE_IDLE,
				 	 STATE_READ_LENGTH,
			 		 STATE_PACKET_TRANSFER);
	signal state_n, state_p : state_t;
	
	-- The number of bytes still to be transmitted for the currently transmitted packet
	signal remainingPacketLength_n, remainingPacketLength_p : std_logic_vector(31 downto 0);
	
	-- The number of the currently transmitted byte in the currently transmitted word
	signal byteCounter_n, byteCounter_p : unsigned(1 downto 0);
	
	-- The address of the currently read word
	signal localRAMReadPointer_n, localRAMReadPointer_p : std_logic_vector(C_LOCAL_RAM_ADDRESS_WIDTH-1 downto 0);
	
	
	function incLocalRAMAddr(localRAMReadPointer_p: std_logic_vector(C_LOCAL_RAM_ADDRESS_WIDTH-1 downto 0)) return std_logic_vector is
		variable result : std_logic_vector(C_LOCAL_RAM_ADDRESS_WIDTH-1 downto 0);
	begin
		if localRAMReadPointer_p = (C_LOCAL_RAM_ADDRESS_WIDTH-1 downto 0 => '1') then
			result := (others => '0');
		else
			result := std_logic_vector(unsigned(localRAMReadPointer_p) + 1);
		end if;
		return result;
	end incLocalRAMAddr;
	
	
	function getByte(word: std_logic_vector(31 downto 0); byte: unsigned(1 downto 0)) return std_logic_vector is
		variable result : std_logic_vector(dataWidth-1 downto 0);
		variable a, b: integer;
	begin
		a := to_integer(byte)*dataWidth;
		b := a + dataWidth - 1;
		result(dataWidth-1 downto 0) := word(b downto a);
		return result;
	end getByte;

begin

	
	
	upstreamData(dataWidth-1 downto 0) <= getByte(localRAMReader_dout, byteCounter_p);
	upstreamData(dataWidth) <= '1' when remainingPacketLength_p = (31 downto 0 => '0') else '0';
	upstreamWriteEnable <= '1' when state_p = STATE_PACKET_TRANSFER else '0';
	localRAMReader_addr <= localRAMReadPointer_p;
	
	nomem_localRAMReadPointer:process(state_p, localRAMReadPointer_p, localRAMValidPointer, upstreamFull, byteCounter_p)
	begin
		localRAMReadPointer_n <= localRAMReadPointer_p;
		case state_p is
			when STATE_IDLE =>

			when STATE_READ_LENGTH =>
				localRAMReadPointer_n <= incLocalRAMAddr(localRAMReadPointer_p);
			
			when STATE_PACKET_TRANSFER =>
				if (byteCounter_p = 0 or remainingPacketLength_p = (31 downto 0 => '0')) and upstreamFull = '0' then
					localRAMReadPointer_n <= incLocalRAMAddr(localRAMReadPointer_p);
				end if;
		end case;
	end process nomem_localRAMReadPointer;	
	
	nomem_byteCounter: process(state_p, byteCounter_p, upstreamFull)
	begin
		byteCounter_n <= byteCounter_p;
		if state_p = STATE_PACKET_TRANSFER then
			if upstreamFull = '0' then
				byteCounter_n <= byteCounter_p - 1;
			end if;
		else
			byteCounter_n <= (1 downto 0 => '1');
		end if;
	end process nomem_byteCounter;
	
	nomem_remainingPacketLength: process(state_p, remainingPacketLength_p, localRAMReader_dout)
	begin
		remainingPacketLength_n <= remainingPacketLength_p;
		case state_p is
			when STATE_IDLE =>
				remainingPacketLength_n <= (others => '-');
				
			when STATE_READ_LENGTH =>
				remainingPacketLength_n <= localRAMReader_dout;
				
			when STATE_PACKET_TRANSFER =>
				if upstreamFull = '0' then
					remainingPacketLength_n <= std_logic_vector(unsigned(remainingPacketLength_p)-1);
				end if;
		end case;
	end process nomem_remainingPacketLength;
	
	nomem_nextState: process(state_p, localRAMValidPointer, localRAMReadPointer_p, remainingPacketLength_p)
	begin
		state_n <= state_p;
		case state_p is
			when STATE_IDLE =>
				if localRAMValidPointer /= localRAMReadPointer_p then
					state_n <= STATE_READ_LENGTH;
				end if;
				
			when STATE_READ_LENGTH =>
				state_n <= STATE_PACKET_TRANSFER;
				
			when STATE_PACKET_TRANSFER =>
				if remainingPacketLength_p = (31 downto 0 => '0') then
					state_n <= STATE_IDLE;
				end if;
		end case;
	end process nomem_nextState;
	
	mem_stateTransition: process(clk, reset)
	begin
		if reset = '1' then
			state_p <= STATE_IDLE;
			remainingPacketLength_p <= (others => '0');
			byteCounter_p <= (others => '1');
			localRAMReadPointer_p <= (others => '0');
		elsif rising_edge(clk) then
			state_p <= state_n;
			remainingPacketLength_p <= remainingPacketLength_n;
			byteCounter_p <= byteCounter_n;
			localRAMReadPointer_p <= localRAMReadPointer_n;
		end if;
	end process mem_stateTransition;

end architecture rtl;