-- Created by IP Generator (Version 2022.2-SP6.7.1 build 188940)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT PANGO_REF_PLL
  PORT (
    clkout0 : OUT STD_LOGIC;
    lock : OUT STD_LOGIC;
    clkin1 : IN STD_LOGIC
  );
END COMPONENT;


the_instance_name : PANGO_REF_PLL
  PORT MAP (
    clkout0 => clkout0,
    lock => lock,
    clkin1 => clkin1
  );
