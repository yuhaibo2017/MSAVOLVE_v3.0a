function [pcZPX2,pcMIP,ppvZPX2,ppvMIP,gCOV,cov_inv,rho,COV,sCOV,lambda] = ...
    NMSA_to_PSICOV_2(nmsa,dist_method,threshold,psc_lambda,nsymbols,jump,...
    cov_diag,s_cov_diag,recov_method,Lmat,lambda,delta,inverse_method,pc_method)
% Matlab experimental implementations of the PSICOV algorithm. It differs
% from NMSA_to_PSICOV for a different treatment of the parameters
% 'nsymbols' and 'jump'. The choice of the distance method affects the
% inclusion ('GAPS') or exclusion ('NOGAPS') of gaps in the calculation of
% the similarity between sequences. A 'threshold' is applied for the
% similarity between sequences. A pseudocount (psc_lambda) is also applied
% based on the number of symbols (nsymbols) desired (20 or 21). The MSA is
% first converted to its binary 'long' representation in which every column
% is extended into 20 (jump = 20) or 21 (jump = 21) different columns, each
% one representing a different aa.Then, the covariance matrix is calculated
% and is converted to the equivalent covariance matrix for the 'short'
% standard representation. Before this conversion it is possible to keep
% (cov_diag = 'KEEP') or zero (cov_diag = 'ZERO') [recommended] the
% diagonal of the large covariance matrix. We can also zero (s_cov_diag =
% 'ZERO') or keep (s_cov_diag = 'KEEP') the diagonal of the sub-covariance
% matrix. The conversion to the 'short' format can be carried out by taking
% the Frobenius norm (recov_method = 'FRO') or the L1 norm (recov_method =
% 'L1') of each submatrix. The value of jump clearly determines whether we
% include or not gaps in the calculation of the 'short' covariance matrix
% (jump = 21 includes gaps; jump = 20 excludes gaps). Finally, an inverse
% method is used to invert the covariance matrix. Three option are
% available for this purpose: standard 'INVERSE', 'GLASSO', or 'QUIC'. Lmat
% is a value between 1 and 0 controlling the 'sparseness' of the
% concentration matrix (smaller values produce a less sparse inverse, and
% take more time. Larger values increase the sparseness, with the inverse
% ultimately being populated only in the diagonal). The default value of
% Lmat is 0.02. Suitable ranges are between 0.025 and 0.005. Lmat can also
% be a regularization matrix of the same dimensions as the covariance
% matrix to be inverted. 'lambda' and 'delta' define the conditioning of
% the covariance matrix prior to the calculation of the sparse inverse. The
% recommended values are lambda = 0.0 and delta = 0.0001. Larger values of
% lambda and delta will make the calculation of the inverse faster, but
% possibly less accurate. 'pc_method' determines whether we calculate the
% MIP matrix from the inverse covariance or from the RHO matrix. It appears
% to affects only the sign of the MIP matrix, but not that of the ZPX2
% matrix. The ppvZPX2 and ppvMIP matrices include the correction produced
% by the application of a logistic fit to the MIP data.
% For best results with all pairs use the syntax:
% [~,~,ppvZPX2,~] = NMSA_to_PSICOV_2(nmsa,'NOGAPS',0.62,1.0,21,21,...
%    'ZERO','KEEP','FRO',0.005,0.0,0.0001,'QUIC','RHO');toc
% For best results with pairs separated by at least 20 residues in sequence 
% use the syntax:
% [~,~,ppvZPX2,~] = NMSA_to_PSICOV_2(nmsa,'NOGAPS',0.62,1.0,21,20,...
%    'ZERO','KEEP','FRO',0.005,0.0,0.0001,'QUIC','RHO');toc

[nrows,ncols] = size(nmsa);

switch dist_method
    case 'NOGAPS'
        bin_ordered = nmsa_to_binmsa_20q(nmsa);
        dist = bin_ordered*bin_ordered';

        sdist = zeros(nrows,nrows);      
        for i = 1:nrows
            sdist(i,:) = dist(i,:)/dist(i,i);
        end

        udist = triu(sdist,1);
        ldist = tril(sdist,-1)';
        lind = udist < ldist;
        udist(lind) = 0;
        ldist(~lind) = 0;
        mdist = udist + ldist;
        dist = mdist + mdist' + eye(nrows);
        
    case 'GAPS'
        bin_ordered = nmsa_to_binmsa_21q(nmsa);
        dist = (bin_ordered*bin_ordered')/ncols;
end

if jump == 20
    bin_ordered = nmsa_to_binmsa_20q(nmsa);
else
    bin_ordered = nmsa_to_binmsa_21q(nmsa);
end

[nrows,ncols] = size(bin_ordered);

% Here we apply the weights for the similarity between sequences.
bin_ordered_sum = sum(bin_ordered);
bin_ordered_ind = find(bin_ordered_sum);
n_bin_ordered_ind = length(bin_ordered_ind);

if threshold == 1
    W = ones(nrows,1);
    Meff = nrows;
else
    dist_threshold = dist >= threshold;
    W = 1./sum(dist_threshold)';
    Meff=round(sum(W));
end

fprintf('Meff = %d \n', Meff);

W_mat = repmat(W,1,length(bin_ordered_ind));
loq = psc_lambda/nsymbols;
loq2 = psc_lambda/nsymbols^2;
l_Meff = psc_lambda + Meff;
w_bin_ordered = W_mat.*bin_ordered(:,bin_ordered_ind);
s_bin_ordered = bin_ordered(:,bin_ordered_ind);
Fi = (loq + sum(w_bin_ordered))/l_Meff;
Fij = zeros(n_bin_ordered_ind);
ogCOV = zeros(n_bin_ordered_ind);
gCOV = zeros(ncols,ncols);

for i = 1:n_bin_ordered_ind
    for j = i:n_bin_ordered_ind
        Fij(i,j) = (loq2 + sum(w_bin_ordered(:,i) ...
            .* s_bin_ordered(:,j)))/l_Meff;
        Fij(j,i) = Fij(i,j);
        ogCOV(i,j) = Fij(i,j) - Fi(i)*Fi(j);
        ogCOV(j,i) = ogCOV(i,j);
    end
end

gCOV(bin_ordered_ind,bin_ordered_ind) = ogCOV;

% Here we can zero the diagonal of the large covariance matrix

switch cov_diag
    case 'ZERO'
        for i = 1:ncols
            gCOV(i,i) = 0;
        end
    case 'KEEP'
end
        
    % Here we recover the original values of nrows and ncols
    shift = jump - 1;    
    [~,ncols] = size(nmsa);
    COV = zeros(ncols,ncols);
    for oi = 1:ncols
        i = jump*(oi-1) + 1;
        for oj = oi:ncols
            j = jump*(oj-1)+1;
            
            % Here we define the submatrix 
            subcov = gCOV(i:i+shift,j:j+shift);
            
            switch s_cov_diag
                case 'ZERO'
                % and zero its diagonal
                for k = 1:jump
                    subcov(k,k) = 0;
                end
                case 'KEEP'
            end
            
            switch recov_method
                case 'FRO'
                % Frobenius norm
                COV(oi,oj) = norm(subcov,'fro');
                case 'SPECTRAL'
                % Spectral norm
                [~,COV(oi,oj),~] =svds(subcov,1);
                case '1'
                % L1 norm matlab style
                COV(oi,oj) = norm(subcov,1);
                case 'L1'
                % L1 norm
                COV(oi,oj) = sum(abs(subcov(:)));
                case '2'
                % 2 norm
                COV(oi,oj) = norm(subcov,2);
            end                       
            COV(oj,oi) = COV(oi,oj);
        end
    end
    
    imatrix = eye(ncols);
    fmatrix = mean(diag(COV))*imatrix;
    
    % Test for positive definitiveness
    sCOV = COV;
    while lambda <= 1.0
        try
            sCOV = lambda*fmatrix + (1-lambda)*COV;    
            test_chol = chol(sCOV);
        end
        if exist('test_chol','var')
            break
        end
        lambda = lambda + delta;
    end

    % Lmat = 0.02 % default value
    
    if exist('Lmat','var')
        % Here Lmat can be a 'regularization' Rij matrix that gives more
        % weight to pair known to be important.
        % Lmat = Lmat*NMSA_to_MI(nmsa) + imatrix;
        % Lmat = Lmat*NMSA_to_MI(nmsa);        
        % Lmat = Lmat*COV + imatrix;
    else
        Lmat = 0.02;
    end
    
        switch inverse_method
        
            case 'INVERSE'
            cov_inv = inv(sCOV);
            cov_rev = sCOV;
                    
            case 'QUIC'                
            [cov_inv cov_rev opt cputime iter dGap] = ...
                QUIC('default', sCOV, Lmat, 1e-6, 2, 200);

            case 'GLASSO'
            % function [w, theta, iter, avgTol, hasError] = ...
            % glasso(numVars, s, computePath, lambda, approximate, ...
            % warmInit, verbose, penalDiag, tolThreshold, ...
            % maxIter, w, theta)
            [cov_rev, cov_inv, iter, avgTol, hasError] = ...
                glasso(ncols, sCOV, 0, Lmat.*ones(ncols), 0, ...
                0, 0, 1, 1e-4, 1e4, zeros(ncols), zeros(ncols));
            
        end
    
    nonzeros = (nnz(cov_inv)-ncols)/(ncols*(ncols-1));
    fprintf('Sparsity = %f \n', nonzeros);

        
    rho = zeros(ncols,ncols);
    for i = 1:ncols
        for j = i:ncols
            rho(i,j) = -cov_inv(i,j)/sqrt(cov_inv(i,i)*cov_inv(j,j));
            rho(j,i) = rho(i,j);
        end
    end
    
    % MIP matrix
    n_rho = rho;
    n_cov_inv = cov_inv;
    
    for i = 1:ncols
        n_rho(i,i) = NaN;
        n_cov_inv(i,i) = NaN;
    end
    
    switch pc_method
        case 'RHO'
                pcMIP = MI_to_MIP(n_rho,ncols);
        case 'INVERSE'
                pcMIP = MI_to_MIP(-n_cov_inv,ncols);
    end

    ppvMIP = mat_to_ppv(pcMIP);
    
    % ZPX2 matrix
    pcZPX2 = MIP_to_ZPX2(pcMIP,ncols);    
    pcZPX2 = real(pcZPX2);        
    ppvZPX2 = mat_to_ppv(pcZPX2);
        
end


function [binmsa] = nmsa_to_binmsa_20q(nmsa)
% Returns each sequence of length L as a vector of size 20L with 0 and 1. 
% Gaps (which would be # 25 in the original Matlab numeric representation 
% of an MSA are ignored. Thus, if at a certain position there is a gap that
% position will be converted into a vector of 20 0s.

[nseq,npos]=size(nmsa);
binmsa=zeros(nseq,20*npos);
for i=1:npos 
    for aa=1:20 
        binmsa(:,20*(i-1)+aa)=(nmsa(:,i)==aa); 
    end; 
end;

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
    
    if (ZPX2_i<0&&ZPX2_j<0)
        pZPX2(m,n)=-pZPX2(m,n);
    end

% Symmetrize.

    pZPX2(n,m)=pZPX2(m,n);
    
    end
    
    pZPX2(m,m)=NaN;

end
end


function [ppv_mat] = mat_to_ppv(mat)

% Here we fit a logistic distribution to the data.

[~,cols] = size(mat);
data = mat(:);
ndata = length(data);
all_ind = 1:ndata;

% Logistic fit Matlab style
% [param] = fitdist(data,'logistic');
% data_mean = param.Params(1);
% data_std = param.Params(2);
% z_data = (data - data_mean)/data_std;
% ppv_data = z_data;

% Logistic fit PSICOV style
data_mean = nanmean(data);
data_std = nanstd(data);
z_data = (data - data_mean)/data_std; 
ppv_data = 0.904 ./ (1.0 + 16.61 * exp(-0.8105 * z_data));

ppv_mat = zeros(cols);
[i,j] = ind2sub(size(mat),all_ind);

for n = 1:ndata
    ppv_mat(i(n),j(n)) = ppv_data(n);
end

end
