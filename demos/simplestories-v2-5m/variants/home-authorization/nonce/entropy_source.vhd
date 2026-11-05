library ieee;
use ieee.std_logic_1164.all;

-- Experimental physical entropy source. SIM_MODE is permanently false.
-- The standalone board assessment must establish its behavior on this device.
entity sawic_entropy_source is
  port(clk_i,rstn_i,enable_i: in std_logic;
       valid_o: out std_logic;
       data_o: out std_logic_vector(7 downto 0));
end entity;

architecture physical of sawic_entropy_source is
begin
  source: entity work.neoTRNG
    generic map(NUM_CELLS=>3,NUM_INV_START=>5,NUM_RAW_BITS=>64,SIM_MODE=>false)
    port map(clk_i=>clk_i,rstn_i=>rstn_i,enable_i=>enable_i,valid_o=>valid_o,data_o=>data_o);
end architecture;
