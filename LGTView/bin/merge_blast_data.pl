#!/usr/bin/perl -w

=head1 NAME

merge_blast_data.pl

=head1 SYNOPSIS

Script to merge paired read FASTA formatted input files or paired
read BLAST result file. 

				***PLEASE NOTE:***
This script assumes that the two files given have an equal
amount of mates for each read and are in the same order and that
each paired header set of IDs (1 + 2) follows either of these formats: 
			XXX123456/1 + XXX123456/2
			XXX123456_1 + XXX123456_2

=head1 DESCRIPTION

This script takes four arguments:

--data_type  = 'query' OR 'results'
--left_file  = /path/to/left/mate/file
--right_file = /path/to/right/mate/file
--out_file = /path/to/output/file

Thus, to use this script you would enter:

./merge_blast_data.pl --data_type=query --left_file=1.fsa --right_file=2.fsa --out_file=myresults.fsa

If 'query' is specified for data_type, then this script will expect
two FASTA formatted files where each contains all the reads for one
particular read pair mate.

If 'results' is specified for data_type, then this script expects two
BLAST result files where each contains all the results for one particular
read pair mate.

Note that if you haven't performed BLAST with your query data already,
you can merge the query files into one before performing BLAST and be 
ready to use your results for TwinBLAST right away after the BLAST is
performed.

The output of this script will be a merged file with read pairs found
one after the other in succession. For example:

Read1/A
Read1/B
Read2/A
Read2/B
etc.

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use warnings;
use Getopt::Long;
use Tie::File;

my $data_type;
my $left_file;
my $right_file;
my $out_file;

GetOptions (
	"data_type|d=s" => \$data_type,
	"left_file|l=s" => \$left_file,
	"right_file|r=s"=> \$right_file,
	"out_file|o=s"  => \$out_file
) or die "Input not as expected. Please read near the top of this file for details.";

tie my @f1, 'Tie::File', $left_file or die "Can't find left file";
my $left_total = scalar @f1;
tie my @f2, 'Tie::File', $right_file or die "Can't find right file";
my $right_total = scalar @f2;

my $left_single_entry = 1;
my $left_cnt = 0;
my $left_id;
my $right_single_entry = 1;
my $right_cnt = 0;
my $right_id;

my $not_eof = 1; # overarching while loop to keep processing til both files done
my $entry_delimiter; # identify FASTA or BLAST files as input
my $delimiter; # stores the previous variable for regex
my $found_delimiter; # use to keep track of entry borders

open OUT, ">$out_file" or die ("Cannot open $out_file for writing");

# Have to do the merge process slightly differently for either merging 
# queries or BLAST results.
if($data_type eq 'query'){
	$entry_delimiter = '>'
} elsif($data_type eq 'results') {
	$entry_delimiter = 'BLAST'
}

$delimiter = quotemeta($entry_delimiter);

# Keep processing until both end of files are reached. While unlikely, this
# style of processing allows for different paired read lengths which is ideal
# for also being able to process BLAST results. However, this might unintentionally
# pass invalid paired reads. 
while ($not_eof) {

	$found_delimiter = 0;
	while ($left_single_entry) {

		# If at the EOF, stop processing
		if($left_cnt == $left_total) {
			$left_single_entry = 0;

		# Check if its the first delimiter or found another delimiter.
		# This is to ensure that a single entry is output each time
		} elsif($f1[$left_cnt] =~ /^$delimiter/) {

			# If at second delimiter, stop and move to other file
			if($found_delimiter){
				$left_single_entry = 0;

			# If only a single entry, print out header content
			} else {
				$found_delimiter = 1;
				print OUT "$f1[$left_cnt]\n";

				# Pull the ID from FASTA file to compare to right ID
				if($entry_delimiter eq '>') {
					$f1[$left_cnt] =~ m/>(.*)[\/*_*]+.*/; 
					$left_id = $1;
				}

				$left_cnt++;
			}

		# If inbetween headers, output content
		} else {
			print OUT "$f1[$left_cnt]\n";

			# Pull the ID from a BLAST file
			if($entry_delimiter eq 'BLAST') {
				if($f1[$left_cnt] =~ m/^Query=(.*)[\/*_*]+.*/){
					$left_id = $1;
				}
			}

			$left_cnt++;
		}
	}

	# While these functions are essentially the same, a bit easier
	# to keep track of the value of each variable by keeping them 
	# in these explicit blocks instead of through a sub since the 
	# sub itself will have many extra if statements to track which
	# set of values to be modifying.
	$found_delimiter = 0;
	while ($right_single_entry) {
		if($right_cnt == $right_total) {
			$right_single_entry = 0;
		} elsif($f2[$right_cnt] =~ /^$delimiter/) {
			if($found_delimiter){
				$right_single_entry = 0;
			} else {
				$found_delimiter = 1;
				print OUT "$f2[$right_cnt]\n";
				if($entry_delimiter eq '>') {
					$f2[$right_cnt] =~ m/>(.*)[\/*_*]+.*/; 
					$right_id = $1;
				}
				$right_cnt++;
			}
		} else {
			print OUT "$f2[$right_cnt]\n";
			if($entry_delimiter eq 'BLAST') {
				if($f2[$right_cnt] =~ m/^Query=(.*)[\/*_*]+.*/){
					$right_id = $1;
				}
			}
			$right_cnt++;
		}
	}

	if($left_id ne $right_id){
		die "$left_id and $right_id do not match. Please check your ".
			"specified output file to view the two sequences that caused the ".
			"crash. Perhaps the inputs were not sorted in the same manner or ".
			"there is an asymmetric number of reads in the first place. Died";
	}

	if($left_cnt == $left_total and $right_cnt == $right_total){
		$not_eof = 0;
	} elsif($left_cnt == $left_total) {
		$left_single_entry = 0;
		$right_single_entry = 1;
	} elsif($right_cnt == $right_total) {
		$left_single_entry = 1;
		$right_single_entry = 0;
	} else {
		$left_single_entry = 1;
		$right_single_entry = 1;
	}
}

close OUT;
