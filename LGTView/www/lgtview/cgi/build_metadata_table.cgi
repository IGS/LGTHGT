#!/usr/bin/perl -w

=head1 NAME

build_metadata_table.cgi

=head1 SYNOPSIS

Script to build a metadata table for the intermediary site of LGTView.

=head1 DESCRIPTION

This script takes a single argument: 

- A file that contains the directory paths which house the relevant output files 
from LGTSeek. For each directory provided, this script will then access the 
respective metadata file, the BLASTN raw results file, and the respective LGT
out results file. If multiple directories are present then these BLAST results
must be merged as well as providing the metadata fields which actually have 
a value assigned to them for at least one group. 

The primary purpose of this script is to populate the generateLGTView.html site 
with a table that users can interact with to generate their custom instance
of LGTView. 

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use warnings;
use CGI;
use JSON;
use URI::Escape;

# Output files that will be expected 
my $single_metadata = "/single_metadata.out"; # just one run output
my $single_blast = "/single_blast.out";
my $final_metadata = "/export/lgt/files/final_metadata.out"; # combined run outputs
my $final_blast = "/export/lgt/files/final_blast.out";

# Need to process multiple outputs of LGTSeek as LGTView is truly useful when comparing
# numerous different sets of metadata against one another. 
my $cgi = CGI->new;
my $base_dir = uri_unescape($cgi->param('file'));
my $metadata_file = "/sra_metadata.csv";
my $lgt_hits_file = "/lgt_by_clone.txt";
my $blast_results_file = "/blastn.out";
my $blast_list = "/export/lgt/files/blast_list.txt";
my $uniq_sra = 0; # check to see if multiple SRA results are present
my @overall_metadata; # compile a list of metadata fields that have values tied to them
my @individual_metadata; # array of arrays for each set of headers present

open(my $sra_list_file, "<$base_dir" || die "Can't open file $base_dir");
open(my $blast_list_file, ">$blast_list" || die "Can't open file $blast_list");

# Would make sense to run this in parallel, implement this if the number of files gets
# to be quite high. 
while (my $sra_dirs = <$sra_list_file>) { # process each SRA LGTSeek output result

	$uniq_sra++;

	chomp $sra_dirs;
	my $meta_in = $sra_dirs . $metadata_file;
	my $lgt_in = $sra_dirs . $lgt_hits_file;
	my $blast_in = $sra_dirs . $blast_results_file;

	my @sra_headers; # metadata fields
	my @sra_values;

	my $firstLine = 0;

	open(my $m_infile, "<$meta_in" || die "Can't open file $meta_in");

	while (my $line = <$m_infile>) {
		chomp $line;

		if($firstLine == 0) {
			@sra_headers = split(/\,/, $line); # banking on SRA using commas for separation only 
			push @sra_headers, 'curation_note'; # account for TB curation note here
			$firstLine = 1;
	
		} else {
			@sra_values = split(/\,/, $line); 
			push @sra_values, 'NA'; 
		}
	}

	close $m_infile;

	my $idx = 0;

	# For letting a user choose which metadata to display, only concerned with those metadata 
	# fields that have a value and aren't comprised of a hash value.
	foreach my $x (@sra_values) {

		if($x ne '') { 

			if($sra_headers[$idx] ne 'ReadHash' && $sra_headers[$idx] ne 'RunHash') {

				if($sra_headers[$idx] ~~ @overall_metadata) {
					next;
				} else {
					# Use this final dataset to populate the table for generateLGTView.js
					push @overall_metadata, $sra_headers[$idx];
				}
			}
		}

		$idx++;
	}

	# Now append all metadata from SRA to the lgt_by_clone.txt file. Add handling in this
	# section if certain fields, like the hashes or consent, are desired to be omitted. 

	$firstLine = 0;

	open(my $l_infile, "<$lgt_in" || die "Can't open file $lgt_in");
	open(my $out, ">$sra_dirs$single_metadata" || die "Can't open file $lgt_in");

	while (my $line = <$l_infile>) {
		chomp $line;

		if($firstLine == 0) {

			my $curr_metadata = join("\t", @sra_headers);
			print $out "$line\t$curr_metadata\n"; 

			# Account for any, and possibly different (unlikely), LGTSeek outputs
			my @lgtseek_out_md = split(/\t/, $line);
			foreach my $md (@lgtseek_out_md) {
				unshift(@sra_headers, $md);

				if($md ~~ @overall_metadata) {
					next;
				} else {
					push @overall_metadata, $md;
				}
			}

			push @individual_metadata, \@sra_headers;

			$firstLine = 1;

		} else {

			my $curr_values = join("\t", @sra_values);
			print $out "$line\t$curr_values\n";
		}
	}

	close $l_infile;
	close $out;

	# Process the BLAST results so that TwinBLAST only houses those that match. This will be done by
	# refine_blast_data.pl
	#`./refine_blast_data.pl $blast_in $lgt_in $sra_dirs$single_blast`;

	print $blast_list_file "$sra_dirs$single_blast\n"; # file for merging
}

# Send the relevant JSON info for the filter/graph table in generateLGTView.js
print "Content-type: text/plain\n\n";
print "{root: [\n";
foreach my $x (@overall_metadata) {
	print to_json({'name' => $x,
			'filter' => \0,
			'pie' => \0,
			'id' => $x,
			'operator' => 'NA',
	}).",\n";
}
print "]}";

close $sra_list_file;
close $blast_list_file;

# Once all the relevant directories have been processed, if multiple present need to consolidate to both
# a single BLAST file and a single metadata file to accommodate TwinBLAST viewer and LGTView loader.
if($uniq_sra > 1) {

	my @uniform_metadata;

	# Building a final metadata file is not straightforward. Need to build a metadata file that
	# contains all the shared AND distinct fields between different sets of data. In addition to 
	# this restraint, the order of the metadata fields also needs to be equivalent and the order
	# maintained across the values associated with the data. The end result must be a uniform
	# header shared by all the different outputs.

	# Iterate over 2D array where each index of outer array attaches to an array of metadata fields.
	# While doing so, note the positions of each piece of metadata.
	my %md_order;
	my $idx=0;
	foreach my $refs (@individual_metadata) {
		foreach my $md_array_vals (@$refs) {
			if($md_array_vals ~~ @uniform_metadata) {
				next;
			} else {
				push @uniform_metadata, $md_array_vals;
				$md_order{$md_array_vals} = $idx;
				$idx++;
			}
		}
	}

	$idx--; # want the last filled metadata position for the array later

	# At this point, all unique metadata fields are present and they need to be used to build a 
	# final metadata file that accommodates each individual metadata file into a uniform final one. 
	open(my $outfile, ">$final_metadata" || die "Can't open file $final_metadata");
	print $outfile join("\t", @uniform_metadata) . "\n";

	open(my $sra_list_file2, "<$base_dir" || die "Can't open file $base_dir");

	# Iterate over each individual metadata file and reformat them to the uniform metadata header
	while (my $sra_dirs = <$sra_list_file2>) { 

		chomp $sra_dirs;
		my @curr_header; # split the header of the current metadata file
		my @curr_vals;
		my $firstLine = 0;

		open(my $curr_md_file, "<$sra_dirs$single_metadata" || die "Can't open file $sra_dirs$single_metadata");

		while (my $line = <$curr_md_file>) {
			chomp $line;

			if($firstLine == 0) {

				@curr_header = split(/\t/, $line); 
				$firstLine = 1;

			} else {

				my $i = 0; # use to communicate current headers respective to current metadata

				@curr_vals = split(/\t/, $line); 
				my @vals_array; $vals_array[$idx] = ''; # declare size of array

				foreach my $val (@curr_vals) {
					$vals_array[$md_order{$curr_header[$i]}] = $val;
					$i++;
				}

				# Only need to find indices for those present, the rest of the values will be
				# assigned an empty string, not undef, to load properly into MongoDB properly. 
				print $outfile join("\t", map { defined $_ ? $_ : '' } @vals_array ) . "\n";
			}
		}

		close $curr_md_file;
	}

	close $outfile;
	close $sra_list_file2;

	# Use merge_blast_or_bam_lists.pl to merge the BLAST files
	#`./merge_blast_or_bam_lists.pl $blast_list blast $final_blast`
}
