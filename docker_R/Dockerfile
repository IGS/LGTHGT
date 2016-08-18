# R base image
FROM r-base

# install packages needed to generate heatmap
RUN echo 'install.packages(c("plyr", "RColorBrewer", "data.table"), repos="http://cran.us.r-project.org", dependencies=TRUE)' \
	> /tmp/packages.R \
	&& Rscript /tmp/packages.R

# That should be everything. As each call to R to generate a heatmap will have 
# different parameters, need to specify that when calling a docker exec cmd. 
CMD ["R"]
