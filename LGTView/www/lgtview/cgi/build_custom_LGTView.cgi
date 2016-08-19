#!/usr/bin/perl -w

=head1 NAME

build_custom_LGTView.cgi

=head1 SYNOPSIS

Script which follows build_metadata_table.cgi and actually loads the
the new instance of LGTView. 

=head1 DESCRIPTION

This script will accept a JSON array of metadata items that were generated
by build_metadata_table.cgi and then re-configured by generateLGTView.js. 
These metadata will have been chosen for whether they are to be represented
as pie charts, filters, or neither within LGTView. 

The script happens in 3 main steps.

1) Extract the JSON metadata and build a file that can be processed by
configure_lgtview_for_metadata.pl. 

2) Rewrite lgtview.js via configure_lgtview_for_metadata.pl

3) Load MongoDB with the final metadata file built from build_metadata_table.cgi.
This will require the use of lgt_load_mongo.pl. Note that in its current state,
LGTView is built to only have 1 DB available at the moment. Until this has been
implemented, will have to remove old DB and load with a fresh instance each
time the generateLGTView.html site is accessed. 

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use warnings;
use CGI;
use JSON;
use Data::Dumper;

my $cgi = CGI->new;
my $jd = $cgi->param('dat');

# This data structure is a bit wonkier than expected. It is essentially a "2D"
# array (array with array refs as elements) and each of those arrays contain
# the hash of columns for each individual metadata. Thus, access like so:
# $md[0][0]->{'name'}, $md[0][1]->{'operator'}, etc.
my @md = from_json( $jd );

my $pchart_line = ''; # line 1 needed for configure_lgtview_for_metadata.pl
my $filter_line = ''; # line 2

my $file = '/export/lgt/files/md_config_file.tsv';

open(my $outfile, ">$file" || die "Can't open file $file");

print "Content-type: text/plain\n\n";

foreach my $m ( @{$md[0]} ) { # iterate over array of hashref

	print to_json({success=>1});

	my $name = $m->{'name'};
	my $filter = $m->{'filter'};
	my $pie = $m->{'pie'};
	#my $id = $m->{'id'}; ID not needed for this step, only for JS
	my $operator = $m->{'operator'};

	if($filter == 0 && $pie == 0){ # this data only needs to be loaded to MongoDB
		next;

	} elsif($pie == 1) { # append to line 1 to configure pie charts

		if($pchart_line ne '') { # separate if value already present
			$pchart_line .= "\t";
		}

		$pchart_line .= "$name|";

		# Try format the metadata fields into a more readable name for the pie
		# chart titles. Note this could require more error checking. Don't want 
		# to do this with the filters so that it's clear which column in the 
		# table is being filtered agianst in the left panel. For example...
		# spots_with_mates --> Spots With Mates
		# LibrarySource --> Library Source

		if($name =~ m/\_/){
			$name =~ s/\_/ /g;
		} else {
			$name =~ s/(\B[A-Z])/ $1/g;
		}

		$pchart_line .= "$name";

	} elsif($filter == 1) { # append to line 2 to configure filters

		if($filter_line ne '') {
			$filter_line .= "\t";
		}

		$filter_line .= "$name|";

		if($operator eq 'matches'){
			$filter_line .= "l";

		} elsif($operator eq '<') {
			$filter_line .= "n|<";

		} elsif($operator eq '>') {
			$filter_line .= "n|>";
		}
	}
}

print $outfile "$pchart_line\n$filter_line";
close $outfile;

# Modify the JS
`./configure_lgtview_for_metadata.pl /export/lgt/files/md_config_file.tsv /var/www/html/lgtview.js`;

# Load MongoDB
`./lgt_load_mongo.pl --metadata=/export/lgt/files/final_metadata.out --db=lgtview_example --host=172.18.0.1:27017`;
