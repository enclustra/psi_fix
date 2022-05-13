---------------------------------------------------------------------------------------------------
--  Copyright (c) 2022 by Paul Scherrer Institute, Switzerland
--  All rights reserved.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Multiplication of two complex numbers with 4 multiplications

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
entity psi_fix_complex_mult_4m is
    generic(
        RstPol_g      : std_logic   := '1'; -- set reset polarity                                                       $$ constant='1' $$
        Pipeline_g    : boolean     := false; -- when false 3 pipes stages, when false 6 pipes (increase Fmax)          $$ export=true $$
        InAFmt_g      : PsiFixFmt_t := (1, 0, 17); -- Input A Fixed Point format                                        $$ constant=(1,0,15) $$
        InBFmt_g      : PsiFixFmt_t := (1, 0, 24); -- Input B Fixed Point format                                        $$ constant=(1,0,24) $$
        OutFmt_g      : PsiFixFmt_t := (1, 0, 20); -- Output Fixed Point format                                         $$ constant=(1,0,20) $$
        Round_g       : PsiFixRnd_t := PsiFixRound; --                                                                  $$ constant=PsiFixRound $$
        Sat_g         : PsiFixSat_t := PsiFixSat; --                                                                    $$ constant=PsiFixSat $$
        InAIsCplx_g   : boolean     := true;
        InBIsCplx_g   : boolean     := true
    );
    port(
        InClk       : in  std_logic;      -- clk                                                                        $$ type=clk; freq=100e6 $$
        InRst       : in  std_logic;      -- sync. rst                                                                  $$ type=rst; clk=clk_i $$

        InIADat     : in  std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0); -- Inphase input of signal A
        InQADat     : in  std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0); -- Quadrature input of signal A
        InIBDat     : in  std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0); -- Inphase input of signal B
        InQBDat     : in  std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0); -- Quadrature input of signal B
        InVld       : in  std_logic;      -- strobe input

        OutIDat     : out std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0); -- data output I
        OutQDat     : out std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0); -- data output Q
        OutVld      : out std_logic       -- strobe output
    );
end entity;

------------------------------------------------------------------------------
-- Architecture Declaration
------------------------------------------------------------------------------
architecture rtl of psi_fix_complex_mult_4m is
    
    -- Constants
    constant MultFmt_c      : PsiFixFmt_t := (max(InAFmt_g.S, InBFmt_g.S), InAFmt_g.I + InBFmt_g.I + 1, InAFmt_g.F + InBFmt_g.F);
    constant AddFmt_c       : PsiFixFmt_t := (MultFmt_c.S, MultFmt_c.I + 1, MultFmt_c.F);
    constant RndFmt_c       : PsiFixFmt_t := (AddFmt_c.S, AddFmt_c.I + 1, OutFmt_g.F);

    -- Two process method
    type two_process_r is record
        -- Registers always present
        VldPipe     : std_logic_vector(1 to 6);
        MultII_3    : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        MultIQ_3    : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        MultQI_3    : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        MultQQ_3    : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        SumI_4      : std_logic_vector(PsiFixSize(AddFmt_c) - 1 downto 0);
        SumQ_4      : std_logic_vector(PsiFixSize(AddFmt_c) - 1 downto 0);
        OutI        : std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0);
        OutQ        : std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0);
        -- Additional registers for pipelined version
        Vld_0       : std_logic;
        InIADat_0   : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_0   : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InIBDat_0   : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InQBDat_0   : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InIADat_1   : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_1   : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InIBDat_1   : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InQBDat_1   : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InIADat_2   : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_2   : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InIBDat_2   : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InQBDat_2   : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        RndI        : std_logic_vector(PsiFixSize(RndFmt_c) - 1 downto 0);
        RndQ        : std_logic_vector(PsiFixSize(RndFmt_c) - 1 downto 0);
    end record;
    
    -- Signals
    signal r, r_next : two_process_r;

begin
    --------------------------------------------
    -- Combinatorial Process
    --------------------------------------------
    p_comb : process(r, InIADat, InQADat, InIBDat, InQBDat, InVld)
        variable v : two_process_r;
    begin
        -- *** Hold variables stable ***
        v := r;
        
        -- *** Stage 0 (outside DSP slice) ***
        if Pipeline_g then 
            v.Vld_0      := InVld;
            v.InIADat_0  := InIADat;
            v.InQADat_0  := InQADat;
            v.InIBDat_0  := InIBDat;
            v.InQBDat_0  := InQBDat;
        end if;
        
        -- *** Stage 1 ***
        if Pipeline_g then 
            v.VldPipe(1) := r.Vld_0;
            v.InIADat_1  := r.InIADat_0;
            v.InQADat_1  := r.InQADat_0;
            v.InIBDat_1  := r.InIBDat_0;
            v.InQBDat_1  := r.InQBDat_0;
        else
            v.VldPipe(1) := InVld;
            v.InIADat_1  := InIADat;
            v.InQADat_1  := InQADat;
            v.InIBDat_1  := InIBDat;
            v.InQBDat_1  := InQBDat;
        end if;
        
        -- *** Stage 2 ***
        v.VldPipe(2) := r.VldPipe(1);
        v.InIADat_2  := r.InIADat_1;
        v.InQADat_2  := r.InQADat_1;
        v.InIBDat_2  := r.InIBDat_1;
        v.InQBDat_2  := r.InQBDat_1;
        
        -- *** Stage 3: multiplications ***
        v.VldPipe(3) := r.VldPipe(2);
        v.MultII_3   := PsiFixMult(r.InIADat_2, InAFmt_g, r.InIBDat_2, InBFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
        if InBIsCplx_g then
            v.MultIQ_3 := PsiFixMult(r.InIADat_2, InAFmt_g, r.InQBDat_2, InBFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
        else
            v.MultIQ_3 := (others => '0');
        end if;
        if InAIsCplx_g then
            v.MultQI_3 := PsiFixMult(r.InQADat_2, InAFmt_g, r.InIBDat_2, InBFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
        else
            v.MultQI_3 := (others => '0');
        end if;
        if InAIsCplx_g and InBIsCplx_g then
            v.MultQQ_3 := PsiFixMult(r.InQADat_2, InAFmt_g, r.InQBDat_2, InBFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
        else
            v.MultQQ_3 := (others => '0');
        end if;
        
        -- *** Stage 4: additions/substractions ***
        v.VldPipe(4) := r.VldPipe(3);
        v.SumI_4 := PsiFixSub(r.MultII_3, MultFmt_c, r.MultQQ_3, MultFmt_c, AddFmt_c, PsiFixTrunc, PsiFixWrap); 
        v.SumQ_4 := PsiFixAdd(r.MultIQ_3, MultFmt_c, r.MultQI_3, MultFmt_c, AddFmt_c, PsiFixTrunc, PsiFixWrap); 

        -- *** Resize (outside DSP slice, no pipeline numbering as its length is variable depending on Pipeline_g) ***
        if Pipeline_g then
            v.VldPipe(5) := r.VldPipe(4);
            v.RndI   := PsiFixResize(r.SumI_4, AddFmt_c, RndFmt_c, Round_g, PsiFixWrap);
            v.RndQ   := PsiFixResize(r.SumQ_4, AddFmt_c, RndFmt_c, Round_g, PsiFixWrap);
            v.VldPipe(6) := r.VldPipe(5);
            v.OutI   := PsiFixResize(r.RndI, RndFmt_c, OutFmt_g, PsiFixTrunc, Sat_g);
            v.OutQ   := PsiFixResize(r.RndQ, RndFmt_c, OutFmt_g, PsiFixTrunc, Sat_g);
        else
            v.VldPipe(5) := r.VldPipe(4);
            v.OutI   := PsiFixResize(r.SumI_4, AddFmt_c, OutFmt_g, Round_g, Sat_g);
            v.OutQ   := PsiFixResize(r.SumQ_4, AddFmt_c, OutFmt_g, Round_g, Sat_g);
        end if;

        -- *** Assign to signal ***
        r_next <= v;

    end process;

    --------------------------------------------
    -- Outputs
    --------------------------------------------
    g_pl : if Pipeline_g generate
        OutVld <= r.VldPipe(6); -- Latency 7 clock cycles
    end generate;
    g_npl : if not Pipeline_g generate
        OutVld <= r.VldPipe(5); -- Latency 5 clock cycles
    end generate;
    OutIDat <= r.OutI;
    OutQDat <= r.OutQ;

    --------------------------------------------
    -- Sequential Process
    --------------------------------------------
    p_seq : process(InClk)
    begin
        if rising_edge(InClk) then
            r <= r_next;
            if InRst = RstPol_g then
                r.VldPipe   <= (others => '0');
                if PipeLine_g then 
                    r.Vld_0 <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture;
