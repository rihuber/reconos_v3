library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
		downstreamReadClock	: out std_logic;
		upstreamWriteEnable	: out std_logic;
		upstreamData		: out std_logic_vector(8 downto 0);
		upstreamFull 		: in std_logic;
		upstreamWriteClock : out std_logic;
		
		-- HWT reset
		rst           : in std_logic
	);

end hwt_functional_block;

architecture implementation of hwt_functional_block is
	
	type STATE_TYPE is ( STATE_GET,
			     		 STATE_WRITE_DATA,
			     		 STATE_READ_DATA,
			     		 STATE_PUT,
			     		 STATE_THREAD_EXIT );
			     
	type RECEIVE_STATE_TYPE is ( STATE_WAIT_FOR_FIFO,
								 STATE_DELIVER_PACKET,
								 STATE_IDLE );

	constant MBOX_RECV  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000000";
	constant MBOX_SEND  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000001";

	signal data     : std_logic_vector(31 downto 0);
	signal data_ret : std_logic_vector(31 downto 0);
	signal state    : STATE_TYPE;
	signal i_osif	: i_osif_t;
	signal o_osif   : o_osif_t;
	signal i_memif  : i_memif_t;
	signal o_memif  : o_memif_t;	
	signal ignore   : std_logic_vector(C_FSL_WIDTH-1 downto 0);
	
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
	
	downstreamReadClock <= i_osif.clk;
	upstreamWriteClock <= i_osif.clk;
    
	-- os and memory synchronisation state machine
	reconos_fsm: process (i_osif.clk,rst,o_osif,o_memif) is
		variable done  : boolean;
	begin
		if rst = '1' then
			osif_reset(o_osif);
			memif_reset(o_memif);
			state <= STATE_GET;
			upstreamWriteEnable <= '0';
			downstreamReadEnable <= '0';
			data_ret <= (others => '0');
		elsif rising_edge(i_osif.clk) then
			upstreamWriteEnable <= '0';
			downstreamReadEnable <= '0';
			case state is
				when STATE_GET =>
					osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
					if done then
						if data = X"FFFFFFFF" then
							state <= STATE_THREAD_EXIT;
						else
							state <= STATE_WRITE_DATA;
						end if;
					end if;

				when STATE_WRITE_DATA =>
					if upstreamFull = '0' then
						upstreamWriteEnable <= '1';
						upstreamData <= data(8 downto 0);
						state <= STATE_READ_DATA;
					end if;
					
				when STATE_READ_DATA =>
					if downstreamEmpty = '0' then
						downstreamReadEnable <= '1';
						data_ret(8 downto 0) <= downstreamData;
						state <= STATE_PUT;
					end if;
				
				when STATE_PUT =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, data_ret, ignore, done);
					if done then 
						state <= STATE_GET; 
					end if;

				when STATE_THREAD_EXIT =>
					osif_thread_exit(i_osif,o_osif);
			
			end case;
		end if;
	end process;

	
end architecture;




