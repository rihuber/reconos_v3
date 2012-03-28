library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library proc_common_v3_00_a;
use proc_common_v3_00_a.proc_common_pkg.all;

library reconos_v3_00_a;
use reconos_v3_00_a.reconos_pkg.all;

entity hwt_functional_block is
	generic(
		headerValue		: std_logic_vector(7 downto 0);
		resetWithToken	: std_logic
	);
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
		rst           : in std_logic;
		
		led 		: out std_logic;
		button		: in std_logic		
	);

end hwt_functional_block;

architecture implementation of hwt_functional_block is
	
	type STATE_TYPE is ( STATE_IDLE,
						 STATE_REPORT_TOKEN_RECEPTION,
						 STATE_REPORT_COMMAND_RECEPTION,
						 STATE_THREAD_EXIT );

	constant MBOX_SEND  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000000";
	constant C_REPORT_TOKEN_RECEPTION : std_logic_vector(31 downto 0) := x"00000000";
	constant C_REPORT_COMMAND_RECEPTION : std_logic_vector(31 downto 0) := x"00000001"; 

	signal state    : STATE_TYPE;
	signal i_osif	: i_osif_t;
	signal o_osif   : o_osif_t;
	signal i_memif  : i_memif_t;
	signal o_memif  : o_memif_t;	
	signal ignore   : std_logic_vector(C_FSL_WIDTH-1 downto 0);
	
	
	
	constant counterWidth : integer := 10;
	
	type state is (IDLE, RECEIVING_TOKEN, HOLDING_TOKEN, SENDING_TOKEN);
	signal state_p, state_n : state;
	signal counter_p, counter_n	: unsigned(counterWidth-1 downto 0);
	
	constant counterMaxValue : unsigned(counterWidth-1 downto 0) := (others => '1');
	constant counterMinValue : unsigned(counterWidth-1 downto 0) := (others => '0');
	
	signal dataValue_p, dataValue_n : std_logic_vector(7 downto 0);
	signal reportTokenReception, reportCommandReception : std_logic;
	
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
		elsif rising_edge(i_osif.clk) then
			case state is
				when STATE_IDLE =>
					if reportTokenReception then
						state <= STATE_REPORT_TOKEN_RECEPTION;
					elsif reportCommandReception then
						state <= STATE_REPORT_COMMAND_RECEPTION;
					end if;
					
				when STATE_REPORT_TOKEN_RECEPTION =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, C_REPORT_TOKEN_RECEPTION, ignore, done);
					if done then 
						state <= STATE_IDLE;
					end if;
					
				when STATE_REPORT_COMMAND_RECEPTION =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, C_REPORT_COMMAND_RECEPTION, ignore, done);
					if done then 
						state <= STATE_IDLE;
					end if;
					
				when STATE_THREAD_EXIT =>
					osif_thread_exit(i_osif,o_osif);
			
			end case;
		end if;
	end process;
	
	
	nomem_output : process (state_p, counter_p, dataValue_p)
	begin
		led  <= '0';
		downstreamReadEnable <= '0';
		upstreamWriteEnable <= '0';
		upstreamData <= (others => '-');
		
		if state_p = RECEIVING_TOKEN then
				downstreamReadEnable <= '1';
		elsif state_p = HOLDING_TOKEN then
				led <= '1';
		elsif state_p = SENDING_TOKEN then 
			upstreamWriteEnable <= '1';
			if counter_p = counterMaxValue then
				upstreamData(7 downto 0) <= headerValue;
			else
				upstreamData(7 downto 0) <= dataValue_p;
			end if;
			if counter_p = counterMinValue then
				upstreamData(8) <= '1';
			else
				upstreamData(8) <= '0';
			end if;
		end if;
		
	end process nomem_output;

	nomem_nextState : process (state_p, counter_p, downstreamData, downstreamEmpty, button, upstreamFull, dataValue_p)
		--variable controlBitVar: std_logic := '0';
	begin
		state_n <= state_p;
		counter_n <= counter_p;
		dataValue_n <= dataValue_p;
		reportTokenReception <= '0';
		reportCommandReception <= '0';
		
		case state_p is
			when IDLE =>
				if downstreamEmpty = '0' then
					state_n <= RECEIVING_TOKEN;
				end if;
			when RECEIVING_TOKEN =>
				if downstreamEmpty = '0' then
					dataValue_n <= downstreamData(7 downto 0);
					if downstreamData(8) = '1' then
						state_n <= HOLDING_TOKEN;
						reportTokenReception <= '1';
					end if;
				end if;
			when HOLDING_TOKEN =>
				if button = '1' then
					state_n <= SENDING_TOKEN;
					reportCommandReception <= '1';
				end if;
			when SENDING_TOKEN =>
				if upstreamFull = '0' then
					if counter_p = counterMinValue then
						state_n <= idle;
						counter_n <= (others => '1');
					else
						counter_n <= counter_p - 1;
					end if;
				end if;
		end case;
	end process nomem_nextState;

	mem_stateTransition : process (rst, clk)
	begin
		if rst = '0' then
			counter_p <= (others => '1');
			dataValue_p <= "01010101";
			if resetWithToken then
				state_p <= HOLDING_TOKEN;
			else
				state_p <= IDLE;
			end if;
		elsif rising_edge(clk) then
			state_p <= state_n;
			counter_p <= counter_n;
			dataValue_p <= dataValue_n;
		end if;
	end process mem_stateTransition;

	
end architecture;




