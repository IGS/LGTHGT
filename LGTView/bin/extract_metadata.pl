#!/usr/bin/perl

=head1 NAME

extract_metadata.pl - Component of LGTview to extract the metadata from a TCGA bar code 
and then assign it to the BAM file information tied to that data.

=head1 SYNOPSIS

Extracts metadata from the output of LGTseek and enables this to be loaded into LGTview.

=head1 DESCRIPTION

The current iteration of this script only is built to handle data derived from TCGA. Future
versions will allow one to provide an input file that can assign one's own particular set of
metadata to further the capability of LGTview. The main purpose of this script is to add
the reference where the sequence is derived from from the other metadata already attached
to the BLAST results output file. 

Future iterations will allow one to call this single program to process metadata for any of
the four LGTSeek pipelines (the current is built for good donor reference and good LGT-free
recipient reference genome).

=head1 USAGE

With TCGA metadata:
./extract_metadata.pl cgquery_outfile relevant_bamfile best_blast_overall my_out_file.tsv

Without TCGA metadata:
./extract_metadata.pl relevant_bamfile best_blast_overall my_out_file.tsv


=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
no warnings 'experimental::smartmatch'; # seems to work fine for Perl 5.18. mute this warning

my $samtools = "/usr/local/bin/samtools";
my $cgquery_file;
my $bam_file;
my $best_blast_file;
my $infile;
my $out;
# this is built out by the get_cgquery_data function. will be empty if no cgquery data present
my $string_of_metadata; 
# Variables to help order BLAST results output to be euk->bac->euk->bac. 
my $euk_entry = '';
my $bac_entry = '';
my $num_of_entries = 0;

if ( @ARGV != 3 && @ARGV != 4) {
	print "Incorrect number of arguments. Please view the 'usage' section at the top ".
		  "of this file for how to run this script.\n";
	exit(1);
}

# Handle this immediately to reduce the amount of outfile manipulation.
if ( @ARGV == 4) {
	$out = $ARGV[3];
} elsif ( @ARGV == 3) {
	$out = $ARGV[2];
}

open(my $outfile, ">$out" || die "Can't open file $!");

# Print the base header regardless of whether cgquery file is present
print $outfile "read\teuk_read\teuk_e:numeric\teuk_len:numeric\teuk_blast_lca:list\teuk_genus\t";
print $outfile "read\tbac_read\tbac_e:numeric\tbac_len:numeric\tbac_blast_lca:list\tbac_genus\t";

# Extra processing will happen if three arguments are provided as to get whatever metadata
# can be found from the cgquery results if this is TCGA data. All files require the BAM
# files that detail where the reads come from in the host. 
if ( @ARGV == 4) {

	$cgquery_file = $ARGV[0];
	$bam_file = $ARGV[1];
	$best_blast_file = $ARGV[2];
	print "Extracting metadata from both the cgquery result file ($cgquery_file)\n";

	open($infile, "<$cgquery_file" || die "Can't open file $cgquery_file");

	# This next array contains all fields from cgquery that are desired to be included in the metadata results
	# except for analyte_code and sample_type which both require special processing
	my @relevant_fields = qw( disease_abbr library_strategy platform );

	while (my $line = <$infile>){

		$line =~ /^\s+(\w+)\s+:/;

		# Analyte code and sample type require some additional processing that requires the 
		# report charts from TCGA in order to convert these values into meaningful data. 
		# These will be properly accounted for once the site is up and running again. 
		if($1 eq 'analyte_code'){

		} elsif($1 eq 'sample_type') {

		}
		elsif($1 ~~ @relevant_fields) { # check if any elements in the array are present
			&get_cgquery_data($line); # build the metadata string to add on later
		}
	}

	# At this point, $string_of_metadata holds all the relevant info from the cgquery results file.
	# This will be appended along with the BAM data. 
	print "Done extracting metadata from cgquery result file \n";

	# Print header that includes cgquery fields
	print $outfile "analyte_code\tsample_type\tdisease_abbr\tlibrary_strategy\tplatform\teuk_ref\n";

} elsif ( @ARGV == 3) {
	$bam_file = $ARGV[0];
	$best_blast_file = $ARGV[1];

	# Print header that excludes cgquery fields
	print $outfile "euk_ref\n";
}

print "Extracting metadata from the BAM file ($bam_file), please wait... \n";
open($infile, "<$best_blast_file" || die "Can't open file $best_blast_file");

# The first line needs to be tab-delimited and denote what each of the TSVs are in the file

# The next step is to append the BAM and cgquery data (if provided) to what was found from LGTseek
while (my $line = <$infile>) {

	chomp($line);
	my @vals = split /\t/, $line;

	# Value in 15 is the ID we want to search the BAM file with to pull the reference location
	my $bam_res = `$samtools view $bam_file | grep -m 1 '$vals[15]'`; # use bash
	my @bam_vals = split /\t/, $bam_res;

	my $ref_location = $bam_vals[2]; # more information here, but just grab this for now

	# Exactly which pieces of metadata are tied to the input for LGTView can be customized here
	my $final_line = join "\t", @vals[15,0,10,3,14]; 

	# Extract just the genus and append to line
	my @taxonomy = split /;/, $vals[14];
	# This is a terrible hack that needs to be changed, but just use this for testing. There must
	# be some output of LGTSeek that specifies genus. For now just hope that you catch a genus
	# or something more refined and pull that term out. 
	my $genus = $taxonomy[-1];
	$genus =~ /(\w+)\s*.*/;
	$final_line .= "\t$1";

	# Reads are not always in an order of hu-> bac -> hu -> bac. Thus, before printing out each pair
	# decide via the domain level of taxonomic classification to put euk before bac. 

	# CHANGE THE LOGIC HERE IF YOU DON'T JUST WANT EUK v BAC LGT RESULTS 
	if ($taxonomy[1] eq 'Eukaryota'){
		$euk_entry = $final_line;
		$num_of_entries++;
	} elsif ($taxonomy[1] eq 'Bacteria'){
		$bac_entry = $final_line;
		$num_of_entries++;
	}

	if ($num_of_entries == 2) {
		
		# At this point we have found both mates to a pair. However, we are just concerned with LGT
		# between euks and bacs. Thus, if exactly one of each of these are not present then omit the
		# pair from the output. 

		# CHANGE THE LOGIC HERE IF YOU DON'T JUST WANT EUK v BAC LGT RESULTS 
		if ( $euk_entry ne '' && $bac_entry ne '' ) { 
			print $outfile "$euk_entry\t";
			print $outfile "$bac_entry\t$ref_location$string_of_metadata\n";
		}

		$num_of_entries = 0;
		$euk_entry = '';
		$bac_entry = '';
	}
}

print "Done creating metadata file. Use this to load into MongoDB via lgt_load_mongo.pl \n";

# Function to return the value tied to a particular field in a cgquery result
sub get_cgquery_data {
	my ($line) = @_;
	$line =~ /.*:\s(.*)/;
	$string_of_metadata .= "\t$1";
}
