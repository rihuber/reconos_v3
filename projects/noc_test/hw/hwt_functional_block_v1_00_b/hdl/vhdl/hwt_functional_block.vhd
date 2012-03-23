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
		upstreamFull 		: in std_logic
		
		-- HWT reset
		rst           : in std_logic
	);

end hwt_functional_block;

architecture implementation of hwt_functional_block is
	
	type STATE_TYPE is ( STATE_WAIT_FOR_DATA,
			     STATE_WAIT_FOR_REPLY,
			     STATE_RETURN_DATA,
			     STATE_THREAD_EXIT );

	constant MBOX_RECV  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000000";
	constant MBOX_SEND  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000001";

	signal data     : std_logic_vector(31 downto 0);
	signal replied_data : std_logic_vector(31 downto 0);
	signal state    : STATE_TYPE;
	signal i_osif   : i_osif_t;
	signal o_osif   : o_osif_t;
	signal i_memif  : i_memif_t;
	signal o_memif  : o_memif_t;
	
	signal ignore   : std_logic_vector(C_FSL_WIDTH-1 downto 0);

	signal send_data : std_logic;
	signal data_sent : std_logic;
	signal received_reply : std_logic;

	signal upstreamData_n : std_logic_vector(8 downto 0);
	signal upstreamWriteEnable_n : std_logic;
	signal received_reply_n : std_logic;
	signal replied_data_n : std_logic_vector(31 downto 0);

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
			send_data <= '0';
		elsif rising_edge(i_osif.clk) then
			send_data <= '0';
			case state is
				when STATE_WAIT_FOR_DATA =>
					osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
					if done then
						if (data = X"FFFFFFFF") then
							state <= STATE_THREAD_EXIT;
						else
							send_data <= '1';
							state <= STATE_WAIT_FOR_REPLY;
						end if;
					end if;

				when STATE_WAIT_FOR_REPLY =>
					if received_reply = '1' then
						state <= STATE_RETURN_DATA;
					end if;
								
				when STATE_RETURN_DATA =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, replied_data, ignore, done);
					if done then 
						state <= STATE_WAIT_FOR_DATA; 
					end if;

				when STATE_THREAD_EXIT =>
					osif_thread_exit(i_osif,o_osif);
			
			end case;
		end if;
	end process;
	
	nomem_fifo : process(send_data, downstreamEmpty, state)
	begin
		upstreamData_n <= (others => '1');
		upstreamWriteEnable_n <= '0';
		received_reply_n <= '0';
		replied_data_n <= replied_data;
		if send_data = '1' then
			upstreamData_n <= data(8 downto 0);
			upstreamWriteEnable_n <= '1';
		elsif downstreamEmpty = '0' then
			if state /= STATE_WAIT_FOR_REPLY then
				upstreamData_n <= downstreamData;
				upstreamWriteEnable_n <= '1';
			else
				replied_data_n(8 downto 0) <= downstreamData;
				received_reply_n <= '1';
			end if;
		end if;
	end process;

	mem_fifo : process(i_osif.clk,rst)
	begin
		if rst = '1' then 
			upstreamData <= (others => '1');
			upstreamWriteEnable <= '0';
			received_reply <= '0';
			replied_data <= (others => '0');
		elsif rising_edge(i_osif.clk) then
			upstreamData <= upstreamData_n;
			upstreamWriteEnable_n <= upstreamWriteEnable_n;
			received_reply <= received_reply_n;
			replied_data <= replied_data_n;
		end if;received_reply_n <= '1';
	end process;

	
end architecture;



