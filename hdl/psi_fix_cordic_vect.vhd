------------------------------------------------------------------------------
--  Copyright (c) 2018 by Paul Scherrer Institute, Switzerland
--  All rights reserved.
--  Authors: Oliver Bruendler
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Description
------------------------------------------------------------------------------
-- This component convertes cartesian coordinates to polar coordinates using
-- a vectoring CORDIC kernel. In pipelined mode it requires more logic but
-- can take one input sample every clock cycle. In serial mode it requires
-- N clock cycles but requires less logic.

------------------------------------------------------------------------------
-- Libraries
------------------------------------------------------------------------------
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
	use ieee.math_real.all;
	
library work;
	use work.psi_fix_pkg.all;
	use work.psi_common_array_pkg.all;
	use work.psi_common_math_pkg.all;
	
------------------------------------------------------------------------------
-- Entity Declaration
------------------------------------------------------------------------------
-- $$ processes=stim, resp $$
entity psi_fix_cordic_vect is
	generic (
		InFmt_g					: PsiFixFmt_t	:= (1, 0, 15);	-- Must be signed		$$ constant=(1,0,15) $$
		OutFmt_g				: PsiFixFmt_t	:= (0, 2, 16);	-- Must be unsigned		$$ constant=(0,2,16) $$
		InternalFmt_g			: PsiFixFmt_t	:= (1, 2, 22);	-- Must be signed		$$ constant=(1,2,22) $$
		AngleFmt_g				: PsiFixFmt_t	:= (0, 0, 15);	-- Must be unsigned		$$ constant=(0,0,15) $$
		AngleIntFmt_g			: PsiFixFmt_t	:= (1, -1, 18);	-- Must be signed		$$ constant=(1,-1,18) $$
		Iterations_g			: natural		:= 13;			--						$$ constant=13 $$
		GainComp_g				: boolean		:= False;		--						$$ export=true $$
		Round_g 				: PsiFixRnd_t	:= PsiFixTrunc;	--						$$ export=true $$
		Sat_g					: PsiFixSat_t	:= PsiFixWrap;	--						$$ export=true $$
		Mode_g					: string		:= "SERIAL";	-- PIPELINED or SERIAL	$$ export=true $$
		PlStgPerIter_g			: integer range 1 to 2	:= 1	-- Number of pipeline stages per iteration (does only affect pipelined implementation)
	);
	port (
		-- Control Signals
		Clk			: in 	std_logic;											-- $$ type=clk; freq=100e6 $$
		Rst			: in 	std_logic;											-- $$ type=rst; clk=Clk $$
		-- Input
		InVld		: in	std_logic;
		InRdy		: out	std_logic;											-- $$ lowactive=true $$
		InI			: in	std_logic_vector(PsiFixSize(InFmt_g)-1 downto 0);
		InQ			: in	std_logic_vector(PsiFixSize(InFmt_g)-1 downto 0);
		-- Output
		OutVld		: out	std_logic;
		OutAbs		: out	std_logic_vector(PsiFixSize(OutFmt_g)-1 downto 0);
		OutAng		: out	std_logic_vector(PsiFixSize(AngleFmt_g)-1 downto 0)
	);
end entity;
		
------------------------------------------------------------------------------
-- Architecture Declaration
------------------------------------------------------------------------------
architecture rtl of psi_fix_cordic_vect is

	-- *** Constants ***
	constant AngleTableReal_c : t_areal(0 to 31)	:= (0.125, 				0.0737918088252,	0.0389895651887,	0.0197917120803,
														0.00993426215277,	0.00497197391179,	0.00248659363948,	0.00124337269683,
														0.000621695834357,	0.000310849102962,	0.000155424699705,	7.77123683806e-05,
														3.88561865063e-05,	1.94280935426e-05,	9.71404680751e-06,	4.85702340828e-06,
														2.4285117047e-06,	1.21425585242e-06,	6.0712792622e-07,	3.03563963111e-07,
														1.51781981556e-07,	7.58909907779e-08,	3.7945495389e-08,	1.89727476945e-08,
														9.48637384724e-09,	4.74318692362e-09,	2.37159346181e-09,	1.1857967309e-09,
														5.92898365452e-10,	2.96449182726e-10,	1.48224591363e-10,	7.41122956816e-11);
	type AngleTable_t is array (0 to Iterations_g-1) of std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0);
	
	function AngleTableStdlv return AngleTable_t is
		variable Table : AngleTable_t;
	begin
		for i in 0 to Iterations_g-1 loop
			Table(i) := PsiFixFromReal(AngleTableReal_c(i), AngleIntFmt_g);
		end loop;
		return Table;
	end function;
	
	constant AngleTable_c : AngleTable_t := AngleTableStdlv;
	
	
	function CordicGain(iterations : integer) return real is
		variable g : real := 1.0;
	begin
		for i in 0 to iterations-1 loop
			g := g * sqrt(1.0+2.0**(-2.0*real(i)));
		end loop;
		return g;
	end function;
	
	constant GcFmt_c		: PsiFixFmt_t												:= (0, 0, 17);
	constant GcCoef_c		: std_logic_vector(PsiFixSize(GcFmt_c)-1 downto 0)			:= PsiFixFromReal(1.0/CordicGain(Iterations_g), GcFmt_c);
	constant AngInt_0_5_c	: std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0)	:= PsiFixFromReal(-0.5, AngleIntFmt_g); -- arg(0.5*2pi) = arg(-0.5*2pi)
	constant AngInt_1_0_c	: std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0)	:= PsiFixFromReal(0.0, AngleIntFmt_g); -- arg(1*2pi) = arg(0*2pi)
	
	-- *** Functions ***
	-- Cordic step for X
	function CordicStepX (	xLast		: std_logic_vector;
							yLast		: std_logic_vector;
							shift		: integer) return std_logic_vector is
		constant yShifted 		: std_logic_vector := PsiFixShiftRight(yLast, InternalFmt_g, shift, Iterations_g-1, InternalFmt_g, PsiFixTrunc, PsiFixWrap, true);
	begin
	
		if signed(yLast) < 0 then
			return PsiFixSub(	xLast, InternalFmt_g, 
								yShifted, InternalFmt_g, 
								InternalFmt_g, PsiFixTrunc, PsiFixWrap);
		else
			return PsiFixAdd(	xLast, InternalFmt_g, 
								yShifted, InternalFmt_g, 
								InternalFmt_g, PsiFixTrunc, PsiFixWrap);

		end if;			
	end function;
	
	-- Cordic step for Y
	function CordicStepY (	xLast		: std_logic_vector;
							yLast		: std_logic_vector;
							shift		: integer) return std_logic_vector is
		constant xShifted 		: std_logic_vector := PsiFixShiftRight(xLast, InternalFmt_g, shift, Iterations_g-1, InternalFmt_g, PsiFixTrunc, PsiFixWrap, true);
	begin
	
		if signed(yLast) < 0 then
			return	PsiFixAdd(	yLast, InternalFmt_g,
								xShifted, InternalFmt_g, 
								InternalFmt_g, PsiFixTrunc, PsiFixWrap);
		else
			return	PsiFixSub(	yLast, InternalFmt_g,
								xShifted, InternalFmt_g, 
								InternalFmt_g, PsiFixTrunc, PsiFixWrap);
		end if;			
	end function;

	-- Cordic step for Z
	function CordicStepZ (	zLast		: std_logic_vector;
							yLast		: std_logic_vector;
							iteration	: integer) return std_logic_vector is
		constant Atan_c : std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0) := AngleTable_c(iteration);
	begin
		if signed(yLast) < 0 then
			return	PsiFixSub(	zLast, AngleIntFmt_g,
								Atan_c, AngleIntFmt_g, 
								AngleIntFmt_g, PsiFixTrunc, PsiFixWrap);
		else
			return	PsiFixAdd(	zLast, AngleIntFmt_g,
								Atan_c, AngleIntFmt_g, 
								AngleIntFmt_g, PsiFixTrunc, PsiFixWrap);
		end if;			
	end function;
	
	-- Types
	type IntArr_t is array (natural range <>) of std_logic_vector(PsiFixSize(InternalFmt_g)-1 downto 0);
	type AngArr_t is array (natural range <>) of std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0);
	
begin
	--------------------------------------------
	-- Assertions
	--------------------------------------------
	assert InFmt_g.S = 1 report "psi_fix_cordic_vect: InFmt_g must be signed" severity error;
	assert OutFmt_g.S = 0 report "psi_fix_cordic_vect: OutFmt_g must be unsigned" severity error;
	assert InternalFmt_g.S = 1 report "psi_fix_cordic_vect: InternalFmt_g must be signed" severity error;
	assert Mode_g = "PIPELINED" or Mode_g = "SERIAL" report "psi_fix_cordic_vect: Mode_g must be PIPELINED or SERIAL" severity error;
	-- Note: Ignoring CORDIC growth, abs(z) still grows by up to sqrt(2) because sqrt(MAX**2 + MAX**2) = sqrt(2)*MAX.
	--       Then, CORDIC growth is asymptotically ~1.647. So, overall growth is ~2.33 ==> +2 integer bits needed in the worst case.
	assert InternalFmt_g.I >= InFmt_g.I+2 report "psi_fix_cordic_vect: InternalFmt_g must have at least 2 more int bits than InFmt_g" severity error;
	assert InternalFmt_g.F >= InFmt_g.F report "psi_fix_cordic_vect: Internal format must have at least as many frac bits as InFmt_g" severity error;
	-- Note: AngleIntFmt_g [-0.5, 0.5) is signed and AngleFmt_g [0.0, 1.0) is unsigned.
	assert AngleFmt_g.S = 0 report "psi_fix_cordic_vect: AngleFmt_g must be unsigned" severity error;
	assert AngleFmt_g.I = 0 report "psi_fix_cordic_vect: AngleFmt_g must have exactly 0 integer bits" severity error;
	assert AngleIntFmt_g.S = 1 report "psi_fix_cordic_vect: AngleIntFmt_g must be signed" severity error;
	assert AngleIntFmt_g.I = -1 report "psi_fix_cordic_vect: AngleIntFmt_g must have exactly -1 integer bits" severity error;
	
	--------------------------------------------
	-- Pipelined Implementation
	--------------------------------------------	
	g_pipelined : if Mode_g = "PIPELINED" generate
		signal IReg, Qreg	: std_logic_vector(PsiFixSize(InFmt_g)-1 downto 0);
		signal VldReg		: std_logic;
		signal X, Y			: IntArr_t(0 to Iterations_g*PlStgPerIter_g);
		signal Z			: AngArr_t(0 to Iterations_g*PlStgPerIter_g);
		signal Vld			: std_logic_vector(0 to Iterations_g*PlStgPerIter_g);
		signal Quad			: t_aslv2(0 to Iterations_g*PlStgPerIter_g);
	begin
		-- Pipelined implementation can take a sample every clock cycle
		InRdy <= '1';
	
		-- Implementation
		p_cordic_pipelined : process(Clk)
		begin
			if rising_edge(Clk) then
				if Rst = '1' then
					Vld		<= (others => '0');
					VldReg	<= '0';
					OutVld	<= '0';
				else
					-- Input registering
					VldReg	<= InVld;
					IReg	<= InI;
					Qreg	<= InQ;
					
					-- Map to quadrant one
					-- No rounding or saturation because InternalFmt_g is checked to have sufficient int and frac bits
					X(0)	<= PsiFixAbs(IReg, InFmt_g, InternalFmt_g, PsiFixTrunc, PsiFixWrap);
					Y(0)	<= PsiFixAbs(Qreg, InFmt_g, InternalFmt_g, PsiFixTrunc, PsiFixWrap);
					Z(0)	<= (others => '0');
					Quad(0)	<= IReg(IReg'left) & Qreg(Qreg'left);
					Vld(0)	<= VldReg;
					
					-- Cordic Iterations_g
					Vld(1 to Vld'high) <= Vld(0 to Vld'high-1);
					Quad(1 to Quad'high) <= Quad(0 to Quad'high-1);
					for i in 0 to Iterations_g-1 loop
						X(i*PlStgPerIter_g+1) <= CordicStepX(X(i*PlStgPerIter_g), Y(i*PlStgPerIter_g), i);
						Y(i*PlStgPerIter_g+1) <= CordicStepY(X(i*PlStgPerIter_g), Y(i*PlStgPerIter_g), i);
						Z(i*PlStgPerIter_g+1) <= CordicStepZ(Z(i*PlStgPerIter_g), Y(i*PlStgPerIter_g), i); 
						-- Additional pipeline registers if required
						for k in 2 to PlStgPerIter_g loop
							X(i*PlStgPerIter_g+k) <= X(i*PlStgPerIter_g+k-1);
							Y(i*PlStgPerIter_g+k) <= Y(i*PlStgPerIter_g+k-1);
							Z(i*PlStgPerIter_g+k) <= Z(i*PlStgPerIter_g+k-1);
						end loop;
					end loop;
					
					-- Output 
					OutVld <= Vld(Iterations_g*PlStgPerIter_g);
					if GainComp_g then
						OutAbs <= PsiFixMult(X(Iterations_g*PlStgPerIter_g), InternalFmt_g, GcCoef_c, GcFmt_c, OutFmt_g, Round_g, Sat_g);
					else
						OutAbs <= PsiFixResize(X(Iterations_g*PlStgPerIter_g), InternalFmt_g, OutFmt_g, Round_g, Sat_g);
					end if;
					case Quad(Iterations_g*PlStgPerIter_g) is
						-- Normalized angles are never saturated. With 1 non-fractional bit, wrapping is correct behavior.
						when "00"	=> 	OutAng <= PsiFixResize(Z(Iterations_g*PlStgPerIter_g), AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
						when "10"	=> 	OutAng <= PsiFixSub(AngInt_0_5_c, AngleIntFmt_g, Z(Iterations_g*PlStgPerIter_g), AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
						when "11"	=> 	OutAng <= PsiFixAdd(AngInt_0_5_c, AngleIntFmt_g, Z(Iterations_g*PlStgPerIter_g), AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
						when "01"	=> 	OutAng <= PsiFixSub(AngInt_1_0_c, AngleIntFmt_g, Z(Iterations_g*PlStgPerIter_g), AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
						when others => null;
					end case;
				end if;
			end if;
		end process;
	end generate;
	
	--------------------------------------------
	-- Serial Implementation
	--------------------------------------------
	g_serial : if Mode_g = "SERIAL" generate
		signal Xin, Yin		: std_logic_vector(PsiFixSize(InternalFmt_g)-1 downto 0);
		signal XinVld		: std_logic;	
		signal Quadin		: std_logic_vector(1 downto 0);
		signal X, Y			: std_logic_vector(PsiFixSize(InternalFmt_g)-1 downto 0);
		signal Z			: std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0);
		signal CordVld		: std_logic;
		signal IterCnt		: integer range 0 to Iterations_g-1;
		signal Quad			: std_logic_vector(1 downto 0);
		constant Z0_c		: std_logic_vector(PsiFixSize(AngleIntFmt_g)-1 downto 0) := (others => '0');
	begin
		InRdy <= not XinVld;
	
		p_cordic_serial : process(Clk)
		begin		
			if rising_edge(Clk) then
				if Rst = '1' then
					XinVld	<= '0';
					IterCnt	<= 0;
					OutVld 	<= '0';
					CordVld <= '0';
				else
					-- Input latching
					if XinVld = '0' and InVld = '1' then
						XinVld <= '1';
						-- Map to quadrant one
						-- No rounding or saturation because InternalFmt_g is checked to have sufficient int and frac bits
						Xin		<= PsiFixAbs(InI, InFmt_g, InternalFmt_g, PsiFixTrunc, PsiFixWrap);
						Yin		<= PsiFixAbs(InQ, InFmt_g, InternalFmt_g, PsiFixTrunc, PsiFixWrap);
						Quadin	<= InI(InI'left) & InQ(InQ'left);
					end if;
					
					-- CORDIC loop
					CordVld <= '0';
					if IterCnt = 0 then
						-- Start of calculation
						if XinVld = '1' then
							X <= CordicStepX(Xin, Yin, 0);
							Y <= CordicStepY(Xin, Yin, 0);
							Quad <= Quadin;
							Z <= CordicStepZ(Z0_c, Yin, 0);
							IterCnt <= IterCnt+1;
							XinVld <= '0';
						end if;
					else
						-- Normal Calculation Step
						X <= CordicStepX(X, Y, IterCnt);
						Y <= CordicStepY(X, Y, IterCnt);
						Z <= CordicStepZ(Z, Y, IterCnt);

						if IterCnt = Iterations_g-1 then
							IterCnt <= 0;
							CordVld <= '1';
						else	
							IterCnt <= IterCnt+1;
						end if;
					end if;
					
					-- Output stage
					OutVld 		<= CordVld;
					if CordVld = '1' then
						if GainComp_g then
							OutAbs <= PsiFixMult(X, InternalFmt_g, GcCoef_c, GcFmt_c, OutFmt_g, Round_g, Sat_g);
						else
							OutAbs <= PsiFixResize(X, InternalFmt_g, OutFmt_g, Round_g, Sat_g);
						end if;
						case Quad is
							-- Normalized angles are never saturated. With 1 non-fractional bit, wrapping is correct behavior.
							when "00"	=> 	OutAng <= PsiFixResize(Z, AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
							when "10"	=> 	OutAng <= PsiFixSub(AngInt_0_5_c, AngleIntFmt_g, Z, AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
							when "11"	=> 	OutAng <= PsiFixAdd(AngInt_0_5_c, AngleIntFmt_g, Z, AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
							when "01"	=> 	OutAng <= PsiFixSub(AngInt_1_0_c, AngleIntFmt_g, Z, AngleIntFmt_g, AngleFmt_g, Round_g, PsiFixWrap);
							when others => null;
						end case;
					end if;
				end if;
			end if;
		end process;
	end generate;
end;
