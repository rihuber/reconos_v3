library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.switchPkg.all;
use noc_switch_v1_00_a.headerPkg.all;

entity noc_switch is
	generic (
		globalAddr : integer
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
		
		ringInputIn				: in  inputLinkInArray(numExtPorts-1 downto 0);
		ringInputOut			: out inputLinkOutArray(numExtPorts-1 downto 0);

		ringOutputIn			: in  inputLinkOutArray(numExtPorts-1 downto 0);
		ringOutputOut			: out inputLinkInArray(numExtPorts-1 downto 0)
  	);
end noc_switch;



architecture rtl of noc_switch is

	signal swInputLinksIn	: inputLinkInArray(numPorts-1 downto 0);
	signal swInputLinksOut	: inputLinkOutArray(numPorts-1 downto 0);
	signal swOutputLinksIn	: outputLinkInArray(numPorts-1 downto 0);
	signal swOutputLinksOut	: outputLinkOutArray(numPorts-1 downto 0);
	
	signal outputBufferOut	: inputLinkInArray(numPorts-1 downto 0);
	signal outputBufferIn	: inputLinkOutArray(numPorts-1 downto 0);
	
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
	
	component interSwitchFifo
		port (
		rst: IN std_logic;
		clk: IN std_logic;
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
	-- UPSTREAM FROM FUNCTIONAL BLOCK
	-----------------------------------------------------------------
	
	swInputLinksIn(numPorts-1 downto numIntPorts) <= ringInputIn;
	ringInputOut <= swInputLinksOut(numPorts-1 downto numIntPorts);

	
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
	-- SWITCH
	-----------------------------------------------------------------
	
	sw : entity noc_switch_v1_00_a.switch
		generic map(
			globalAddress => globalAddr
		)
		port map(
			clk		=> clk125,
			reset		=> reset,
			inputLinksIn	=> swInputLinksIn,
			inputLinksOut	=> swInputLinksOut,
			outputLinksIn	=> swOutputLinksIn,
			outputLinksOut	=> swOutputLinksOut
		);
		
		
	-----------------------------------------------------------------
	-- OUTPUT BUFFER
	-----------------------------------------------------------------
	
	generate_output_buffer_fifo: for i in numIntPorts to numPorts-1 generate	
		outputBufferFifo : interSwitchFifo
			port map (
				clk => clk125,
				rst => reset,
				din => swOutputLinksOut(i).data,
				wr_en => swOutputLinksOut(i).writeEnable,
				rd_en => outputBufferIn(i).readEnable,
				dout => outputBufferOut(i).data,
				full => swOutputLinksIn(i).full,
				empty => outputBufferOut(i).empty
			);
	end generate generate_output_buffer_fifo;
	
	downstream0BufferFifo : fbSwitchFifo
			port map (
				rd_clk => downstream0ReadClock,
				wr_clk => clk125,
				rst => reset,
				din => swOutputLinksOut(0).data,
				wr_en => swOutputLinksOut(0).writeEnable,
				rd_en => outputBufferIn(0).readEnable,
				dout => outputBufferOut(0).data,
				full => swOutputLinksIn(0).full,
				empty => outputBufferOut(0).empty
			);
	
	downstream1BufferFifo : fbSwitchFifo
			port map (
				rd_clk => downstream0ReadClock,
				wr_clk => clk125,
				rst => reset,
				din => swOutputLinksOut(1).data,
				wr_en => swOutputLinksOut(1).writeEnable,
				rd_en => outputBufferIn(1).readEnable,
				dout => outputBufferOut(1).data,
				full => swOutputLinksIn(1).full,
				empty => outputBufferOut(1).empty
			);
	
	
	-----------------------------------------------------------------
	-- OUTPUT TO RING
	-----------------------------------------------------------------
	
	ringOutputOut(numExtPorts-1 downto 0) <= outputBufferOut(numPorts-1 downto numIntPorts);
	outputBufferIn(numPorts-1 downto numIntPorts) <= ringOutputIn;
	
	
	-----------------------------------------------------------------
	-- DOWNSTREAM TO FUNCTIONAL BLOCK
	-----------------------------------------------------------------
	
	downstream0Empty <= outputBufferOut(0).empty;
	downstream0Data <= outputBufferOut(0).data;
	outputBufferIn(0).readEnable <= downstream0ReadEnable;
	
	downstream1Empty <= outputBufferOut(1).empty;
	downstream1Data <= outputBufferOut(1).data;
	outputBufferIn(1).readEnable <= downstream0ReadEnable;
	
end architecture rtl;
