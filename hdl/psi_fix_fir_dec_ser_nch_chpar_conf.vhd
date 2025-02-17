------------------------------------------------------------------------------
--  Copyright (c) 2018 by Paul Scherrer Institute, Switzerland
--  All rights reserved.
--  Authors: Oliver Bruendler
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Description
------------------------------------------------------------------------------
-- This component calculateas an FIR filter with the following limitations:
-- - Filter is calculated serially (one tap after the other)
-- - The number of channels is configurable
-- - All channels are processed in parallel and their data must be synchronized
-- - Coefficients are configurable but the same for each channel

------------------------------------------------------------------------------
-- Libraries
------------------------------------------------------------------------------
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
	
library work;
	use work.psi_fix_pkg.all;
	use work.psi_common_math_pkg.all;
	use work.psi_common_array_pkg.all;
	
------------------------------------------------------------------------------
-- Entity Declaration
------------------------------------------------------------------------------
entity psi_fix_fir_dec_ser_nch_chpar_conf is
	generic (
		InFmt_g					: PsiFixFmt_t					:= (1, 0, 17);	
		OutFmt_g				: PsiFixFmt_t					:= (1, 0, 17);	
		CoefFmt_g				: PsiFixFmt_t					:= (1, 0, 17);
		Channels_g				: natural						:= 2;
		MaxRatio_g				: natural						:= 8;
		MaxTaps_g				: natural						:= 1024;
		Rnd_g					: PsiFixRnd_t					:= PsiFixRound;
		Sat_g					: PsiFixSat_t					:= PsiFixSat;
		UseFixCoefs_g			: boolean						:= false;
		Coefs_g				: t_areal						:= (0.0, 0.0);
		RamBehavior_g			: string						:= "RBW"	-- RBW = Read before write, WBR = Write before read
	);
	port (
		-- Control Signals
		Clk			: in 	std_logic;
		Rst			: in 	std_logic;
		-- Input
		InVld		: in	std_logic;
		InData		: in	std_logic_vector(PsiFixSize(InFmt_g)*Channels_g-1 downto 0);
		-- Output
		OutVld		: out	std_logic;
		OutData		: out	std_logic_vector(PsiFixSize(OutFmt_g)*Channels_g-1 downto 0);
		-- Parallel Configuration Interface
		Ratio		: in	std_logic_vector(log2ceil(MaxRatio_g)-1 downto 0)	:= std_logic_vector(to_unsigned(MaxRatio_g-1, log2ceil(MaxRatio_g))); 	-- Ratio - 1 (0 => Ratio 1, 4 => Ratio 5)
		Taps		: in	std_logic_vector(log2ceil(MaxTaps_g)-1 downto 0)	:= std_logic_vector(to_unsigned(MaxTaps_g-1, log2ceil(MaxTaps_g)));		-- Number of taps - 1
		-- Coefficient interface
		CoefClk		: in	std_logic											:= '0';
		CoefWr		: in	std_logic											:= '0';
		CoefAddr	: in	std_logic_vector(log2ceil(MaxTaps_g)-1 downto 0)	:= (others => '0');
		CoefWrData	: in	std_logic_vector(PsiFixSize(CoefFmt_g)-1 downto 0)	:= (others => '0');
		CoefRdData	: out	std_logic_vector(PsiFixSize(CoefFmt_g)-1 downto 0);
		-- Status Output
		CalcOngoing	: out	std_logic
	);
end entity;
		
------------------------------------------------------------------------------
-- Architecture Declaration
------------------------------------------------------------------------------
architecture rtl of psi_fix_fir_dec_ser_nch_chpar_conf is

	constant DataMemDepthApplied_c		: natural	:= 2**log2ceil(MaxTaps_g);
	constant CoefMemDepthApplied_c		: natural	:= 2**log2ceil(MaxTaps_g);

	-- Constants
	constant MultFmt_c	: PsiFixFmt_t		:= (max(InFmt_g.S, CoefFmt_g.S), InFmt_g.I+CoefFmt_g.I, InFmt_g.F+CoefFmt_g.F);
	constant AccuFmt_c	: PsiFixFmt_t		:= (1, OutFmt_g.I+1, InFmt_g.F + CoefFmt_g.F);
	constant RndFmt_c	: PsiFixFmt_t		:= (1, OutFmt_g.I+1, OutFmt_g.F);

	-- types
	type InData_t is array (0 to Channels_g-1) of std_logic_vector(PsiFixSize(InFmt_g)-1 downto 0);
	type InData_a is array (natural range <>) of InData_t;
	type Mult_t is array (0 to Channels_g-1) of std_logic_vector(PsiFixSize(MultFmt_c)-1 downto 0);
	type Accu_t is array (0 to Channels_g-1) of std_logic_vector(PsiFixSize(AccuFmt_c)-1 downto 0);
	type Rnd_t is array (0 to Channels_g-1) of std_logic_vector(PsiFixSize(RndFmt_c)-1 downto 0);
	type Out_t is array (0 to Channels_g-1) of std_logic_vector(PsiFixSize(OutFmt_g)-1 downto 0);
	

	-- Two process method
	type two_process_r is record
		Vld					: std_logic_vector(0 to 2);
		InSig				: InData_a(0 to 2);
		DataWrAddr_1		: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		DecCnt_1			: unsigned(log2ceil(MaxRatio_g)-1 downto 0);
		TapCnt_1			: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		Data0Addr_2			: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		DataWrAddr_2		: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		DataRdAddr_2		: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		CoefRdAddr_2		: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		AddrWrittenCount_3	: unsigned(log2ceil(MaxTaps_g) downto 0);  -- Truly need +1 bit (number of addresses is 2**n).
		DataRdAddr_3		: unsigned(log2ceil(MaxTaps_g)-1 downto 0);
		CalcOn				: std_logic_vector(1 to 6);
		Last				: std_logic_vector(2 to 6);
		First 				: std_logic_vector(1 to 5);
		MultInData_4		: InData_t;
		MultInCoef_4		: std_logic_vector(PsiFixSize(CoefFmt_g)-1 downto 0);
		MultOut_5			: Mult_t;
		Accu_6				: Accu_t;
		Rnd_7				: Rnd_t;
		RndVld_7			: std_logic;
		Output_8			: Out_t;
		OutVld_8			: std_logic;
		ReplaceZero_3		: std_logic;
		-- Status
		CalcOngoing			: std_logic;
	end record;
	
	signal r, r_next : two_process_r;
	
	-- Component Interface Signals
	signal DataRamDin_2		: std_logic_vector(PsiFixSize(InFmt_g)*Channels_g-1 downto 0);
	signal DataRamDout_3	: std_logic_vector(PsiFixSize(InFmt_g)*Channels_g-1 downto 0);
	signal CoefRamDout_3	: std_logic_vector(PsiFixSize(CoefFmt_g)-1 downto 0);
	
	-- coef ROM
	type CoefRom_t is array (Coefs_g'low to Coefs_g'high) of std_logic_vector(PsiFixSize(CoefFmt_g)-1 downto 0);
	signal CoefRom 	: CoefRom_t;
	
	
begin
	--------------------------------------------
	-- Combinatorial Process
	--------------------------------------------
	p_comb : process(r, InVld, InData,
					Ratio, Taps,
					DataRamDout_3, CoefRamDout_3)
		variable v : two_process_r;
		variable AccuIn_v		: std_logic_vector(PsiFixSize(AccuFmt_c)-1 downto 0);
	begin
		-- *** Hold variables stable ***
		v := r;
		
		-- *** Pipe Handling ***
		v.Vld(v.Vld'low+1 to v.Vld'high)				:= r.Vld(r.Vld'low to r.Vld'high-1);
		v.InSig(v.InSig'low+1 to v.InSig'high)			:= r.InSig(r.InSig'low to r.InSig'high-1);
		v.CalcOn(v.CalcOn'low+1 to v.CalcOn'high)		:= r.CalcOn(r.CalcOn'low to r.CalcOn'high-1);
		v.Last(v.Last'low+1 to v.Last'high)				:= r.Last(r.Last'low to r.Last'high-1);
		v.First(v.First'low+1 to v.First'high)			:= r.First(r.First'low to r.First'high-1);
		
		-- *** Stage 0 ***
		-- Input Registers
		v.Vld(0)	:= InVld;
		for i in 0 to Channels_g-1 loop
			v.InSig(0)(i)	:= InData(PsiFixSize(InFmt_g)*(i+1)-1 downto PsiFixSize(InFmt_g)*i);
		end loop;
			
		-- *** Stage 1 ***
		-- Increment data write address immediately after data was written
		if r.Vld(1) = '1' then
			v.DataWrAddr_1	:= r.DataWrAddr_1 + 1;
		end if;	
		
		-- Convolution calculation control
		if r.TapCnt_1 /= 0 then
			v.TapCnt_1 	:= r.TapCnt_1 - 1;
		else
			v.CalcOn(1)	:= '0';
		end if;
		
		-- Start a convolution calculation in response to InVld (but with decimation)
		v.First(1) := '0';
		if r.Vld(0) = '1' then
			if (r.DecCnt_1 = 0) or (MaxRatio_g = 1) then
				v.DecCnt_1	:= unsigned(Ratio);
				v.TapCnt_1	:= unsigned(Taps);
				v.CalcOn(1)	:= '1';
				v.First(1) := '1';
			else
				v.DecCnt_1 	:= r.DecCnt_1 - 1;
			end if;
		end if;
		
		-- *** Stage 2 ***
		v.DataWrAddr_2 := r.DataWrAddr_1;
		-- Data read address
		if r.First(1) = '1' then
			v.Data0Addr_2	:= r.DataWrAddr_1;
		end if;
		v.DataRdAddr_2 	:= v.Data0Addr_2 - r.TapCnt_1; -- Note: Read v.Data0Addr_2 in same cycle.
		-- Coefficient read address
		v.CoefRdAddr_2	:= r.TapCnt_1;
		
		-- Set "last" flag to mark the end of the convolution calculation
		if r.TapCnt_1 = 0 or unsigned(Taps) = 0 then
			v.Last(2) := '1';
		else
			v.Last(2) := '0';
		end if;
		
		-- *** Stage 3 ***
		v.DataRdAddr_3 	:= r.DataRdAddr_2;
		-- Keep track of how many addresses have been written with valid data after reset
		if r.Vld(2) = '1' and r.DataWrAddr_2 >= r.AddrWrittenCount_3 then
			v.AddrWrittenCount_3 := resize(r.DataWrAddr_2, v.AddrWrittenCount_3'length) + 1;
		end if;
		-- Pipelining
		-- Set flag to overwrite invalid data with zeros
		if r.AddrWrittenCount_3 > r.DataRdAddr_3 then
			v.ReplaceZero_3 := '0';
		else
			v.ReplaceZero_3 := '1';
		end if;
		
		-- *** Stage 4 ***
		-- Multiplier input registering
		for i in 0 to Channels_g-1 loop
			-- Replace taps that are not yet written with zeros for bittrueness
			if r.AddrWrittenCount_3 > r.DataRdAddr_3 then
				v.MultInData_4(i)	:= DataRamDout_3(PsiFixSize(InFmt_g)*(i+1)-1 downto PsiFixSize(InFmt_g)*i);
			else
				v.MultInData_4(i)	:= (others => '0');
			end if;
		end loop;
		v.MultInCoef_4	:= CoefRamDout_3;
		
		-- *** Stage 5 *** 
		-- Multiplication
		for i in 0 to Channels_g-1 loop
			v.MultOut_5(i)	:= PsiFixMult(	r.MultInData_4(i), InFmt_g,
											r.MultInCoef_4, CoefFmt_g,
											MultFmt_c); -- Full precision, no rounding or saturation required
		end loop;
		
		-- *** Stage 6 ***
		-- Accumulator
		AccuIn_v := (others => '0');
		for i in 0 to Channels_g-1 loop
			if r.First(5) = '1' then
				AccuIn_v := (others => '0');
			else
				AccuIn_v := r.Accu_6(i);
			end if;
			v.Accu_6(i)	:= PsiFixAdd(	r.MultOut_5(i), MultFmt_c,
										AccuIn_v, AccuFmt_c,
										AccuFmt_c); -- Overflows compensate at the end of the calculation and rounding not required

		end loop;		
		
		-- *** Stage 7 ***
		-- Rounding
		v.RndVld_7 := '0';
		if r.Last(6) = '1' then
			for i in 0 to Channels_g-1 loop
				v.Rnd_7(i)	:= PsiFixResize(r.Accu_6(i), AccuFmt_c, RndFmt_c, Rnd_g, PsiFixWrap);
			end loop;
			v.RndVld_7 := r.CalcOn(6);
		end if;		
		
		-- *** Stage 8 ***
		-- Output Handling and saturation
		v.OutVld_8 := r.RndVld_7;
		for i in 0 to Channels_g-1 loop
			v.Output_8(i)	:= PsiFixResize(r.Rnd_7(i), RndFmt_c, OutFmt_g, PsiFixTrunc, Sat_g);
		end loop;

		
		-- *** Status Output ***
		if (unsigned(r.Vld) /= 0) or (unsigned(r.CalcOn) /= 0) or (r.RndVld_7 = '1') then
			v.CalcOngoing := '1';
		else
			v.CalcOngoing := '0';
		end if;
				
		-- *** Outputs ***
		OutVld	<= r.OutVld_8;
		for i in 0 to Channels_g-1 loop
			OutData(PsiFixSize(OutFmt_g)*(i+1)-1 downto PsiFixSize(OutFmt_g)*i)	<= r.Output_8(i);
		end loop;	
		CalcOngoing <= r.CalcOngoing or r.Vld(0);
		
		-- *** Assign to signal ***
		r_next <= v;
	end process;
	

	
	--------------------------------------------
	-- Sequential Process
	--------------------------------------------
	p_seq : process(Clk)
	begin	
		if rising_edge(Clk) then
			r <= r_next;
			if Rst = '1' then	
				r.Vld 					<= (others => '0');
				r.DataWrAddr_1			<= (others => '0');
				r.DecCnt_1				<= (others => '0');
				r.AddrWrittenCount_3	<= (others => '0');
				r.CalcOn				<= (others => '0');
				r.RndVld_7				<= '0';
				r.OutVld_8				<= '0';
				r.Last					<= (others => '0');
				r.ReplaceZero_3			<= '1';
				r.CalcOngoing			<= '0';
			end if;
		end if;
	end process;
	
	--------------------------------------------
	-- Component Instantiations
	--------------------------------------------
	-- Coefficient RAM for configurable coefficients
	g_nFixCoef : if not UseFixCoefs_g generate
		i_coef_ram : entity work.psi_fix_param_ram
			generic map (
				Depth_g		=> CoefMemDepthApplied_c,
				Fmt_g		=> CoefFmt_g,
				Behavior_g	=> RamBehavior_g,
				Init_g		=> Coefs_g
			)
			port map (
				ClkA		=> CoefClk,
				AddrA		=> CoefAddr,
				WrA			=> CoefWr,
				DinA		=> CoefWrData,
				DoutA		=> CoefRdData,
				ClkB		=> Clk,
				AddrB		=> std_logic_vector(r.CoefRdAddr_2),
				WrB			=> '0',
				DinB		=> (others => '0'),
				DoutB		=> CoefRamDout_3
			);
	end generate;
	
	-- Coefficient ROM for non-configurable coefficients
	g_FixCoef : if UseFixCoefs_g generate
		-- Table must be generated outside of the ROM process to make code synthesizable
		g_CoefTable : for i in CoefRom'low to CoefRom'high generate
			CoefRom(i) <= PsiFixFromReal(Coefs_g(i), CoefFmt_g);
		end generate;
	
		-- Assign unused outputs
		CoefRdData <= (others => '0');
		-- Coefficient ROM
		p_coef_rom : process(Clk)
		begin
			if rising_edge(Clk) then
				CoefRamDout_3 <= CoefRom(to_integer(r.CoefRdAddr_2));
			end if;
		end process;
		
	end generate;
		
	g_data_in : for i in 0 to Channels_g-1 generate
		DataRamDin_2(PsiFixSize(InFmt_g)*(i+1)-1 downto PsiFixSize(InFmt_g)*i)	<= r.InSig(2)(i);
	end generate;

	i_data_ram : entity work.psi_common_sdp_ram
		generic map (
			Depth_g		=> DataMemDepthApplied_c,
			Width_g		=> PsiFixSize(InFmt_g)*Channels_g,
			IsAsync_g	=> false,
			Behavior_g	=> "RBW"  -- Must be read-first behavior.
		)
		port map (
			Clk		=> Clk,
			WrAddr	=> std_logic_vector(r.DataWrAddr_2),
			Wr		=> r.Vld(2),
			WrData	=> DataRamDin_2,
			RdAddr	=> std_logic_vector(r.DataRdAddr_2),
			RdData	=> DataRamDout_3
		);

end;
