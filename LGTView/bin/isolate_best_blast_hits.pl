#!/usr/bin/perl

=head1 NAME

isolate_best_blast_hitse.pl - Takes paired read BLAST output from the LGTseek pipeline and 
isolates just the top hit for each read. 

=head1 SYNOPSIS

Refines a BLAST results file from all relevant hits to only the most significant hits.

=head1 DESCRIPTION

Uses the read ID and specific pair suffix to remove the non-top hits found. This assumes
ordering in the sense that read pair 1 is followed by read pair 2 like so:

SRR00010000/1 ~
SRR00010000/2 ~
SRR00010000/2 ~
SRR00010000/2 ~
SRR00010000/2 ~
SRR00020000/1 ~
SRR00020000/1 ~
SRR00020000/2 ~
SRR00030000/1 ~
SRR00030000/2 ~

And aims to produce output like this:

SRR00010000/1 ~
SRR00010000/2 ~
SRR00020000/1 ~
SRR00020000/2 ~
SRR00030000/1 ~
SRR00030000/2 ~

=head1 USAGE

./isolate_best_hits.pl lgtseek_blast.out

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;

if ( @ARGV != 2) {
	print "Please provide the BLAST results file containing hits for both pairs of a read like so: $0 blast_overall my_out_file.txt \n";
	exit(1);
}

my $bfile = $ARGV[0];
my $outfile = $ARGV[1];
open(my $infile, "<$bfile") || die "Can't access BLAST results file $bfile: $!";
open(my $outfile, ">$outfile") || die "Can't create outfile $!";

my $id = ''; 
my $found1 = 0;
my $found2 = 0;
my $line1 = '';
my $line2 = '';
my $id1 = '';
my $id2 = '';

while (my $line = <$infile>) {

	my @vals = split /\t/, $line;

	if($id eq ''){ # account for start of pair of reads
		$id = $vals[0];
	
		# Need to start with mate 1
		if ($id =~ /\/1$/) {
			$found1 = 1;
			$line1 = $line;

		} else {

			$id = '';
			next;
		}

	} elsif($id eq $vals[0]){ # account for 2nd-n best hits
		next;

	} elsif($id ne $vals[0]){ # account for next read ID in a pair
		$id = $vals[0];

		# Need to perform a check here to ensure this is the second of a pair as 
		# without that it wouldn't catch:
		# SRR00010000/1 ~
		# SRR00020000/1 ~
		if ($id =~ /\/2$/) {
			$found2 = 1;
			$line2 = $line;

		} else {

			# If this isn't mate 2, then mate 1 has no mate 2 and the current mate 1
			# that is in this line needs to be reinitialized as mate 1.
			$id = $vals[0];
			$found1 = 1;
			$line1 = $line;

		}
	}

	# Unfortunately, each individual read isn't guaranteed to be part of a pair if no
	# results were identified for one of them. Account for this here. 
	if ($found1 == 1 && $found2 == 1){

		$line1 =~ /^(.*)\/1\t/;
		$id1 = $1;
		$line2 =~ /^(.*)\/2\t/;
		$id2 = $1;

		# Only print if these reads are indeed part of a pair
		if($id1 eq $id2){
			print $outfile "$line1";
			print $outfile "$line2";
		}

		$id = '';
		$found1 = 0;
		$found2 = 0;
		$line1 = '';
		$line2 = '';
	}
}
