#!/usr/bin/perl -w

=head1 NAME

conceal_blast_data.pl

=head1 SYNOPSIS

Script to hide sensitive information found in a BLAST results file. 

=head1 DESCRIPTION

This script takes two arguments:

--blast_file  = /path/to/blast/file
--out_file = /path/to/output/file

Thus, to use this script you would enter:

./conceal_blast_data.pl --blast_file=blast.results --out_file=my_concealed_blast.results



				*** PLEASE NOTE ***

While the aim of this script is to remove any sensitive information
from a BLAST report, it may not suit all of your particular needs for 
data removal. 

BE SURE TO REVIEW THE OUTPUT SO THAT IT MEETS YOUR REQUIREMENTS.

				*******************


=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use warnings;
use Getopt::Long;

my $blast_file;
my $out_file;

GetOptions (
	"blast_file|b=s" => \$blast_file,
	"out_file|o=s"  => \$out_file
) or die "Input not as expected. Please read near the top of this file for details.";

# booleans to proces different sections of the BLAST results (heaader region and alignments)
my $boundary = 0; 
my $alignments = 0;
my $significant = 0;
my $hide_alignments = 0;
my $inbetween_q_and_s = 0;

# make sure query and subject length aren't equal (would reveal sequence)
my $qlen;
my $slen;

open OUT, ">$out_file" or die ("Cannot open $out_file for writing");
open(my $fh, $blast_file) or die "Can't open $blast_file!";

while (my $line = <$fh>) {

	chomp $line;

	# Found a new entry
	if($line =~ /^BLAST.*/) {
		$boundary = 1;
		$alignments = 0;
		$significant = 0;
		$hide_alignments = 0;
		print OUT "$line\n";

	# Found a new set of alignments
	} elsif($line =~ /^Searching.+done$/) {
		$alignments = 1;
		$boundary = 0;
		print OUT "$line\n";

	# Process the section between entry header and alignments
	} elsif($boundary) {

		if($line =~ /.*letters\)$/){
			$line =~ s/\d+/1/;
			print OUT "$line\n";

		} else {
			print OUT "$line\n";
		}

	# Process the alignments section
	} elsif($alignments) {

		# If hits are actually found, need to remove some info from 
		# the next few lines that could give away the sequence
		if($line =~ /^Sequences producing significant alignments:/){
			print OUT "$line\n";
			$significant = 1;

		# No significant hits found
		} elsif($significant) {

			# Allow printing of score(bits) and e-value but remove all
			# other data. Show the alignments with dummy data to satisfy
			# the BLAST result formatting for use in downstream parsers.
			if($line =~ /^>/){
				print OUT "$line\n";		
				$hide_alignments = 1;

			# Need to hide sequence data. Can't do a simple replace of nucletodies
			# to 'n' to account for the case where the sbjct result sequence is
			# the entirety of that sequence (would give away the query sequence too
			# easily). Also remove which bases aligned.
			} elsif($hide_alignments) {
	
				# Fill in Query/Sbjct data with dummy data.
				if($line =~ /^Query:/){
					print OUT "Query: 0  nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn 1\n";
					$inbetween_q_and_s = 1;
				} elsif($line =~ /^Sbjct:/){
					print OUT "Sbjct: 0  nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn 1\n";
					$inbetween_q_and_s = 0;

				# Skip the alignment symbols
				} elsif($inbetween_q_and_s) {
					print OUT "                                                                      \n";

				# Eliminate traces of evidence via % ID or strand
				} elsif($line =~ /^\sIdentities =/) {
					print OUT " Identities = 0/0 (0%)\n";
				} elsif($line =~ /^\sStrand =/) {
					print OUT " Strand = Plus / Plus\n";

				# Any other data is alright to pass to final file.
				} else {
					print OUT "$line\n";		
				}

			# Allow printing of score(bits) and e-value
			} else {
				print OUT "$line\n";		
			}

		} else {
			print OUT "$line\n";		
		}
	}
}

close OUT;
