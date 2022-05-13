---------------------------------------------------------------------------------------------------
--  Copyright (c) 2018 by Paul Scherrer Institute, Switzerland
--  All rights reserved.
--  Authors: Oliver Bruendler
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Multiplication of two complex numbers

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.psi_fix_pkg.all;
use work.psi_common_math_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity Declaration
---------------------------------------------------------------------------------------------------
-- $$ processes=stim, resp $$
entity psi_fix_complex_mult is
	generic(
		RstPol_g      : std_logic   := '1'; -- set reset polarity														$$ constant='1' $$
		Pipeline_g    : boolean     := false; -- when false 3 pipes stages, when false 6 pipes (increase Fmax)			$$ export=true $$
		InAFmt_g      : PsiFixFmt_t := (1, 0, 15); -- Input A Fixed Point format 										$$ constant=(1,0,15) $$
		InBFmt_g      : PsiFixFmt_t := (1, 0, 24); -- Input B Fixed Point format 										$$ constant=(1,0,24) $$
		OutFmt_g      : PsiFixFmt_t := (1, 0, 20); -- Output Fixed Point format											$$ constant=(1,0,20) $$
		Round_g       : PsiFixRnd_t := PsiFixRound; --																	$$ constant=PsiFixRound $$
		Sat_g         : PsiFixSat_t := PsiFixSat; --																	$$ constant=PsiFixSat $$
		InAIsCplx_g	  : boolean		:= true;
		InBIsCplx_g	  : boolean		:= true;
        Mult4_g       : boolean     := true
	);
	port(
		InClk     	: in  std_logic;      -- clk 																			$$ type=clk; freq=100e6 $$
		InRst     	: in  std_logic;      -- sync. rst																	$$ type=rst; clk=clk_i $$

		InIADat 	: in  std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0); -- Inphase input of signal A
		InQADat 	: in  std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0); -- Quadrature input of signal A
		InIBDat 	: in  std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0); -- Inphase input of signal B
		InQBDat 	: in  std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0); -- Quadrature input of signal B
		InVld     	: in  std_logic;      -- strobe input

		OutIDat 	: out std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0); -- data output I
		OutQDat 	: out std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0); -- data output Q
		OutVld    	: out std_logic       -- strobe output
	);
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture Declaration
---------------------------------------------------------------------------------------------------
architecture rtl of psi_fix_complex_mult is

begin
	-----------------------------------------------------------------------------------------------
	-- Instantiations
	-----------------------------------------------------------------------------------------------
	
    g_arch_3m: if not(Mult4_g) generate
        -- architecture with 3 multiplications
        i_3m: entity work.psi_fix_complex_mult_3m
        generic map(
            RstPol_g        => RstPol_g,   
            Pipeline_g      => Pipeline_g, 
            InAFmt_g        => InAFmt_g,   
            InBFmt_g        => InBFmt_g,   
            OutFmt_g        => OutFmt_g,   
            Round_g         => Round_g,   
            Sat_g           => Sat_g,      
            InAIsCplx_g	    => InAIsCplx_g,
            InBIsCplx_g	    => InBIsCplx_g
        )
        port map(
            InClk           => InClk,       
            InRst     	    => InRst,  
                            
            InIADat 	    => InIADat,
            InQADat 	    => InQADat,
            InIBDat 	    => InIBDat,
            InQBDat 	    => InQBDat,
            InVld     	    => InVld,  
                            
            OutIDat 	    => OutIDat,
            OutQDat 	    => OutQDat,
            OutVld    	    => OutVld 
        );
    end generate;
    
    g_arch_4m: if Mult4_g generate
        -- architecture with 4 multiplications
        i_4m: entity work.psi_fix_complex_mult_4m
        generic map(
            RstPol_g        => RstPol_g,   
            Pipeline_g      => Pipeline_g, 
            InAFmt_g        => InAFmt_g,   
            InBFmt_g        => InBFmt_g,   
            OutFmt_g        => OutFmt_g,   
            Round_g         => Round_g,   
            Sat_g           => Sat_g,      
            InAIsCplx_g	    => InAIsCplx_g,
            InBIsCplx_g	    => InBIsCplx_g
        )
        port map(
            InClk           => InClk,       
            InRst     	    => InRst,  
                            
            InIADat 	    => InIADat,
            InQADat 	    => InQADat,
            InIBDat 	    => InIBDat,
            InQBDat 	    => InQBDat,
            InVld     	    => InVld,  
                            
            OutIDat 	    => OutIDat,
            OutQDat 	    => OutQDat,
            OutVld    	    => OutVld 
        );
    end generate;
    
end architecture;
