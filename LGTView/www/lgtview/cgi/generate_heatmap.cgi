#!/usr/bin/perl -w

=head1 NAME

generate_heatmap.cgi

=head1 SYNOPSIS

Script called when clicking the 'load' button from lgtview.js.

=head1 DESCRIPTION

This script will accept a JSON array of metadata items that are present
in the bottom table of an LGTView page. It will then use this table to 
create a heatmap via R.

The script happens in 2 main steps.

1) Extract the JSON metadata and build a tsv file that can be processed by
lgtview_plot_heatmap.R 

2) Call R and run the R script with the passed in parameters from the site.

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
my $tax = $cgi->param('tax');
my $metadata_header = $cgi->param('chosen_metadata');
my $abudance_type = $cgi->param('abudance_type');
my $limit = $cgi->param('limit');

# 2D array (array with array refs as elements) and each of those arrays contain
# the hash of columns for each individual metadata. Thus, access like so:
# $md[0][0]->{'name'}, $md[0][1]->{'operator'}, etc.
my @md = from_json( $jd );

my $file = '/export/lgt/files/r_input_file.tsv';
open(my $outfile, ">$file" || die "Can't open file $file");

my @headers; # need all data to be in same order as headers 
# Note that these headers will be in an arbitrary order according to the order
# identified in the first JSON hash found. 
foreach my $key (keys $md[0][0]) {
	push @headers, $key;
}

# Append header as first line in file
print $outfile join("\t", @headers);

print "Content-type: text/plain\n\n";

foreach my $m ( @{$md[0]} ) { # iterate over array of hashref

	my @row_dat;

	print to_json({success=>1});

	# For each object, maintain the same order
	foreach my $x (@headers) {
		push @row_dat, $m->{$x};
	}

	# row is ordered and ready to go so add to output
	print $outfile join("\t", @row_dat);
}

close $outfile;

# Run the R script
# Need to change this to a docker command between linked containers
`Rscript /usr/bin/lgtview_plot_heatmap.R $file $tax $metadata_header $abundance_type $limit`;

# Do a polling check for when this file is present and then send 
# the path to JS for viewing. 

