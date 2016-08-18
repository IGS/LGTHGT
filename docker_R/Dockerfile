# R base image
FROM r-base

MAINTAINER James Matsumura (jmatsumura@som.umaryland.edu)

# install packages needed to generate heatmap
RUN echo 'install.packages(c("plyr", "RColorBrewer", "data.table"), repos="http://cran.us.r-project.org", dependencies=TRUE)' \
	> /tmp/packages.R \
	&& Rscript /tmp/packages.R

# Create R user to be mounted and run from other container
ENV HOME /home/lgtview
RUN useradd --create-home --home-dir $HOME lgtview \ 
	&& chown -R lgtview:lgtview $HOME

# That should be everything. As each call to R to generate a heatmap will have 
# different parameters, need to specify that when calling a docker exec cmd. 
CMD ["R"]
