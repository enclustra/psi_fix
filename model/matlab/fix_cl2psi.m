%-----------------------------------------------------------------------------
%  Copyright (c) 2020 by Enclustra, Switzerland
%  All rights reserved.
%  Authors: Oliver Bruendler
%-----------------------------------------------------------------------------
%
% Function to convert a en_cl_fix fixed point format to psi_fix convention.
%
% cl    Fixed point format according to en_cl_fix
% psi   Fixed point format according to psi_fix
%
function psi = fix_cl2psi(cl)
    psi = py.psi_fix_pkg.PsiFixFmt(int32(cl.S), int32(cl.I), int32(cl.F));
end