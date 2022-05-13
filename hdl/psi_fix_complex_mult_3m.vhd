---------------------------------------------------------------------------------------------------
--  Copyright (c) 2022 by Paul Scherrer Institute, Switzerland
--  All rights reserved.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Multiplication of two complex numbers with 3 multiplications

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
entity psi_fix_complex_mult_3m is
    generic(
        RstPol_g      : std_logic   := '1'; -- set reset polarity                                                       $$ constant='1' $$
        Pipeline_g    : boolean     := false; -- when false 3 pipes stages, when false 6 pipes (increase Fmax)          $$ export=true $$
        InAFmt_g      : PsiFixFmt_t := (1, 0, 16); -- Input A Fixed Point format                                        $$ constant=(1,0,15) $$
        InBFmt_g      : PsiFixFmt_t := (1, 0, 16); -- Input B Fixed Point format                                        $$ constant=(1,0,24) $$
        OutFmt_g      : PsiFixFmt_t := (1, 0, 20); -- Output Fixed Point format                                         $$ constant=(1,0,20) $$
        Round_g       : PsiFixRnd_t := PsiFixRound; --                                                                  $$ constant=PsiFixRound $$
        Sat_g         : PsiFixSat_t := PsiFixSat; --                                                                    $$ constant=PsiFixSat $$
        InAIsCplx_g   : boolean     := true;
        InBIsCplx_g   : boolean     := true
    );
    port(
        InClk       : in  std_logic;      -- clk                                                                            $$ type=clk; freq=100e6 $$
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
architecture rtl of psi_fix_complex_mult_3m is
    
    -- Constants
    constant PreAddAFmt_c   : PsiFixFmt_t := (InAFmt_g.S, InAFmt_g.I + 1, InAFmt_g.F);
    constant PreAddBFmt_c   : PsiFixFmt_t := (InBFmt_g.S, InBFmt_g.I + 1, InBFmt_g.F);
    constant MultFmt_c      : PsiFixFmt_t := (max(InAFmt_g.S, InBFmt_g.S), InAFmt_g.I + InBFmt_g.I + 2, InAFmt_g.F + InBFmt_g.F);
    constant PostAddFmt_c   : PsiFixFmt_t := (MultFmt_c.S, MultFmt_c.I + 1, MultFmt_c.F);
    constant RndFmt_c       : PsiFixFmt_t := (PostAddFmt_c.S, PostAddFmt_c.I + 1, OutFmt_g.F);

    -- Two process method
    type two_process_r is record
        VldPipe                 : std_logic_vector(0 to 7);
        InIADat_0               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_0               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InIBDat_0               : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InQBDat_0               : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InIADat_1               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_1               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InIBDat_1               : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InQBDat_1               : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InIADat_2               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_2               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InIBDat_2               : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InQBDat_2               : std_logic_vector(PsiFixSize(InBFmt_g) - 1 downto 0);
        InIADat_3               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        InQADat_3               : std_logic_vector(PsiFixSize(InAFmt_g) - 1 downto 0);
        PreSubIQA_1             : std_logic_vector(PsiFixSize(PreAddAFmt_c) - 1 downto 0);
        PreSubIQB_1             : std_logic_vector(PsiFixSize(PreAddBFmt_c) - 1 downto 0);
        PreAddIQB_1             : std_logic_vector(PsiFixSize(PreAddBFmt_c) - 1 downto 0);
        PreSubIQB_3             : std_logic_vector(PsiFixSize(PreAddBFmt_c) - 1 downto 0);
        PreAddIQB_3             : std_logic_vector(PsiFixSize(PreAddBFmt_c) - 1 downto 0);
        Mult_PreSubIQA_QB_2     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        Mult_PreSubIQB_IA_2     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        Mult_PreAddIQB_QA_2     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        Mult_PreSubIQA_QB_3     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        Mult_PreSubIQA_QB_4     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        Mult_PreSubIQB_IA_4     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        Mult_PreAddIQB_QA_4     : std_logic_vector(PsiFixSize(MultFmt_c) - 1 downto 0);
        SumI_3                  : std_logic_vector(PsiFixSize(PostAddFmt_c) - 1 downto 0);
        SumQ_3                  : std_logic_vector(PsiFixSize(PostAddFmt_c) - 1 downto 0);
        SumI_5                  : std_logic_vector(PsiFixSize(PostAddFmt_c) - 1 downto 0);
        SumQ_5                  : std_logic_vector(PsiFixSize(PostAddFmt_c) - 1 downto 0);
        RndI                    : std_logic_vector(PsiFixSize(RndFmt_c) - 1 downto 0);
        RndQ                    : std_logic_vector(PsiFixSize(RndFmt_c) - 1 downto 0);
        OutI                    : std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0);
        OutQ                    : std_logic_vector(PsiFixSize(OutFmt_g) - 1 downto 0);
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
        
        -- *** Stage 0 ***
        v.VldPipe(0) := InVld;
        v.InIADat_0  := InIADat;
        v.InQADat_0  := InQADat;
        v.InIBDat_0  := InIBDat;
        v.InQBDat_0  := InQBDat;
        
        -- *** Stage 1 ***
        v.VldPipe(1) := r.VldPipe(0);
        if InAIsCplx_g then 
            v.PreSubIQA_1 := PsiFixSub(r.InIADat_0, InAFmt_g, r.InQADat_0, InAFmt_g, PreAddAFmt_c, PsiFixTrunc, PsiFixWrap); -- Pre-substraction common term
        else
            v.PreSubIQA_1 := PsiFixResize(r.InIADat_0, InAFmt_g, PreAddAFmt_c, PsiFixTrunc, PsiFixWrap);
        end if;
        v.InIADat_1  := r.InIADat_0;
        v.InQADat_1  := r.InQADat_0;
        v.InQBDat_1  := r.InQBDat_0;
        if Pipeline_g then  
            v.InIBDat_1  := r.InIBDat_0;  
        else
            -- Pre-additions/substractions specific of real and imaginary parts
            if InBIsCplx_g then 
                v.PreSubIQB_1 := PsiFixSub(r.InIBDat_0, InBFmt_g, r.InQBDat_0, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
                v.PreAddIQB_1 := PsiFixAdd(r.InIBDat_0, InBFmt_g, r.InQBDat_0, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
            else
                v.PreSubIQB_1 := PsiFixResize(r.InIBDat_0, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
                v.PreAddIQB_1 := PsiFixResize(r.InIBDat_0, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
            end if;
        end if;
        
        -- *** Stage 2 ***
        v.VldPipe(2) := r.VldPipe(1);
        if InBIsCplx_g then -- Multiplication common term
            v.Mult_PreSubIQA_QB_2 := PsiFixMult(r.PreSubIQA_1, PreAddAFmt_c, r.InQBDat_1, InBFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
        else
            v.Mult_PreSubIQA_QB_2 := (others => '0');
        end if;
        if Pipeline_g then 
            v.InIADat_2  := r.InIADat_1;
            v.InQADat_2  := r.InQADat_1;
            v.InIBDat_2  := r.InIBDat_1;
            v.InQBDat_2  := r.InQBDat_1;
        else
            -- Multiplications specific of real and imaginary parts
            v.Mult_PreSubIQB_IA_2 := PsiFixMult(r.PreSubIQB_1, PreAddBFmt_c, r.InIADat_1, InAFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
            if InAIsCplx_g then 
                v.Mult_PreAddIQB_QA_2 := PsiFixMult(r.PreAddIQB_1, PreAddBFmt_c, r.InQADat_1, InAFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
            else
                v.Mult_PreAddIQB_QA_2 := (others => '0');
            end if;
        end if;
        
        -- *** Stage 3 ***
        v.VldPipe(3) := r.VldPipe(2);
        if Pipeline_g then 
            v.InIADat_3  := r.InIADat_2;
            v.InQADat_3  := r.InQADat_2;
            -- Pre-additions/substractions specific of real and imaginary parts
            if InBIsCplx_g then
                v.PreSubIQB_3 := PsiFixSub(r.InIBDat_2, InBFmt_g, r.InQBDat_2, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
                v.PreAddIQB_3 := PsiFixAdd(r.InIBDat_2, InBFmt_g, r.InQBDat_2, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap); 
            else
                v.PreSubIQB_3 := PsiFixResize(r.InIBDat_2, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
                v.PreAddIQB_3 := PsiFixResize(r.InIBDat_2, InBFmt_g, PreAddBFmt_c, PsiFixTrunc, PsiFixWrap);
            end if;
            v.Mult_PreSubIQA_QB_3 := r.Mult_PreSubIQA_QB_2;
        else
            -- Post-additions
            v.SumI_3 := PsiFixAdd(r.Mult_PreSubIQA_QB_2, MultFmt_c, r.Mult_PreSubIQB_IA_2, MultFmt_c, PostAddFmt_c, PsiFixTrunc, PsiFixWrap); 
            v.SumQ_3 := PsiFixAdd(r.Mult_PreSubIQA_QB_2, MultFmt_c, r.Mult_PreAddIQB_QA_2, MultFmt_c, PostAddFmt_c, PsiFixTrunc, PsiFixWrap); 
        end if;
        
        -- *** Stage 4 ***
        if Pipeline_g then 
            v.VldPipe(4) := r.VldPipe(3);
            v.Mult_PreSubIQA_QB_4 := r.Mult_PreSubIQA_QB_3;
            -- Multiplications specific of real and imaginary parts
            v.Mult_PreSubIQB_IA_4 := PsiFixMult(r.PreSubIQB_3, PreAddBFmt_c, r.InIADat_3, InAFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
            if InAIsCplx_g then 
                v.Mult_PreAddIQB_QA_4 := PsiFixMult(r.PreAddIQB_3, PreAddBFmt_c, r.InQADat_3, InAFmt_g, MultFmt_c, PsiFixTrunc, PsiFixWrap);
            else
                v.Mult_PreAddIQB_QA_4 := (others => '0');
            end if;
        end if;
        
        -- *** Stage 5 ***
        if Pipeline_g then 
            v.VldPipe(5) := r.VldPipe(4);
            -- Post-additions
            v.SumI_5 := PsiFixAdd(r.Mult_PreSubIQA_QB_4, MultFmt_c, r.Mult_PreSubIQB_IA_4, MultFmt_c, PostAddFmt_c, PsiFixTrunc, PsiFixWrap); 
            v.SumQ_5 := PsiFixAdd(r.Mult_PreSubIQA_QB_4, MultFmt_c, r.Mult_PreAddIQB_QA_4, MultFmt_c, PostAddFmt_c, PsiFixTrunc, PsiFixWrap); 
        end if;
        
        -- *** Resize (outside DSP slice, no pipeline numbering as its length is variable depending on Pipeline_g) ***
        if Pipeline_g then
            v.VldPipe(6) := r.VldPipe(5);
            v.RndI   := PsiFixResize(r.SumI_5, PostAddFmt_c, RndFmt_c, Round_g, PsiFixWrap); 
            v.RndQ   := PsiFixResize(r.SumQ_5, PostAddFmt_c, RndFmt_c, Round_g, PsiFixWrap); 
            v.VldPipe(7) := r.VldPipe(6);
            v.OutI   := PsiFixResize(r.RndI, RndFmt_c, OutFmt_g, PsiFixTrunc, Sat_g);
            v.OutQ   := PsiFixResize(r.RndQ, RndFmt_c, OutFmt_g, PsiFixTrunc, Sat_g);
        else
            v.VldPipe(4) := r.VldPipe(3);
            v.OutI   := PsiFixResize(r.SumI_3, PostAddFmt_c, OutFmt_g, Round_g, Sat_g);
            v.OutQ   := PsiFixResize(r.SumQ_3, PostAddFmt_c, OutFmt_g, Round_g, Sat_g);
        end if;

        -- *** Assign to signal ***
        r_next <= v;

    end process;

    --------------------------------------------
    -- Outputs
    --------------------------------------------
    g_pl : if Pipeline_g generate
        OutVld <= r.VldPipe(7); -- Latency 8 clock cycles
    end generate;
    g_npl : if not Pipeline_g generate
        OutVld <= r.VldPipe(4); -- Latency 5 clock cycles
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
            end if;
        end if;
    end process;

end architecture;
