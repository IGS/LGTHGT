#!/usr/bin/perl -w

=head1 NAME

refine_blast_data.pl

=head1 SYNOPSIS

Script to refine raw BLAST results to only those hits that are present in another file

=head1 DESCRIPTION

This script takes three arguments:

blast_file  e.g. /path/to/blast/file
id_list e.g. /path/to/id/list
out_file e.g. /path/to/output/file

Thus, to use this script you would enter:

./refine_blast_data.pl blast.results id_list.txt my_final_blast.results

Note that the id_list.txt file just needs any trace of the read present and does not
require a specific format. Thus, be wary of this as the BLAST file will include any results
that match ANY trace of a particular read in the id_list.txt file.

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use warnings;

my $blast_file = $ARGV[0];
my $id_list = $ARGV[1];
my $out_file = $ARGV[2];

if ( @ARGV != 3) {
	print "Incorrect number of arguments. Please ensure the correct usage described at the ".
			"top of this script";
	exit(1);
}

open(my $out, ">$out_file") or die "Cannot open $out_file for writing";
open(my $fh, $blast_file) or die "Can't open $blast_file!";

my $blast_entry; # start fresh at every entry, only include those that are relevant
my $read_id; # read pair ID
my $found_count = 0; # keep track of how many entries
my $results_done = 0; # done with results, output matrix data

while (my $line = <$fh>) {

	if($line =~ /^BLAST.*/ && $found_count == 0){

		$blast_entry .= $line;
		$found_count = 1;

	} elsif($line =~ /^BLAST.*/ && $found_count == 1) {

		$blast_entry .= $line;
		$found_count = 2;

	} elsif($found_count == 1) { # section following first BLAST header

		$blast_entry .= $line;

		# Only need to pull the query ID for one mate, do it for second

	} elsif($found_count == 2) { # section following second BLAST header

		if($line =~ /^Query=.*/) {
			$line =~ /^Query=\s(.*)\/(1|2)$/;
			$read_id = quotemeta "$1";

		} elsif ($line =~ /^BLAST.*/) {

			open(my $fh2, $id_list) or die "Can't open $id_list!"; 
			while (my $line2 = <$fh2>) {
				if($line2 =~ /$read_id/){
					print $out $blast_entry;
					last;
				}
			}
			close $fh2;

			$blast_entry = '';
			$read_id = '';

		} elsif($line =~ /\s\sDatabase:.*/) {

			open(my $fh2, $id_list) or die "Can't open $id_list!"; 
			while (my $line2 = <$fh2>) {
				if($line2 =~ /$read_id/){
					print $out $blast_entry;
					last;
				}
			}
			close $fh2;

			$blast_entry = '';
			$read_id = '';
			$results_done = 1;
			$found_count = 0; # escape the earlier ifs
			print $out $line;
		}

		$blast_entry .= $line;

	} elsif($results_done == 1) { # output footer of raw results

		print $out $line;
	}
}

close $fh;
close $out;
