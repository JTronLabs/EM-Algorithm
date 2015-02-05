function gaussmix(numClusters, dataFile,modelFile)
    numClustersNumeric = str2double(numClusters);
    [data,numExamples,numFeatures] = scanIn(dataFile);
    [means, variances, priors] = init(data,numClustersNumeric);
    logProb = -realmax;
    
    repeat=true;
    iterationNo=0;
    while repeat && iterationNo<100
        [clusterLogDist,clusterLogDistDenominators] = eStep(data,numExamples,numFeatures,numClustersNumeric,means,variances,priors);
        
        %clusterLogDist
        %clusterLogDistDenominators
        %means
        %variances(1,:,:)
        %variances(2,:,:)
        %variances(3,:,:)
        %priors
        
        [means, variances, priors] = mStep(data,numExamples,numFeatures,numClustersNumeric,clusterLogDist);
        probAfterIteration = totalLogLikelihoodOfData(numExamples,clusterLogDistDenominators)
        nextLogProbMinusCurrent = probAfterIteration-logProb
        repeat = abs(nextLogProbMinusCurrent) > 0.001;
        logProb = probAfterIteration;
        iterationNo = iterationNo+1
        
        
        if nextLogProbMinusCurrent<0  && iterationNo ~= 2 %%first iteration, (prob-realmax), results in issues, so ignore
           disp('ERROR : Total probability decreasing!!'); 
           return
        end
        
    end
    
    %clusterLogDist
    %clusterLogDistDenominators
    %means
    %variances(1,:,:)
    %priors
    
    writeOutput(modelFile,clusterLogDist,data);
end

function [rawData,numExamples,numFeatures] = scanIn( dataFile)
    fid = fopen(dataFile,'r'); % Open text file
    
    exAndFeat = cell2mat( textscan(fid,'%d %d',1) );  % Read first line
    numExamples = exAndFeat(1); 
    numFeatures = exAndFeat(2);
    
    rawData = cell2mat( textscan(fid,repmat('%f ',[1,numFeatures])) ); %textscan repeats until it finds differentm format
    
    fclose(fid);
end

function writeOutput(modelFile,clusterLogDist,data)
    fid = fopen(modelFile,'w'); % Open text file
    
    exAndFeat = size(data);
    numExamples = exAndFeat(1);
    numFeatures = exAndFeat(2);
    exAndClus = size(clusterLogDist);
    numClusters = exAndClus(2);
    
    %find the max clusterLogDistribution of each example and save it as the
    %cluster the example is assign to
    assignedCluster = (1:numExamples).*0;
    for ex=1:numExamples
        max = -realmax;
        
        for c=1:numClusters
            if(clusterLogDist(ex,c)>max)
                assignedCluster(ex) = c;
                max = clusterLogDist(ex,c);
            end
        end
        
        fprintf(fid,'%d ',assignedCluster(ex) );
        fprintf(fid,repmat('%f ',[1,numFeatures]),data(ex,:) );
        fprintf(fid,'\n');
    end
        
    fclose(fid);
end

function [means, variances, priors] = init(data, numClusters)
    %initialize cluster priors to a uniform distribution
    priors( 1:numClusters ) =  1.0 / double(numClusters) ;
    
    %initialize priors for each cluster to a uniform
    %distribution
    numExAndFeat = size(data);
    numEx = numExAndFeat(1);
    numFeat = numExAndFeat(2);
        
    %find mins and maxs of each data feature
    mins( 1 : numFeat ) =  realmax;
    maxs( 1 : numFeat ) =  -realmax;
    for i=1:numEx
       for j=1:numFeat
           if(data(i,j)>maxs(j))
               maxs(j)= data(i,j) ;               
           end
           if(data(i,j)<mins(j))
               mins(j)=data(i,j);
           end
       end
    end
        
    %init means to a random value in the range of the data
    %init standard deviations to a fixed fraction of the range of each variable
    means = zeros(numClusters,numFeat);
    variances = zeros(numClusters,numFeat,numFeat);
    
    for i=1:numClusters
        for j=1:numFeat
            range = maxs(j)-mins(j);
            means(i,j) = range*rand()+mins(j);
            %means(i,j)=mins(j);
            variances(i,j,j) = ( range / 2.0 )^2 ;
        end
    end
end

function [clusterLogDist,clusterLogDistDenominators] = eStep(data,numExamples,numFeatures,numClusters,means,variances,priors)
    clusterLogDist = zeros(numExamples,numClusters);
    clusterLogDistDenominators = zeros(1,numExamples);
    
    for ex=1:numExamples
        logPMax = -realmax;
        
        for c=1:numClusters
            %numerator is ln ( P(Ci) * P(Xk | Ci) )
            %P(Xk | Ci) = multivariate normal distribution
            %http://en.wikipedia.org/wiki/Multivariate_normal_distribution#Density_function
            %apply log to that function, the coeffecient is now added and
            %the exponent of e is now subtracted
            clusterVariance =  reshape ( variances(c,:,:),[numFeatures numFeatures] ) ;
            normalLogCoeff = -.5 * log( (2*pi)^double(numExamples) * det( clusterVariance ) ); %2pi^ex or numExamples?
            %as my vectors are row vectors instead of column vectors, the
            %transpose has switched
            %NOTE:inverse tempVariance completed via the divide-faster than
            %inv(tempVariance)
            normalLogOfExp = -.5 * ( data(ex,:) - means(c,:) ) / clusterVariance *  transpose( data(ex,:) - means(c,:) ) ; 
            
            [a, MSGID] = lastwarn();%warnings OFF - should be removed
            warning('off', MSGID);

            %P(Ci) is just from the prior. Add the ln values to get
            %numerator
            clusterLogDist(ex,c) = log(priors(c)) + normalLogCoeff + normalLogOfExp;
            if(  clusterLogDist(ex,c) > logPMax )
                logPMax = clusterLogDist(ex,c) ;
            end
        end
        
        %after finding all the numerators & logPMax, use LogSum over the
        %numerators to find the denominator (normalizing constant) of every
        %example
        logSum=0;
        for c=1:numClusters
            logSum = logSum + exp(clusterLogDist(ex,c)-logPMax);
        end
        clusterLogDistDenominators(ex) = logPMax + log(logSum);
        
        %Once denominator has been found, subtract it from this example's
        %numerators
        clusterLogDist(ex,:) = clusterLogDist(ex,:) - clusterLogDistDenominators(ex);
    end
    
    
    
    %now we have the cluster distributions. The distributions indicate the
    %weight each data point has towards each cluster
end

function [means, variances, priors] = mStep(data,numExamples,numFeatures,numClusters,clusterLogDist)
    %NOTE :safe to convert from clusterLogDist back to probability as it is big
    probabilityDistribution = exp(clusterLogDist);
    weightsSummedOverDataExamples = sum(probabilityDistribution,1);
    
    %for each cluster prior, average the distribution over every examples
    %prior(cluster=c) = [ SUM OVER DATA EXAMPLES Prob(c|data) ]/numDataExamples
    priors = sum(probabilityDistribution,1)./double(numExamples);%prior = sum over column dimension/numData
    
    
    %for each mean, find weighted average of the data
    %MEAN(cluster=c) = [ SUM OVER DATA EXAMPLES data * Prob(c|data) ] / [SUM OVER DATA EXAMPLES Prob(c|data) ]
    means = zeros(numClusters,numFeatures);
    for c=1:numClusters
        for ex=1:numExamples
            %for each cluster mean, sum up the data features weighted by
            %probability
            means(c,:) = means(c,:) + data(ex,:) .* probabilityDistribution(ex,c);
        end
        
        means(c,:) = means(c,:) ./ weightsSummedOverDataExamples(c);
    end
    
    
    %for each variance, find distance from mean, square, and weight by dist
    %variance(cluster=c) = [SUM OVER DATA EXAMPLES (data-mean^2) * Prob(c|data)] / [SUM OVER DATA EXAMPLES Prob(c|data) ]
    variances = zeros(numClusters,numFeatures,numFeatures);
    for c=1:numClusters
        
        varianceDiagonal = zeros(1,numFeatures);
        for ex=1:numExamples
            %for every data feature, find sqaure distance from mean and
            %multiply by probability weight
            squareDistFromMean = ( data(ex,:) - means(c,:) ).^2;
            varianceDiagonal = varianceDiagonal + ( squareDistFromMean .* probabilityDistribution(ex,c) );
        end
        
        varianceDiagonal = varianceDiagonal ./ weightsSummedOverDataExamples(c);
        
        %assign the variances to the diagonal of the variance cluster matrix
        for f=1:numFeatures
            variances(c,f,f) = varianceDiagonal(f);
        end
    end
    
    %priors 
    %means
    %variances(1,:,:)
    %variances(2,:,:)
    %variances(3,:,:)
    
end

function totalLogProb = totalLogLikelihoodOfData(numExamples,clusterLogDistDenominators)    
    %{
    total likelihood = P(x1,x2,�,xn) = \prod_i \sum_c P(x_i | cluster_c) P(cluster_c)
    log (P(x1,x2,�,xn)) = log( \prod_i \sum_c P(x_i | cluster_c) P(cluster_c) )
                           =\sum_i log( \sum_c P(x_i | cluster_c) P(cluster_c) ) )
    Given each denominator = log(\sum_c P(x_i | cluster_c) P(cluster_c) ) ) then 
    log (P(x1,x2,�,xn)) = \sum_i (denominator_i)
    %}

    totalLogProb=0;
    for ex=1:numExamples
        totalLogProb = totalLogProb + clusterLogDistDenominators(ex);
    end
    
    %{
    %logsum the denominators to find the total  
    logPMax=-realmax;
    for ex=1:numExamples
        if clusterLogDistDenominators(ex) > logPMax
            logPMax = clusterLogDistDenominators(ex);
        end
    end
    
    logSum=0;
    for ex=1:numExamples
        logSum = logSum + exp(clusterLogDistDenominators(ex) - logPMax);
    end
    
    totalLogProb = logPMax + log(logSum);
    %}
end
























