function [pcZPX2,pcMIP,COV,cov_inv,cov_rev,opt,iter] = NMSA_to_pcZPX2(nmsa,Lmat)
% This function calculates the partial correlation matrix for the columns
% of an MSA. The MSA is first converted to its binary 'long' representation
% in which every column is extended into 21 different columns, each one
% representing a different aa. Then, the covariance matrix is calculated
% and is shrunk to the equivalent covariance matrix for the 'short'
% standard representation. Finally, the QUIC method is used to invert the
% covariance matrix. Lmat is a value between 1 and 0 controlling the
% 'sparseness' of the concentration matrix (smaller values produce a less
% sparse inverse, and take more time. Larger values increase the
% sparseness, with the inverse ultimately being populated only in the
% diagonal). The default value of Lmat is 0.06. Lmat can also be a
% regularization matrix of the same dimensions as the covariance matrix to
% be inverted. Simplest usage: [pcZPX2] = NMSA_to_pcZPX2(nmsa);

bin_ordered = nmsa_to_binmsa_21q(nmsa);

[~,ncols] = size(bin_ordered);
bin_ordered_sum = sum(bin_ordered);
bin_ordered_ind = find(bin_ordered_sum);

% Here we calculate the COV matrix only for the indices included in the
% vector 'bin_ordered_ind'.

    gCOV = zeros(ncols,ncols);
    ogCOV = cov(bin_ordered(:,bin_ordered_ind));
    gCOV(bin_ordered_ind,bin_ordered_ind) = ogCOV;
    
    % Here we recover the original values of nrows and ncols

    [~,ncols] = size(nmsa);
    COV = zeros(ncols,ncols);
    for oi = 1:ncols
        i = 21*(oi-1) + 1;
        for oj = oi:ncols
            j = 21*(oj-1)+1;
            % Frobenius norm
            COV(oi,oj) = norm(gCOV(i:i+20,j:j+20),'fro');
            % Spectral norm
            % subcov = gCOV(i:i+20,j:j+20);
            % [~,COV(oi,oj),~] =svds(subcov,1);
            % L1 norm
            % COV(oi,oj) = norm(gCOV(i:i+20,j:j+20),1);
            % Simple sum
            % COV(oi,oj) = sum(sum(gCOV(i:i+20,j:j+20)));
            COV(oj,oi) = COV(oi,oj);
        end
    end
    
    % Lmat = 0.06 % default value
    
    if exist('Lmat','var')
    else
        Lmat = 0.06;
    end
    
    [cov_inv cov_rev opt cputime iter dGap] = QUIC('default', COV, Lmat, 1e-6, 2, 200);
    
    rho = zeros(ncols,ncols);
    for i = 1:ncols
        for j = i:ncols
            rho(i,j) = -cov_inv(i,j)/sqrt(cov_inv(i,i)*cov_inv(j,j));
            rho(j,i) = rho(i,j);
        end
    end
    
    % MIP matrix
    pcMIP = MI_to_MIP(rho,ncols);

    % and finally ZPX2 matrix
    pcZPX2 = MIP_to_ZPX2(pcMIP,ncols);
    
    pcZPX2 = real(pcZPX2);
    
end


function [pcorr] = pcorr(nmsa,ncols)
% This function calculate a matrix of partial correlation coefficients for
% the columns of the binary msa.
nmsa = +nmsa;
sum_col_vec = sum(nmsa,2);
nC = sum_col_vec/norm(sum_col_vec);
% cC = sum_col_vec - mean(sum_col_vec);
% nC = cC/norm(cC);
% pcorr = NaN(ncols,ncols);
pcorr = zeros(ncols,ncols);
for i = 1:ncols
    A = nmsa(:,i);
    pA = A - (A'*nC)*nC;
    cpA = pA - mean(pA);
    ncpA = cpA/norm(cpA);
    for j = i:ncols
        B = nmsa(:,j);
        pB = B - (B'*nC)*nC;
        cpB = pB - mean(pB);
        ncpB = cpB/norm(cpB);
        pcorr(i,j) = ncpA'*ncpB;
        pcorr(j,i) = pcorr(i,j);
    end
end 
end


function [binmsa] = nmsa_to_binmsa_21q(nmsa)
% Returns each sequence of length L as a vector of size 21L with 0 and 1. 
% Number 21 represents gaps in the Matlab numeric representation of an MSA.

[nseq,npos]=size(nmsa);
ind25 = nmsa == 25;
nmsa(ind25) = 21;
binmsa=zeros(nseq,21*npos);
for i=1:npos 
    for aa=1:21 
        binmsa(:,21*(i-1)+aa)=(nmsa(:,i)==aa); 
    end; 
end;
end


function [pMIP] = MI_to_MIP(pMI,ncols)
%--------------------------------------------------------------------------
% MIP calculation
mean_mat = nanmean(pMI(:));
mean_row = zeros(ncols,1);
MCA_mat = zeros(ncols,ncols);

% Here  we calculate the MCA matrix.

for m = 1:ncols
    mean_row(m) = nanmean(pMI(m,:));
end

for m = 1:ncols
    for n = m:ncols
    MCA_mat(m,n)=(mean_row(m)*mean_row(n))/mean_mat;
    MCA_mat(n,m) = MCA_mat(m,n);    
    end
MCA_mat(m,m) = NaN;
end

% Finally we subtract the MCA matrix from the MI matrix.
pMIP = pMI-MCA_mat;

end


function [pZPX2] = MIP_to_ZPX2(pMIP,ncols)
%--------------------------------------------------------------------------
% ZPX2 calculation
mean_row=zeros(ncols,1);
std_row=zeros(ncols,1);
pZPX2=zeros(ncols,ncols);

for m=1:ncols
    mean_row(m)=nanmean(pMIP(m,:));
    std_row(m)=nanstd(pMIP(m,:));   
end
for m=1:ncols
    for n=m:ncols

    ZPX2_i=(pMIP(m,n)-mean_row(m))/std_row(m);
    ZPX2_j=(pMIP(m,n)-mean_row(n))/std_row(n);
        
    pZPX2(m,n)=ZPX2_i*ZPX2_j;

% Here we correct for the product of two negative ZPX2_i and ZPX2_j, which
% would give the wrong MI. Comment: I am not sure the following three lines
% make a difference. Change of sign is not in the original ZPX2 algorithm by
% Gloor, but is included in the ZRES algorithm by Chen. At any rate the
% change of sign seems to affect only i,j positions with very small counts,
% and therefore the final effect of the change is marginal.
    
%     if (ZPX2_i<0&&ZPX2_j<0)
%         pZPX2(m,n)=-pZPX2(m,n);
%     end

% Symmetrize.

    pZPX2(n,m)=pZPX2(m,n);
    
    end
    
    pZPX2(m,m)=NaN;

end
end


