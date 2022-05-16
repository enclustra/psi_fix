########################################################################################################################
#  Copyright (c) 2018 by Paul Scherrer Institute, Switzerland
#  All rights reserved.
#  Authors: Oliver Bruendler
########################################################################################################################

########################################################################################################################
# Imports
########################################################################################################################
from psi_fix_pkg import *
import numpy as np
from scipy.signal import lfilter

########################################################################################################################
# FIR Filter Model
########################################################################################################################
class psi_fix_fir:
    """
    General model of a fixed point FIR filter. The model represents any bittrue implementation of a FIR, independently
    of tis RTL implementation (multi-channel, serial/parallel, etc.).

    It is assumed that the accumulator never wraps ans rounding/saturatio only happens at the output (accumulator would wrap)
    """

    ####################################################################################################################
    # Constructor
    ####################################################################################################################
    def __init__(self,  inFmt : PsiFixFmt,
                        outFmt : PsiFixFmt,
                        coefFmt : PsiFixFmt):
        """
        Constructor for the FIR model object
        :param inFmt: Input fixed-point format
        :param outFmt: Output fixed-point format
        :param coefFmt: Coefficient fixed-point format
        """
        self.inFmt = inFmt
        self.outFmt = outFmt
        self.coefFmt = coefFmt
        self.accuFmt = PsiFixFmt(1, outFmt.I + 1, inFmt.F + coefFmt.F)
        self.roundFmt = PsiFixFmt(self.accuFmt.S, self.accuFmt.I, self.outFmt.F)

    ####################################################################################################################
    # Public Methods and Properties
    ####################################################################################################################
    def Filter(self, inp : np.ndarray, decimRate : int, coefficients : np.ndarray):
        """
        Filter data without detection of saturation
        :param inp: Input data
        :param decimRate: Decimation ratio of the FIR filter
        :param coefficients: filter coefficients
        :return: Output data
        """
        sat, outp = self.FilterSatDetect(inp, decimRate, coefficients)
        return outp

    def FilterSatDetect(self, inp : np.ndarray, decimRate : int, coefficients : np.ndarray):
        """
        Filter data with detection of saturation
        :param inp: Input data
        :param decimRate: Decimation ratio of the FIR filter
        :param coefficients: Filter coefficients
        :return: Output data as tuple (sat, outp) where SAT is a boolean that indicates saturation and OUTP is the
                 output data.
        """
        # Force integer (MATLAB may pass 1.0 as float)
        decimRate = int(decimRate)
        # Make input fixed point
        inp = PsiFixFromReal(inp, self.inFmt)
        coefs = PsiFixFromReal(coefficients, self.coefFmt)
        # Filter
        res = lfilter(coefs, 1, inp)
        # Throw an error if an overflow is detected for 2 reasons:
        # 1) It is important for the user to know about the overflow because they must fix it.
        # 2) Not all VHDL implementations match the bit-true model when overflow occurs.
        ovf = np.zeros(res.size)
        ovf = np.where(res > PsiFixUpperBound(self.roundFmt), 1, ovf)
        ovf = np.where(res < PsiFixLowerBound(self.roundFmt), 1, ovf)
        if np.any(ovf):
            raise ValueError("psi_fix_fir : Internal overflow. The user must set suitable formats. See documentation.")
        # Round and truncate (wrap)
        resRnd = PsiFixResize(res, self.accuFmt, self.roundFmt, PsiFixRnd.Round)
        # Decimate
        resDec = resRnd[::decimRate]
        # Check saturation
        sat = np.zeros(resDec.size)
        sat = np.where(resDec > PsiFixUpperBound(self.outFmt), 1, sat)
        sat = np.where(resDec < PsiFixLowerBound(self.outFmt), 1, sat)
        # Output
        outp = PsiFixResize(resDec, self.roundFmt, self.outFmt, PsiFixRnd.Trunc, PsiFixSat.Sat)  # No rounding since no fractional bits must be removed.
        return (sat, outp)
