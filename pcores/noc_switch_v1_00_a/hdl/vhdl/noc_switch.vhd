library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.switchPkg.all;
use noc_switch_v1_00_a.headerPkg.all;

entity noc_switch is
	generic (
		globalAddr : std_logic_vector(4 downto 0) := (others => '0')
	);
  	port (
  		clk125					: in  std_logic;
		reset					: in  std_logic;

		downstream0ReadEnable	: in  std_logic;
		downstream0Empty  		: out std_logic;
		downstream0Data			: out std_logic_vector(dataWidth downto 0);
		downstream0ReadClock 	: in  std_logic;

		downstream1ReadEnable	: in  std_logic;
		downstream1Empty  		: out std_logic;
		downstream1Data			: out std_logic_vector(dataWidth downto 0);
		downstream1ReadClock 	: in  std_logic;

		upstream0WriteEnable	: in  std_logic;
		upstream0Data			: in  std_logic_vector(dataWidth downto 0);
		upstream0Full 			: out std_logic;
		upstream0WriteClock 	: in  std_logic;

		upstream1WriteEnable	: in  std_logic;
		upstream1Data			: in  std_logic_vector(dataWidth downto 0);
		upstream1Full 			: out std_logic;
		upstream1WriteClock 	: in  std_logic;
		
		ringInputEmpty			: in std_logic_vector(numExtPorts-1 downto 0);
		ringInputData			: in std_logic_vector((numExtPorts*(dataWidth+1))-1 downto 0);
		ringInputReadEnable		: out std_logic_vector(numExtPorts-1 downto 0);
		ringOutputReadEnable	: in std_logic_vector(numExtPorts-1 downto 0);
		ringOutputData			: out std_logic_vector((numExtPorts*(dataWidth+1))-1 downto 0);
		ringOutputEmpty			: out std_logic_vector(numExtPorts-1 downto 0)
		
--		ringInputIn				: in  inputLinkInArray(numExtPorts-1 downto 0);
--		ringInputOut			: out inputLinkOutArray(numExtPorts-1 downto 0);

		--ringOutputIn			: in  inputLinkOutArray(numExtPorts-1 downto 0);
		--ringOutputOut			: out inputLinkInArray(numExtPorts-1 downto 0)
  	);
end noc_switch;



architecture rtl of noc_switch is

	signal swInputLinksIn	: inputLinkInArray(numPorts-1 downto 0);
	signal swInputLinksOut	: inputLinkOutArray(numPorts-1 downto 0);
	signal swOutputLinksIn	: outputLinkInArray(numPorts-1 downto 0);
	signal swOutputLinksOut	: outputLinkOutArray(numPorts-1 downto 0);
	
	signal outputBufferOut	: inputLinkInArray(numPorts-1 downto 0);
	signal outputBufferIn	: inputLinkOutArray(numPorts-1 downto 0);
	
	signal loc_upstream0ReadEnable : std_logic;
	signal loc_upstream0Data : std_logic_vector(8 downto 0);
	signal loc_upstream0Empty : std_logic;
	signal loc_upstream1ReadEnable : std_logic;
	signal loc_upstream1Data : std_logic_vector(8 downto 0);
	signal loc_upstream1Empty : std_logic;
	signal loc_downstream0WriteEnable : std_logic;
	signal loc_downstream0Full : std_logic;
	signal loc_downstream0Data: std_logic_vector(8 downto 0);
	signal loc_downstream1WriteEnable : std_logic;
	signal loc_downstream1Full : std_logic;
	signal loc_downstream1Data : std_logic_vector(8 downto 0);
	signal loc_ringDataIn : std_logic_vector(8 downto 0);
	signal loc_ringDataOut : std_logic_vector(8 downto 0);
	signal loc_ringWriteEnable : std_logic;
	signal loc_ringReadEnable : std_logic;
	signal loc_ringEmpty : std_logic;
	signal loc_ringFull : std_logic;
	
	                   
	component fbSwitchFifo
		port (
		rst: IN std_logic;
		rd_clk: IN std_logic;
		wr_clk: IN std_logic;
		din: IN std_logic_VECTOR(8 downto 0);
		wr_en: IN std_logic;
		rd_en: IN std_logic;
		dout: OUT std_logic_VECTOR(8 downto 0);
		full: OUT std_logic;
		empty: OUT std_logic
	);
	end component;
	
	
begin
	
	loc_upstream0ReadEnable <= not loc_downstream1Full;
	loc_upstream1ReadEnable <= not loc_ringFull;
	loc_downstream0WriteEnable <= not ringInputEmpty(0);
	loc_downstream0Data <= ringInputData(8 downto 0);
	loc_downstream1WriteEnable <= not loc_upstream0Empty;
	loc_downstream1Data <= loc_upstream0Data;
	loc_ringDataIn <= loc_upstream1Data;
	loc_ringWriteEnable <= not loc_upstream1Empty;
	loc_ringReadEnable <= ringOutputReadEnable(0);
	
	ringOutputData(8 downto 0) <= loc_ringDataOut;
	ringOutputEmpty(0) <= loc_ringEmpty;
	ringInputReadEnable(0) <= not loc_downstream0Full;
	
	-----------------------------------------------------------------
	-- INPUT FROM FUNCTIONAL BLOCK
	-----------------------------------------------------------------
	
	fifo_upstream0 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => clk125,
			wr_clk => upstream0WriteClock,
			din => upstream0Data,
			wr_en => upstream0WriteEnable,
			rd_en => loc_upstream0ReadEnable,
			dout => loc_upstream0Data,
			full => upstream0Full,
			empty => loc_upstream0Empty
		);
	
	fifo_upstream1 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => clk125,
			wr_clk => upstream1WriteClock,
			din => upstream1Data,
			wr_en => upstream1WriteEnable,
			rd_en => loc_upstream1ReadEnable,
			dout => loc_upstream1Data,
			full => upstream1Full,
			empty => loc_upstream1Empty
		);
		
	fifo_downstream0 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => downstream0ReadClock,
			wr_clk => clk125,
			din => loc_downstream0Data,
			wr_en => loc_downstream0WriteEnable,
			rd_en => downstream0ReadEnable,
			dout => downstream0Data,
			full => loc_downstream0Full,
			empty => downstream0Empty
		);
	
	fifo_downstream1 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => downstream1ReadClock,
			wr_clk => clk125,
			din => loc_downstream1Data,
			wr_en => loc_downstream1WriteEnable,
			rd_en => downstream1ReadEnable,
			dout => downstream1Data,
			full => loc_downstream1Full,
			empty => downstream1Empty
		);
		
	fifo_ring : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => clk125,
			wr_clk => clk125,
			din => loc_ringDataIn,
			wr_en => loc_ringWriteEnable,
			rd_en => loc_ringReadEnable,
			dout => loc_ringDataOut,
			full => loc_ringFull,
			empty => loc_ringEmpty
		);

		
	
	
end architecture rtl;
