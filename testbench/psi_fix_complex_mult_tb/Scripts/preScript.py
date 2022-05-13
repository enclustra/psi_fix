###################################################################################################
# Copyright(c) 2022 Enclustra GmbH, Switzerland (info@enclustra.com)
###################################################################################################
import sys
sys.path.append("../../../model")
import numpy as np
from psi_fix_pkg import *
from psi_fix_complex_mult import psi_fix_complex_mult
from matplotlib import pyplot as plt
import scipy.signal as sps
import os

STIM_DIR = os.path.dirname(os.path.abspath(__file__)) + "/../Data"
RAND_SAMPLES = 10000

PLOT_ON = False

try:
    os.mkdir(STIM_DIR)
except FileExistsError:
    pass

###################################################################################################
# Simulation
###################################################################################################
inAFmt = PsiFixFmt(1, 0, 16) # Max 25(18) and 17 bit-widths for 3 and 4 mult archs to efficient DSP slice map (Xilinx)
inBFmt = PsiFixFmt(1, 0, 16) # Max 18(25) and 17 bit-widths for 3 and 4 mult archs to efficient DSP slice map (Xilinx)
outFmt = PsiFixFmt(1, 0, 20)

sigRot = np.exp(2j*np.pi*np.linspace(0, 1, 360))*0.99
sigRamp = np.linspace(0.5, 0.9, 360)
sigRandA = (np.random.rand(RAND_SAMPLES)+1j*np.random.rand(RAND_SAMPLES))*2-1-1j
sigRandB = (np.random.rand(RAND_SAMPLES)+1j*np.random.rand(RAND_SAMPLES))*2-1-1j

sigA = np.concatenate((sigRot, sigRamp, sigRandA))
sigB = np.concatenate((sigRamp, sigRot, sigRandB))

sigAI = PsiFixFromReal(sigA.real, inAFmt, errSat=False)
sigAQ = PsiFixFromReal(sigA.imag, inAFmt, errSat=False)
sigBI = PsiFixFromReal(sigB.real, inAFmt, errSat=False)
sigBQ = PsiFixFromReal(sigB.imag, inAFmt, errSat=False)

mult3 = psi_fix_complex_mult(inAFmt, inBFmt, outFmt, PsiFixRnd.Round, PsiFixSat.Sat, False)
mult4 = psi_fix_complex_mult(inAFmt, inBFmt, outFmt, PsiFixRnd.Round, PsiFixSat.Sat)
res3I, res3Q = mult3.Process(sigAI, sigAQ, sigBI, sigBQ)
res4I, res4Q = mult4.Process(sigAI, sigAQ, sigBI, sigBQ)

###################################################################################################
# Plot (if required)
###################################################################################################
if PLOT_ON:
    fig, ax = plt.subplots(1, 1)
    plt.plot(res3I, marker='o', label='3 multiplications', color='b')
    plt.plot(res4I, marker='x', label='4 multiplications', color='r')
    ax.set_title('Real Output')
    ax.set_xlabel("Sample")
    ax.set_ylabel("Amplitude")
    fig, ax = plt.subplots(1, 1)
    plt.plot(res3Q, marker='o', label='3 multiplications', color='b')
    plt.plot(res4Q, marker='x', label='4 multiplications', color='r')
    ax.set_title('Imag Output')
    ax.set_xlabel("Sample")
    ax.set_ylabel("Amplitude")
    ax.legend()
    plt.show()

###################################################################################################
# Write Files for Co sim
###################################################################################################
np.savetxt(STIM_DIR + "/input.txt",
           np.column_stack((PsiFixGetBitsAsInt(sigAI, inAFmt),
                            PsiFixGetBitsAsInt(sigAQ, inAFmt),
                            PsiFixGetBitsAsInt(sigBI, inBFmt),
                            PsiFixGetBitsAsInt(sigBQ, inBFmt))),
           fmt="%i", header="ai aq bi bq")
np.savetxt(STIM_DIR + "/output3m.txt",
           np.column_stack((PsiFixGetBitsAsInt(res3I, outFmt),
                            PsiFixGetBitsAsInt(res3Q, outFmt))),
           fmt="%i", header="result-I result-Q")
np.savetxt(STIM_DIR + "/output4m.txt",
           np.column_stack((PsiFixGetBitsAsInt(res4I, outFmt),
                            PsiFixGetBitsAsInt(res4Q, outFmt))),
           fmt="%i", header="result-I result-Q")
