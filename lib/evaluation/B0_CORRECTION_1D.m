function [Mz_corr]=B0_CORRECTION_1D(Z,dB0,P)
% B0_CORRECTION_1D applies B0 correction to a 1D Z-spectrum.
%
% This function takes an input Z-spectrum and corrects it for B0 field inhomogeneities based on the provided inhomogeneity dB0.
% It uses interpolation to shift the spectrum according to the inhomogeneity and provides the corrected spectrum.
%
% INPUTS:
%   Z       - A vector representing the Z-spectrum signal intensities.
%   dB0     - A value representing the B0 field inhomogeneity (in ppm) for each point of the Z-spectrum.
%   P       - A structure containing parameters related to the evaluation and sequence, specifically:
%             P.EVAL.B0_int_meth: Method used for interpolation (e.g., 'linear', 'spline', 'cubic', 'pchip').
%             P.EVAL.w_interp: Frequency offsets for interpolation.
%             P.SEQ.w: Original frequency offsets of the Z-spectrum.
%
% OUTPUTS:
%   Mz_corr - A vector containing the corrected Z-spectrum after interpolation.
%
% The function allows for different interpolation methods, which can be specified in P.EVAL.B0_int_meth. If the method is set
% to 'linspline', the correction is computed using a combination of linear and spline interpolation.

% Set interpolation method (default is 'linspline')
try
    B0_int_meth=P.EVAL.B0_int_meth;
catch
    B0_int_meth='linspline'; % i.e. linspline, linear, spline,cubic,pchip
end;
w_interp=P.EVAL.w_interp;
x_Zspec_ppm=P.SEQ.w;





try
    if strcmp(B0_int_meth,'linspline')
        Mz_corr = (interp1(x_Zspec_ppm-dB0,Z,w_interp,'linear','extrap')+interp1(x_Zspec_ppm-dB0,Z,w_interp,'spline','extrap'))/2;
    else
        Mz_corr = interp1(x_Zspec_ppm-dB0,Z,w_interp,B0_int_meth,'extrap');
    end
    

catch MS
    warning('B0 correction failed during interpolation');
    rethrow(MS)
end


