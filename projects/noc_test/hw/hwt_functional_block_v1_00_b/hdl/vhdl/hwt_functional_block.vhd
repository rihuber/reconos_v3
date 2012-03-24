library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library proc_common_v3_00_a;
use proc_common_v3_00_a.proc_common_pkg.all;

library reconos_v3_00_a;
use reconos_v3_00_a.reconos_pkg.all;

entity hwt_functional_block is
	port (
		-- OSIF FSL
		OSFSL_Clk       : in  std_logic;                 -- Synchronous clock
		OSFSL_Rst       : in  std_logic;
		OSFSL_S_Clk     : out std_logic;                 -- Slave asynchronous clock
		OSFSL_S_Read    : out std_logic;                 -- Read signal, requiring next available input to be read
		OSFSL_S_Data    : in  std_logic_vector(0 to 31); -- Input data
		OSFSL_S_Control : in  std_logic;                 -- Control Bit, indicating the input data are control word
		OSFSL_S_Exists  : in  std_logic;                 -- Data Exist Bit, indicating data exist in the input FSL bus
		OSFSL_M_Clk     : out std_logic;                 -- Master asynchronous clock
		OSFSL_M_Write   : out std_logic;                 -- Write signal, enabling writing to output FSL bus
		OSFSL_M_Data    : out std_logic_vector(0 to 31); -- Output data
		OSFSL_M_Control : out std_logic;                 -- Control Bit, indicating the output data are contol word
		OSFSL_M_Full    : in  std_logic;                 -- Full Bit, indicating output FSL bus is full
		
		-- FIFO Interface
		FIFO32_S_Clk : out std_logic;
		FIFO32_M_Clk : out std_logic;
		FIFO32_S_Data : in std_logic_vector(31 downto 0);
		FIFO32_M_Data : out std_logic_vector(31 downto 0);
		FIFO32_S_Fill : in std_logic_vector(15 downto 0);
		FIFO32_M_Rem : in std_logic_vector(15 downto 0);
		FIFO32_S_Rd : out std_logic;
		FIFO32_M_Wr : out std_logic;

		-- NoC interface
		downstreamReadEnable	: out std_logic;
		downstreamEmpty  	: in std_logic;
		downstreamData		: in std_logic_vector(8 downto 0);
		upstreamWriteEnable	: out std_logic;
		upstreamData		: out std_logic_vector(8 downto 0);
		upstreamFull 		: in std_logic;
		
		-- HWT reset
		rst           : in std_logic
	);

end hwt_functional_block;

architecture implementation of hwt_functional_block is
	
	type STATE_TYPE is ( STATE_GET,
			     		 STATE_SEND_PACKETS,
			     		 STATE_WAIT_FOR_PACKET,
			     		 STATE_PUT,
			     		 STATE_THREAD_EXIT );
			     
	type RECEIVE_STATE_TYPE is ( STATE_WAIT_FOR_FIFO,
								 STATE_DELIVER_PACKET,
								 STATE_IDLE );

	constant MBOX_RECV  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000000";
	constant MBOX_SEND  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000001";

	signal command     : std_logic_vector(31 downto 0);
	signal state    : STATE_TYPE;
	signal i_osif	: i_osif_t;
	signal o_osif   : o_osif_t;
	signal i_memif  : i_memif_t;
	signal o_memif  : o_memif_t;
	
	signal ignore   : std_logic_vector(C_FSL_WIDTH-1 downto 0);

	signal sendPackets : std_logic;
	signal receivePacket : std_logic;
	signal receivePacket_done : std_logic;
	signal receivePacket_done_n : std_logic;
	signal counter : std_logic_vector(31 downto 0);
	signal counter_n : std_logic_vector(31 downto 0);
	
	signal receiveState : RECEIVE_STATE_TYPE;
	signal receiveState_n : RECEIVE_STATE_TYPE;
	signal receivedCounter : std_logic_vector(31 downto 0);
	signal receivedCounter_n : std_logic_vector(31 downto 0);
	
	signal upstreamData_n : std_logic_vector(8 downto 0);
	signal upstreamWriteEnable_n : std_logic;

begin
	
  	fsl_setup(
		i_osif,
		o_osif,
		OSFSL_Clk,
		OSFSL_Rst,
		OSFSL_S_Data,
		OSFSL_S_Exists,
		OSFSL_M_Full,
		OSFSL_M_Data,
		OSFSL_S_Read,
		OSFSL_M_Write,
		OSFSL_M_Control
	);
		
	memif_setup(
		i_memif,
		o_memif,
		OSFSL_Clk,
		FIFO32_S_Clk,
		FIFO32_S_Data,
		FIFO32_S_Fill,
		FIFO32_S_Rd,
		FIFO32_M_Clk,
		FIFO32_M_Data,
		FIFO32_M_Rem,
		FIFO32_M_Wr
	);
	
    
	-- os and memory synchronisation state machine
	reconos_fsm: process (i_osif.clk,rst,o_osif,o_memif) is
		variable done  : boolean;
	begin
		if rst = '1' then
			osif_reset(o_osif);
			memif_reset(o_memif);
			state <= STATE_GET;
			sendPackets <= '0';
			receivePacket <= '0';
		elsif rising_edge(i_osif.clk) then
			sendPackets <= '0';
			receivePacket <= '0';
			case state is
				when STATE_GET =>
					osif_mbox_get(i_osif, o_osif, MBOX_RECV, command, done);
					if done then
						if command = X"FFFFFFFF" then
							state <= STATE_THREAD_EXIT;
						elsif command = X"00000001" then
							state <= STATE_SEND_PACKETS;
						else
							state <= STATE_WAIT_FOR_PACKET;
						end if;
					end if;

				when STATE_SEND_PACKETS =>
					sendPackets <= '1';
								
				when STATE_WAIT_FOR_PACKET =>
					receivePacket <= '1';
					if receivePacket_done = '1' then
						state <= STATE_PUT;
					end if;
				
				when STATE_PUT =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, receivedCounter, ignore, done);
					if done then 
						state <= STATE_WAIT_FOR_PACKET; 
					end if;

				when STATE_THREAD_EXIT =>
					osif_thread_exit(i_osif,o_osif);
			
			end case;
		end if;
	end process;
	
	
	
	mem_sending : process(i_osif.clk,rst)
	begin
		if rst = '1' then 
			counter <= (others => '0');
			upstreamData <= (others => '0');
			upstreamWriteEnable <= '0';
		elsif rising_edge(i_osif.clk) then
			upstreamData <= upstreamData_n;
			upstreamWriteEnable <= upstreamWriteEnable_n;
			counter <= counter_n;
		end if;
	end process;
	
	nomem_sendign : process(counter, sendPackets, upstreamFull) 
	begin
		upstreamData_n <= counter(8 downto 0);
		upstreamWriteEnable_n <= '0';
		counter_n <= counter;
		if sendPackets = '1' and upstreamFull = '0' then
			upstreamWriteEnable_n <= '1';
			counter_n <= counter + 1;
		end if;
	end process;
	
	
	
	mem_receiving : process(i_osif.clk,rst)
	begin
		if rst = '1' then 
			receiveState <= STATE_IDLE;
			receivePacket_done <= '0';
			receivedCounter	<= (others =>'0');
		elsif rising_edge(i_osif.clk) then
			receiveState <= receiveState_n;
			receivePacket_done <= receivePacket_done_n;
			receivedCounter <= receivedCounter_n;
		end if;
	end process;
	
	nomem_receiving : process(receivedCounter, receiveState, receivePacket, downstreamEmpty, downstreamData)
	begin
		receivedCounter_n <= receivedCounter;
		receiveState_n <= receiveState;
		downstreamReadEnable <= '0';
		receivePacket_done_n <= '0';
		case receiveState is
			when STATE_IDLE =>
				if receivePacket = '1' then
					receiveState_n <= STATE_WAIT_FOR_FIFO;				
				end if;
			
			when STATE_WAIT_FOR_FIFO =>
				if downstreamEmpty = '0' then
					receivedCounter_n(8 downto 0) <= downstreamData;
					downstreamReadEnable <= '1';
					receiveState_n <= STATE_DELIVER_PACKET;
				end if;
			
			when STATE_DELIVER_PACKET =>
				receivePacket_done_n <= '1';
				if receivePacket = '0' then
					receiveState_n <= STATE_IDLE;
				end if;
			
		end case;
	end process;

	
end architecture;




