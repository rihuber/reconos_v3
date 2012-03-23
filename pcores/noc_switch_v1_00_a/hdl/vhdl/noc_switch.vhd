library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

library noc_switch_v1_00_a;
use noc_switch_v1_00_a.switchPkg.all;
use noc_switch_v1_00_a.headerPkg.all;

entity noc_switch is
	generic (
		globalAddr : integer := 0
	);
  	port (
		clk125		: in std_logic;
		reset		: in std_logic;

		downstream0ReadEnable	: in std_logic;
		downstream0Empty  	: out std_logic;
		downstream0Data		: out std_logic_vector(dataWidth downto 0);

		downstream1ReadEnable	: in std_logic;
		downstream1Empty  	: out std_logic;
		downstream1Data		: out std_logic_vector(dataWidth downto 0);

		upstream0WriteEnable	: in std_logic;
		upstream0Data		: in std_logic_vector(dataWidth downto 0);
		upstream0Full 		: out std_logic;

		upstream1WriteEnable	: in std_logic;
		upstream1Data		: in std_logic_vector(dataWidth downto 0);
		upstream1Full 		: out std_logic
  	);
end noc_switch;



architecture rtl of noc_switch is
	
	component interSwitchFifo
		port (
		clk: IN std_logic;
		rst: IN std_logic;
		din: IN std_logic_VECTOR(8 downto 0);
		wr_en: IN std_logic;
		rd_en: IN std_logic;
		dout: OUT std_logic_VECTOR(8 downto 0);
		full: OUT std_logic;
		empty: OUT std_logic
	);
	end component;
	
begin

	up0_down1 : interSwitchFifo
		port map (
			clk => clk125,
			rst => reset,
			din => upstream0Data,
			wr_en => upstream0WriteEnable,
			rd_en => downstream1ReadEnable,
			dout => downstream1Data,
			full => upstream0Full,
			empty => downstream1Empty
		);

	up1_down0 : interSwitchFifo
		port map (
			clk => clk125,
			rst => reset,
			din => upstream1Data,
			wr_en => upstream1WriteEnable,
			rd_en => downstream0ReadEnable,
			dout => downstream0Data,
			full => upstream1Full,
			empty => downstream0Empty
		);
	
end architecture rtl;
