library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.switchPkg.all;
use noc_switch_v1_00_a.headerPkg.all;

entity noc_switch is
	generic (
		globalAddr : std_logic_vector(3 downto 0) := B"0000"
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
	signal upstreamInputLinksIn	: inputLinkInArray(numIntPorts-1 downto 0);
	
	                   
--	component fbSwitchFifo
--		port (
--		rst: IN std_logic;
--		rd_clk: IN std_logic;
--		wr_clk: IN std_logic;
--		din: IN std_logic_VECTOR(8 downto 0);
--		wr_en: IN std_logic;
--		rd_en: IN std_logic;
--		dout: OUT std_logic_VECTOR(8 downto 0);
--		full: OUT std_logic;
--		empty: OUT std_logic
--	);
--	end component;

	
	component switch is
		generic(
			globalAddress	: std_logic_vector(3 downto 0)	-- The global address of this switch. Packets with this global address are forwarded to the internal output link corresponding to the local address of the packet.
		);
		port (
			clk				: in std_logic;
			reset			: in std_logic;
			inputLinksIn	: in inputLinkInArray(numPorts-1 downto 0);		-- Input signals of the input links (internal AND external links)
			inputLinksOut	: out inputLinkOutArray(numPorts-1 downto 0);	-- Output signals of the input links (internal AND external links)
			outputLinksIn	: in outputLinkInArray(numPorts-1 downto 0);	-- Input signals of the output links (internal AND external links)
			outputLinksOut	: out outputLinkOutArray(numPorts-1 downto 0)	-- Output signals of the output links (internal AND external)
		);
	end component;
	
	
begin
	
	-----------------------------------------------------------------
	-- INPUT BUFFER FROM FUNCTIONAL BLOCK
	-----------------------------------------------------------------
	
	fifo_upstream0 : entity noc_switch_v1_00_a.interSwitchFifo
		port map (
			rst => reset,
			clk => clk125,
			din => upstream0Data,
			wr_en => upstream0WriteEnable,
			rd_en => swInputLinksOut(0).readEnable,
			dout => upstreamInputLinksIn(0).data,
			full => upstream0Full,
			empty => upstreamInputLinksIn(0).empty
		);
	
	fifo_upstream1 : entity noc_switch_v1_00_a.interSwitchFifo
		port map (
			rst => reset,
			clk => clk125,
			din => upstream1Data,
			wr_en => upstream1WriteEnable,
			rd_en => swInputLinksOut(1).readEnable,
			dout => upstreamInputLinksIn(1).data,
			full => upstream1Full,
			empty => upstreamInputLinksIn(1).empty
		);
		
	-----------------------------------------------------------------
	-- UNBUFFERED INPUT FROM RING
	-----------------------------------------------------------------
	
	unbufferedInputFromRing : process(ringInputData, ringInputEmpty, swInputLinksOut)
	begin
		swInputLinksIn(numIntPorts-1 downto 0) <= upstreamInputLinksIn;
		for i in 0 to numExtPorts-1 loop
			swInputLinksIn(i+numIntPorts).data <= ringInputData(((dataWidth+1)*(i+1))-1 downto (dataWidth+1)*i);
			swInputLinksIn(i+numIntPorts).empty <= ringInputEmpty(i);
			ringInputReadEnable(i) <= swInputLinksOut(i+numIntPorts).readEnable;
		end loop;
	end process;
		
	-----------------------------------------------------------------
	-- OUTPUT BUFFER TO FUNCTIONAL BLOCK
	-----------------------------------------------------------------
		
	fifo_downstream0 : entity noc_switch_v1_00_a.interSwitchFifo
		port map (
			rst => reset,
			clk => clk125,
			din => swOutputLinksOut(0).data,
			wr_en => swOutputLinksOut(0).writeEnable,
			rd_en => downstream0ReadEnable,
			dout => downstream0Data,
			full => swOutputLinksIn(0).full,
			empty => downstream0Empty
		);
	
	fifo_downstream1 : entity noc_switch_v1_00_a.interSwitchFifo
		port map (
			rst => reset,
			clk => clk125,
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
		fifo_ring : entity noc_switch_v1_00_a.interSwitchFifo
			port map (
				rst => reset,
				clk => clk125,
				din => swOutputLinksOut(i+numIntPorts).data,
				wr_en => swOutputLinksOut(i+numIntPorts).writeEnable,
				rd_en => ringOutputReadEnable(i),
				dout => ringOutputData(((dataWidth+1)*(i+1))-1 downto (dataWidth+1)*i),
				full => swOutputLinksIn(i+numIntPorts).full,
				empty => ringOutputEmpty(i)
			);
	end generate;
		
	-----------------------------------------------------------------
	-- THE SWITCH
	-----------------------------------------------------------------	
	
	sw : switch
		generic map(
			globalAddress => globalAddr
		)
		port map(
			clk				=> clk125,
			reset			=> reset,
			inputLinksIn	=> swInputLinksIn,
			inputLinksOut	=> swInputLinksOut,
			outputLinksIn	=> swOutputLinksIn,
			outputLinksOut	=> swOutputLinksOut
		);
	
end architecture rtl;
