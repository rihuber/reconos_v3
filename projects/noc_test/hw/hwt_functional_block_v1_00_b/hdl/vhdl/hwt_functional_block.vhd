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
		
		led 		: out std_logic
	);

end hwt_functional_block;

architecture implementation of hwt_functional_block is
	
	type STATE_TYPE is ( STATE_WAIT_FOR_TOKEN,
						 STATE_REPORT_TOKEN_RECEPTION, 
						 STATE_WAIT_FOR_COMMAND,
						 STATE_SEND_TOKEN,
						 STATE_REPORT_TOKEN_SENT	);

	constant MBOX_RECV  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000000";
	constant MBOX_SEND  : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000001";
	
	constant C_REPORT_TOKEN_RECEPTION : std_logic_vector(31 downto 0) := x"00000000";
	constant C_REPORT_COMMAND_RECEPTION : std_logic_vector(31 downto 0) := x"00000001"; 

	signal state    : STATE_TYPE;
	signal i_osif	: i_osif_t;
	signal o_osif   : o_osif_t;
	signal i_memif  : i_memif_t;
	signal o_memif  : o_memif_t;	
	signal ignore   : std_logic_vector(C_FSL_WIDTH-1 downto 0);
	signal reportTokenReception : std_logic;
	signal tokenSent : std_logic;
	
	
	constant counterWidth : integer := 2;
	
	type token_state is (IDLE, RECEIVING_TOKEN, HOLDING_TOKEN, SENDING_TOKEN);
	signal state_p, state_n : token_state;
	signal counter_p, counter_n	: unsigned(counterWidth-1 downto 0);
	
	constant counterMaxValue : unsigned(counterWidth-1 downto 0) := (others => '1');
	constant counterMinValue : unsigned(counterWidth-1 downto 0) := (others => '0');
	
	signal header_p, header_n : std_logic_vector(31 downto 0);
	
	signal dataValue_p, dataValue_n : std_logic_vector(7 downto 0);
	signal reportCommandReception : std_logic;
	signal button : std_logic;
	
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
	
	led <= '1' when state=STATE_WAIT_FOR_COMMAND
				else '0';
    
	-- os and memory synchronisation state machine
	reconos_fsm: process (i_osif.clk,rst,o_osif,o_memif) is
		variable done  : boolean;
	begin
		if rst = '1' then
			osif_reset(o_osif);
			memif_reset(o_memif);
			if resetWithToken = '1' then
				state <= STATE_WAIT_FOR_COMMAND;
			else
				state <= STATE_WAIT_FOR_TOKEN;
			end if;
		elsif rising_edge(i_osif.clk) then
			case state is
				when STATE_WAIT_FOR_TOKEN =>
					if reportTokenReception = '1' then
						state <= STATE_REPORT_TOKEN_RECEPTION;
					end if;
				
				when STATE_REPORT_TOKEN_RECEPTION =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, C_REPORT_TOKEN_RECEPTION, ignore, done);
					if done then 
						state <= STATE_WAIT_FOR_COMMAND;
					end if;
					
				when STATE_WAIT_FOR_COMMAND =>
					osif_mbox_get(i_osif, o_osif, MBOX_RECV, header_n, done);
					if done then
						header_p <= header_n;
						state <= STATE_SEND_TOKEN;
					end if;
					
				when STATE_SEND_TOKEN =>
					if tokenSent = '1' then
						state <= STATE_REPORT_TOKEN_SENT;
					end if;
					
				when STATE_REPORT_TOKEN_SENT =>
					osif_mbox_put(i_osif, o_osif, MBOX_SEND, C_REPORT_TOKEN_RECEPTION, ignore, done);
					if done then 
						state <= STATE_WAIT_FOR_TOKEN;
					end if;
					
			end case;
		end if;
	end process;
	
	
	nomem_receiving_token : process(state, downstreamEmpty, downstreamData)
	begin
		downstreamReadEnable <= '0';
		reportTokenReception <= '0';
		if state = STATE_WAIT_FOR_TOKEN then
			if downstreamEmpty = '0' then
				downstreamReadEnable <= '1';
				if downstreamData(8) = '1' then
					reportTokenReception <= '1';
				end if;
			end if;
		end if;
	end process;
	
	upstreamData(7 downto 0) 	<= header_p(7 downto 0);
	upstreamData(8) 			<= '1' when counter_p = counterMinValue 	else '0';
	upstreamWriteEnable 		<= '1' when state = STATE_SEND_TOKEN 		else '0';
	
	
	nomem_sending_counter : process(state, upstreamFull)
	begin
		counter_n <= counter_p;
		tokenSent <= '0';
		if state = STATE_SEND_TOKEN then
			if upstreamFull = '0' then
				if counter_p = counterMinValue then
					tokenSent <= '1';
				else
					counter_n <= counter_p - 1;
				end if;
			end if;
		else
			counter_n <= counterMaxValue;
		end if;
	end process;
	
	
	mem_counter_transition : process(i_osif.clk,rst)
	begin
		if rst = '1' then
			counter_p <= counterMaxValue;
		elsif rising_edge(i_osif.clk) then
			counter_p <= counter_n;
		end if;
	end process;
	
end architecture;




