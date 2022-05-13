###################################################################################################
# Copyright(c) 2022 Enclustra GmbH, Switzerland (info@enclustra.com)
###################################################################################################

###################################################################################################
# Imports
###################################################################################################
from psi_fix_pkg import *

###################################################################################################
# Complex Multiplication model
###################################################################################################
class psi_fix_complex_mult:

    ###############################################################################################
    # Constructor
    ###############################################################################################
    def __init__(self, inAFmt: PsiFixFmt,
                 inBFmt: PsiFixFmt,
                 outFmt : PsiFixFmt,
                 rnd : PsiFixRnd = PsiFixRnd.Round,
                 sat : PsiFixSat = PsiFixSat.Sat,
                 mult4: bool = True):
        """
        Creation of a complex multiplication model
        :param inAFmt: Input A fixed point format
        :param inBFmt: Input B fixed point format
        :param outFmt: Output fixed point format
        :param rnd: Rounding mode at the output
        :param sat: Saturation mode at the output
        :param mult4: Maximum number of real multiplications used (False = 3, True = 4 (default))
        """
        self.inAFmt = inAFmt
        self.preAddAFmt = PsiFixFmt(inAFmt.S, inAFmt.I+1, inAFmt.F)
        self.inBFmt = inBFmt
        self.preAddBFmt = PsiFixFmt(inBFmt.S, inBFmt.I+1, inBFmt.F)
        self.mult4Fmt = PsiFixFmt(max(inAFmt.S, inBFmt.S), inAFmt.I+inBFmt.I+1, inAFmt.F+inBFmt.F)
        self.mult3Fmt = PsiFixFmt(self.mult4Fmt.S, self.mult4Fmt.I+1, self.mult4Fmt.F)
        self.outFmt = outFmt
        self.rnd = rnd
        self.sat = sat
        self.mult4 = mult4

    ###############################################################################################
    # Public functions
    ###############################################################################################
    def Process(self, ai, aq, bi, bq):
        """
        Process data using the complex multiplication model

        :param ai: Input A, real-part
        :param aq: Input A, imaginary-part
        :param bi: Input B, real-part
        :param bq: Input B, imaginary part
        :return: Result tuple (I, Q)
        """
        
        aif = PsiFixFromReal(ai, self.inAFmt)
        aqf = PsiFixFromReal(aq, self.inAFmt)
        bif = PsiFixFromReal(bi, self.inBFmt)
        bqf = PsiFixFromReal(bq, self.inBFmt)
        
        if self.mult4:
            # Multiplications
            multIQ = PsiFixMult(aif, self.inAFmt, bqf, self.inBFmt, self.mult4Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            multQI = PsiFixMult(aqf, self.inAFmt, bif, self.inBFmt, self.mult4Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            multII = PsiFixMult(aif, self.inAFmt, bif, self.inBFmt, self.mult4Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            multQQ = PsiFixMult(aqf, self.inAFmt, bqf, self.inBFmt, self.mult4Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)

            #Summations
            sumI = PsiFixSub(multII, self.mult4Fmt, multQQ, self.mult4Fmt, self.outFmt, self.rnd, self.sat)
            sumQ = PsiFixAdd(multIQ, self.mult4Fmt, multQI, self.mult4Fmt, self.outFmt, self.rnd, self.sat)
        else:
            # Common term
            subA = PsiFixSub(aif, self.inAFmt, aqf, self.inAFmt, self.preAddAFmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)   # preadder within Xilinx 7 series DSP slices features:
                                                                                                                       # - 24-bit two complement operands
                                                                                                                       # - 25-bit output
                                                                                                                       # - no saturation logic
            multSubAQ = PsiFixMult(subA, self.preAddAFmt, bqf, self.inBFmt, self.mult3Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
        
            # real part
            subB = PsiFixSub(bif, self.inBFmt, bqf, self.inBFmt, self.preAddBFmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            multSubBI = PsiFixMult(subB, self.preAddBFmt, aif, self.inAFmt, self.mult3Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            sumI = PsiFixAdd(multSubAQ, self.mult3Fmt, multSubBI, self.mult3Fmt, self.outFmt, self.rnd, self.sat)

            # imaginary part
            sumB = PsiFixAdd(bif, self.inBFmt, bqf, self.inBFmt, self.preAddBFmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            multSumBQ = PsiFixMult(sumB, self.preAddBFmt, aqf, self.inAFmt, self.mult3Fmt, PsiFixRnd.Trunc, PsiFixSat.Wrap)
            sumQ = PsiFixAdd(multSubAQ, self.mult3Fmt, multSumBQ, self.mult3Fmt, self.outFmt, self.rnd, self.sat)

        return sumI, sumQ
