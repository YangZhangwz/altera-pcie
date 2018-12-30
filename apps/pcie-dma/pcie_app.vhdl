--
-- Copyright (C) 2014, 2017 Chris McClelland
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the "Software"), to deal in the Software without
-- restriction, including without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright  notice and this permission notice  shall be included in all copies or
-- substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library makestuff;

entity pcie_app is
	port (
		pcieClk_in            : in  std_logic;  -- 125MHz clock from PCIe PLL
		cfgBusDev_in          : in  std_logic_vector(12 downto 0);  -- the device ID assigned to the FPGA on enumeration

		-- Incoming requests from the CPU
		rxData_in             : in  std_logic_vector(63 downto 0);
		rxValid_in            : in  std_logic;
		rxReady_out           : out std_logic;
		rxSOP_in              : in  std_logic;
		rxEOP_in              : in  std_logic;

		-- Outgoing responses from the FPGA
		txData_out            : out std_logic_vector(63 downto 0);
		txValid_out           : out std_logic;
		txReady_in            : in  std_logic;
		txSOP_out             : out std_logic;
		txEOP_out             : out std_logic
	);
end entity;

architecture rtl of pcie_app is
	constant REG_ABITS        : natural := 1;  -- 2**1 = 2 (just DMABASE & DMACTRL)
	signal dmaData            : std_logic_vector(63 downto 0);
	signal dmaValid           : std_logic;
	signal dmaReady           : std_logic;
	signal cpuReading         : std_logic;
	signal cpuWriting         : std_logic;
	signal cpuChannel         : std_logic;  -- std_logic_vector(REG_ABITS-1 downto 0);
	signal rngReset           : std_logic;
	signal counter            : std_logic_vector(31 downto 0) := (others => '0');
	signal counter_next       : std_logic_vector(31 downto 0);
begin
	-- Instantiate random-number generator
	rng: entity makestuff.dvr_rng64
		port map (
			clk_in           => pcieClk_in,
			reset_in         => rngReset,
			data_out         => dmaData,
			valid_out        => dmaValid,
			ready_in         => dmaReady
		);

	-- TLP-level interface
	tlp_inst: entity makestuff.tlp_xcvr
		generic map (
			REG_ABITS        => REG_ABITS
		)
		port map (
			pcieClk_in       => pcieClk_in,
			cfgBusDev_in     => cfgBusDev_in,

			-- Incoming requests from the CPU
			rxData_in        => rxData_in,
			rxValid_in       => rxValid_in,
			rxReady_out      => rxReady_out,
			rxSOP_in         => rxSOP_in,
			rxEOP_in         => rxEOP_in,

			-- Outgoing responses to the CPU
			txData_out       => txData_out,
			txValid_out      => txValid_out,
			txReady_in       => txReady_in,
			txSOP_out        => txSOP_out,
			txEOP_out        => txEOP_out,

			-- Internal read/write interface
			cpuChan_out(0)   => cpuChannel,
			cpuWrValid_out   => cpuWriting,
			cpuWrReady_in    => '1',
			cpuRdData_in     => counter,  -- all reads return the counter value
			cpuRdValid_in    => '1',
			cpuRdReady_out   => cpuReading,

			-- DMA stream
			dmaData_in       => dmaData,
			dmaValid_in      => dmaValid,
			dmaReady_out     => dmaReady
		);

	-- Infer counter register
	process(pcieClk_in)
	begin
		if ( rising_edge(pcieClk_in) ) then
			counter <= counter_next;
		end if;
	end process;

	-- Reset the RNG when reading register DMABASE
	rngReset <= cpuReading and not cpuChannel;

	-- Reset the counter when writing register DMACTRL
	counter_next <=
		(others => '0') when cpuWriting = '1' and cpuChannel = '1'
		else std_logic_vector(unsigned(counter) + 1);

end architecture;
