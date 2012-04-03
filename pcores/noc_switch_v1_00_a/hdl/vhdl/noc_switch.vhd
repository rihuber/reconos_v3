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
	
	-----------------------------------------------------------------
	-- INPUT BUFFER FROM FUNCTIONAL BLOCK
	-----------------------------------------------------------------
	
	fifo_upstream0 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => clk125,
			wr_clk => upstream0WriteClock,
			din => upstream0Data,
			wr_en => upstream0WriteEnable,
			rd_en => swInputLinksOut(0).readEnable,
			dout => swInputLinksIn(0).data,
			full => upstream0Full,
			empty => swInputLinksIn(0).empty
		);
	
	fifo_upstream1 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => clk125,
			wr_clk => upstream1WriteClock,
			din => upstream1Data,
			wr_en => upstream1WriteEnable,
			rd_en => swInputLinksOut(1).readEnable,
			dout => swInputLinksIn(1).data,
			full => upstream1Full,
			empty => swInputLinksIn(1).empty
		);
		
	-----------------------------------------------------------------
	-- UNBUFFERED INPUT FROM RING
	-----------------------------------------------------------------
	
	unbufferedInputFromRing : for i in 0 to numExtPorts-1 generate
		swInputLinksIn(i+numIntPorts).data <= ringInputData(((dataWidth+1)*(i+1))-1 downto (dataWidth+1)*i);
		swInputLinksIn(i+numIntPorts).empty <= ringInputEmpty(i);
		ringInputReadEnable(i) <= swInputLinksOut(i+numIntPorts).readEnable;
	end generate;
		
	-----------------------------------------------------------------
	-- OUTPUT BUFFER TO FUNCTIONAL BLOCK
	-----------------------------------------------------------------
		
	fifo_downstream0 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => downstream0ReadClock,
			wr_clk => clk125,
			din => swOutputLinksOut(0).data,
			wr_en => swOutputLinksOut(0).writeEnable,
			rd_en => downstream0ReadEnable,
			dout => downstream0Data,
			full => swOutputLinksIn(0).full,
			empty => downstream0Empty
		);
	
	fifo_downstream1 : fbSwitchFifo
		port map (
			rst => reset,
			rd_clk => downstream1ReadClock,
			wr_clk => clk125,
			din => swOutputLinksOut(1).data,
			wr_en => swOutputLinksOut(1).writeEnable,
			rd_en => downstream1ReadEnable,
			dout => downstream1Data,
			full => swOutputLinksIn(1).full,
			empty => downstream1Empty
		);
		
	-----------------------------------------------------------------
	-- OUTPUT BUFFER TO RING
	-----------------------------------------------------------------
	
	outputBufferToRing : for i in 0 to numExtPorts-1 generate
		fifo_ring : fbSwitchFifo
			port map (
				rst => reset,
				rd_clk => clk125,
				wr_clk => clk125,
				din => swOutputLinksOut(i+numIntPorts).data,
				wr_en => swOutputLinksOut(i+numIntPorts).writeEnable,
				rd_en => ringOutputReadEnable(i),
				dout => ringOutputData(((dataWidth+1)*(i+1))-1 downto (dataWidth+1)*i),
				full => swOutputLinksIn(i+numIntPorts).full,
				empty => ringOutputEmpty(i)
			);
	end generate;
		
	-----------------------------------------------------------------
	-- SIMPLE SWITCH REPLACEMENT
	-----------------------------------------------------------------
	
	-- Downstream 0 (input from ring line 0)
	swOutputLinksOut(0).data <= swInputLinksIn(2).data;
	swOutputLinksOut(0).writeEnable <= not swInputLinksIn(2).empty;
	swInputLinksOut(2).readEnable <= not swOutputLinksIn(0).full;
	
	-- Downstream 1 (input from upstream 0)
	swOutputLinksOut(1).data <= swInputLinksIn(0).data;
	swOutputLinksOut(1).writeEnable <= not swInputLinksIn(0).empty;
	swInputLinksOut(0).readEnable <= not swOutputLinksIn(1).full;
	
	-- Ring output line 0 (input from upstream 1)
	swOutputLinksOut(2).data <= swInputLinksIn(1).data;
	swOutputLinksOut(2).writeEnable <= not swInputLinksIn(1).empty;
	swInputLinksOut(1).readEnable <= not swOutputLinksIn(2).full;
	
end architecture rtl;
