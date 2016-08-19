# This script will take in a metadata file formatted for LGTView. It finds
# whichever column is associated with the header 'bac_blast_lca:list' and
# builds a heatmap using relative or absolute abundances of those OTUs.
# Users will be able to specify the level of taxonomy in order to generate 
# a heatmap at a scope which suits their particular needs. The second 
# dimension to the heatmap will also need to be specified and has to be 
# found within that same metadata file. 
#
# This script is meant to be invoked from LGTView but it can be run on the
# command line like so:
#
# Rscript lgtview_plot_heatmap.R infile tax_# metadata_header abundance_type limit
#
# 1. infile = tab-delimited total metadata file (this may be filtered already by LGTView)
#
# 2. tax_# = taxonomic rank used to build the heatmap. Note that there are
# often numerous classically unranked assignments made here. Meaning, it
# doesn't follow strictly domain;kingdom;phylum;etc. Thus, the user will
# specify a number here that will, starting from the highest level found,
# will go down to as specific as they mention. So if the OTU is:
# cellular organisms;Eukaryota;Opisthokonta;Metazoa
# And the user enters 2 it will return domain-level results. 
#
# 3. metadata_header = will map to any of the headers present within the metadata
# file. Thus, leading to the heatmap to be (chosen_metadata,OTUs) as the (x,y)
#
# 4. abundance_type = either 'relative' or 'absolute' depending on whether the user
# wants relative counts or absolute counts for how many hits to that particular
# OTU within each of the metadata groups.
#
# 5. limit = the number of metadata fields that should be restricted to so that the
# output is not overcrowded. 
#
# Author: James Matsumura
#
# Contact: jmatsumura@som.umaryland.edu

library("plyr")
library("RColorBrewer")
library("data.table")

# Accept command line arguments
args <- commandArgs(TRUE)

# Assign file path, taxonomic rank, chosen metadata, abundance type
file.path <- args[1]
taxonomic.rank <- as.numeric(args[2])
chosen.metadata <- args[3]
abundance.type <- args[4]
limit.output <- as.numeric(args[5])

# Start as a data frame until abundances are calculated. Only filling on the
# off chance that some odd characters were introduced into an OTU name like
# '#' which causes issues for R's parsing. 

data <- read.table(file=file.path, header=T, sep="\t", fill=T)

# UPDATE - JUL 27
# There's no reason I need a filter file, should just use whatever file is generated
# by LGTView at the time of invoking the heatmap generation. This will auto-generate 
# a filtered or non-filtered dataset. Can delete if this proves to be unnecessary.
# 
# In order to be more accommodating with LGTView, this should take some input that
# allows for subsetting the particular data file with the current set of data 
# displayed in LGTView. For now, generate a file that contains a list of a 
# unique attribute (read pair ID). This makes the script much more flexible as it
# now benefits from the various filter mechanisms available in LGTView. 
#if (subset.input != "noFilter") {
  # fread can be played with depending on if speed is that much of an issue
#  chosen.subset <- fread(subset.input, select = c("read"))
  # Odd, can't consistently filter without doing this in some iterative fashion.
  # Use read IDs to isolate which rows to keep
#  filtered.indices <- c()
#  for(i in 1:length(chosen.subset[[1]])){
#    filtered.indices[i] <- match(chosen.subset[[1]][i], data[,"read"])
#  }
#  data <- data[filtered.indices,]
#}
# END UPDATE - JULY 27

# X df is whichever metadata is specified
x.col <- as.data.frame(data[,chosen.metadata])

# Y df is, for now, going to be set as the taxonomic assignment for bac read
y.col <- as.data.frame(data[,"bac_blast_lca.list"])

# Need essentially the number of unique entries in the metadata file
f.len <- length(y.col[[1]]) # x.col list is the same length

# Build a complete df to subset by that will attach each metadata to the relevant
# piece of taxonomic information
final_df <- data.frame(matrix(nrow=length(y.col[,1]),ncol=2))
final_df[,1] <- x.col # metadata col
names(final_df)[1] <- "metadata"
names(final_df)[2] <- "tax"

# First, refine the tax to the prescribed level/rank.
for(i in 1:f.len){
  
  taxonomy <- strsplit(as.character(y.col[i,1]),";")
  
  # Account for when the user asks for more specific than was found
  if(length(taxonomy[[1]]) < taxonomic.rank){
    tax_assignment <- "unclassified"
  } else { # now handle if it is indeed present
    tax_assignment <- taxonomy[[1]][taxonomic.rank]
  }
  
  # Sharing complete lineage will help more readily ID trends so attach it all
  if(taxonomic.rank > 1){
    mod_tax_assignment <- paste(taxonomy[[1]][1:taxonomic.rank-1], collapse=";")
    final_tax_assignment <- paste(mod_tax_assignment, tax_assignment, sep=";")
    
  # Handle the case where they only want the first taxonomic rank  
  } else {
    final_tax_assignment <- taxonomy[[1]][1]
  }

  # Append to df that will be used to calculate abundances for each individual df
  final_df[i,2] <- as.character(final_tax_assignment)
}

# This next loop will build a matrix for the heatmap with each row representing a
# unique metadata group and the columns being each unique tax found. 
#
# EVENTUALLY UPDATE TO RUN IN PARALLEL IF PROVES TOO SLOW:
# Going to build individual dfs that each represent a single row for each unique type
# of metadata present. The amount of columns is then dependent on how many unique 
# instances of tax were just identified by the last step. 

unique_metadata <- unique(as.character(final_df[,1]))
unique_tax <- unique(as.character(final_df[,2]))

# Build the final data frame with the dimensions just identified. 
idv_final_df <- data.frame(matrix(nrow=length(unique_metadata),ncol=length(unique_tax)))

# Assign the unique column names and row names to what will be the matrix to 
# store the abundance counts per unique metadata+tax combo
rownames(idv_final_df) <- as.character(unique_metadata)
colnames(idv_final_df) <- as.character(unique_tax) 

max <- 0 # needed to build legend for absolute abundance
# Building a vector for refining to top x hits with the most evidence
total.hits <- data.frame(matrix(nrow=length(unique_metadata),ncol=1))

# Now, for each piece of metadata, need to calculate abundance for each
for(i in 1:length(unique_metadata)){ 
  
  # Subset the data by each unique metadata group
  md_subset <- final_df[,1]==as.character(unique_metadata[i])
  idv_df <- final_df[md_subset,1:2]

  # This will perform the count of each unique type of tax to get an abundance
  tax_counts <- ddply(idv_df, .(tax), c("nrow"))

  # Going to build a hash for quick lookup when assigning values to heatmap matrix
  count_hash<-new.env()
  
  # Already in absolute abundance, if relative desired then convert. Note that the legend
  # needs to be a bit tuned for whether the data is for relative or absolute abundances
  if(abundance.type == "relative"){
    
    total <- sum(tax_counts[,2])
    total.hits[i,1] <- total
    
    for(q in 1:length(tax_counts[,2])){
      count_hash[[as.character(tax_counts[q,1])]]<-(tax_counts[q,2]/total*100)
    }

  # Building the hash slightly different for absolute (no % calc necessary)
  } else {
    
    for(p in 1:length(tax_counts[,2])){
      
      total.hits[i,1] <- sum(tax_counts[,2])
      
      count_hash[[as.character(tax_counts[p,1])]]<-tax_counts[p,2]
      
      if(tax_counts[p,2] > max){
        max <- tax_counts[p,2]
      }
      
    }
  }
  
  # Iterate over each column, and if a count is present then assign that
  # value. If it is not, then assign a 0. 
  for(j in 1:length(unique_tax)){
    
    # Check the built hash. If the current metadata group doesn't match to 
    # any of the tax groups identified, set the count to 0.
    if(is.null(count_hash[[colnames(idv_final_df)[j]]])){
      idv_final_df[i,j] <- 0

    # If this tax was associated with this metadata group, set to the 
    # count that was found for this particular group.
    } else {
      idv_final_df[i,j] <- as.numeric(count_hash[[colnames(idv_final_df)[j]]])
    }
  }
}

# At this point, each metadata field has tax assigned as well as the respective 
# counts. Need to subset by the vector of sums to find the top X total counts. 
sort.index <- sort(as.numeric(total.hits[,1]), index.return=TRUE, decreasing=TRUE)[[2]]

# Only limit this if it even needs to be limited
if(limit.output < length(sort.index)){
  new.sort.index <- sort.index[1:limit.output] # use these indices to subset
}

idv_final_df <- idv_final_df[sort.index[1:limit.output],] # data subsetted by metadata groups

# Build the legend here so it isn't recalculated at each iteration of the previous loop
if(abundance.type == "relative"){
  leg <- seq(0, 100, length=21)
  leg_labels <- c("0%","5%", "10%", "15%", "20%", "25%", "30%",
                  "35%,", "40%", "45%", "50%", "55%", "60%", "65%",
                  "70%", "75%", "80%", "85%", "90%", "95%", "100%")
} else {
  leg <- seq(0, max, length=21)
  leg_labels <- round(seq(0, max, length.out=21))
}

# Now that the data has been populated, output the plot
outfile <- "lgtview_heatmap.png"

# Makes sense to print this to an image to reduce the amount of handling required
# by the LGTView JS
printError <- function(x){
  error <- paste("Cannot generate heatmap as there are less than two distinct types of ",x,".",sep="")
  png(outfile, width=960, height=480)
  plot.new()
  title(error, line=-10, cex.main=1.8)
}

# Need to do error handling here in case either X or Y dims are less than 2
# since that cannot generate a valid heatmap. 
if(dim(idv_final_df)[1] < 2){
  printError("metadata groups")

# Handle Y dimension. This gives more details on why it failed to the user    
} else if (dim(idv_final_df)[2] < 2) {
  printError("taxonomy lineages")
  
# If data can generate a heatmap (greater than 2,2 dimensions), generate it  
} else {
  
  png(outfile, width=2400, height=1920)
  
  # Sort by row names to make the graph a bit more legible. Note that, based on 
  # similarity of abundance distribution (which needs to be interpeted carefully)
  # this ordering may be broken down into the different clustered groups.
  sorted_final_df <- idv_final_df[order(rownames(idv_final_df)),]
  
  # Change the left margin to accommodate however long the taxonomy covers
  par(mar=c(5, max(5,max(nchar(colnames(sorted_final_df)))/2.3),5,1))
  
  # Doing 100 for color gradient to accommodate relative abundance
  cg <- colorRampPalette(brewer.pal(8,"RdBu"))(100)
   
  # Need two images here in order to accommodate layout function
  layout(matrix(c(2,1), 2, 1), widths=c(0.2,0.2), heights=c(0.4,0.05))
  
  image(as.matrix(leg), col=cg, axes=F)
  axis(1, at=seq(0, 1, length=length(leg)), labels=leg_labels, cex.axis=1)

  # Transform achieves flipping axes.
  # Disabling clustering methods because I do not think it is appropriate to convey
  # relationships regardless of metadata type. Can make this an option in future version.
  # Not using the heatmap function as using that precludes any use of layout.
  hm <- as.matrix(t(sorted_final_df))
  image(1:ncol(hm), 1:nrow(hm), t(hm), col=cg, axes=F, xlab="", ylab="")
  axis(1, 1:ncol(hm), labels=colnames(hm), las=2)
  axis(2, 1:nrow(hm), labels=rownames(hm), las=2)
}