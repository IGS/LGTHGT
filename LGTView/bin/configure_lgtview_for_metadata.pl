#!/usr/bin/perl

=head1 NAME

configure_lgtview_for_metadata.pl - Component of LGTview to rewrite the JavaScript in the
lgtview.js file so that custom graphs and filters can be present in the LGTView instance. 

=head1 SYNOPSIS

Extracts which metadata are to be used as charts and which as filters so that these fields can
be more easily customized in LGTView.

=head1 DESCRIPTION

This script expects a single file as input which is formatted in the following way:

LINE 1 - tab delimited values of whatever metadata fields should be represented by pie charts. Each
value should be followed by a pipe and then the text that should be the title of the chart display.

LINE 2 - tab delimited values with the metadata field followed by a pipe and then either a "n" 
or a "l" to designate whether to make this comparable to a number or letter (string) value respectively.
If a number is to be compared to, add in a greater than or less than symbol to determine whether or not
they want this to be filtered with min or max values. 

Please note that these metadata fields MUST match exactly what is found in the first line of the
metadata file that was used to load the site or else the site will not load properly.  

EXAMPLE:
name|Name	phone_number|Phone Number	occupation|Occupation
weight|n|>	age|n|<	address|l

Notice how there are no overlapping fields. While it would work to add in metadata fields for both
the chart and filter panels of LGTView, it would be a bit redundant in functionality as they both
accomplish the same thing. Instead, place variables that would lend themselves better to being part
of a larger group in the charts and those values that are likely to be highly individual into the
filters panel. For example, phone numbers would be better in the filters since it would be unlikely
that even two people have the same number but you may want to query by area code. Whereas 
characteristics like occupation or gender are better suited for the pie charts as they will form 
as a shared attribute across entities more easily.

In the future, this script will be called by a web form instead of taking a file in. The web form
can simply recreate the above format behind the curtain so no major modifications will need to be 
made here. 

=head1 USAGE

./configure_lgtview_for_metadata.pl my_new_metadata.out /path/to/lgtview.js

The first argument is a file that matches the format described above and the second argument is 
the path for where the lgtview.js file needs to be replacedd at. 

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;

my $tmpfile = "./tmp.js";
my $sawYou = 0;
my @splitVals;
my @filters;

# The next three variables will replace certain segments of the lgtview.js file
my $chartsString=''; # text for CHART SECTION
my $filtersString1=''; # text for FILTER SECTION 1
my $filtersString2=''; # text for FILTER SECTION 2
my $filterForm=''; # text for the form panel created for filters

if ( @ARGV != 2) {
	print "Incorrect number of arguments. Please view the 'usage' section at the top ".
		  "of this file for how to run this script.\n";
	exit(1);
}

open(my $infile, "<$ARGV[0]" || die "Can't open file $ARGV[0]");
open(my $lgtviewJS, "<$ARGV[1]" || die "Can't open file $ARGV[1]");
open(my $outfile, ">$tmpfile" || die "Can't open file $tmpfile");

while (my $line = <$infile>) {

	chomp($line);
	my @vals = split /\t/, $line;

	# If this is the first line, process this data differently
	if (!$sawYou) {

		foreach my $i (@vals) {
			@splitVals = split /\|/, $i;
			$chartsString .= "\taddWindow({'name': '$splitVals[0]',\n";
			$chartsString .= "\t\t'title': '$splitVals[1]',\n";
			$chartsString .= "\t\t'modname': '$splitVals[0]'\n";
			$chartsString .= "\t});\n";
		}

		$sawYou = 1;

	} else { # go here for second line processing

		foreach my $i (@vals) {
			@splitVals = split /\|/, $i;

			# Process numerics slightly different than strings
			if ($splitVals[1] eq 'n') {

				if ($splitVals[2] eq '>') {
					$splitVals[0] = "max " . $splitVals[0];
				} elsif ($splitVals[2] eq '<') {
					$splitVals[0] = "min " . $splitVals[0];
				}

				# Can't have spaces in JS variables. Modify input here. 
				&formatFiltersSection($splitVals[0],$splitVals[2]);

			# Process string filters here
			} else {

				&formatFiltersSection($splitVals[0],'');
			}
		}
	}
}

# Process these filters in a way that JS acccepts
my $combinedFilters = join ",", @filters;

# Build this now that we know all of the filters that ought to be present 
$filterForm .= "\tvar filterform = new Ext.form.Panel({\n";
$filterForm .= "\t\twidth: '100%',\n";
$filterForm .= "\t\tframe: true,\n";
$filterForm .= "\t\titems: [$combinedFilters]\n";
$filterForm .= "\t});\n";

# At this point all the JS formatted content which is needed to populate 
# the file is present. Now parse the original JS file and create a new
# custom version of it. 

my $inChartsSection = 0; # track position in charts section
my $inFilterSection1 = 0; # track position in filter section 1
my $inFilterSection2 = 0; # track position in filter Section 2
my $contentPrinted = 0; # use this to know whether or not JS has been appended

while (my $line = <$lgtviewJS>) {

	# Switch module can be added to Dockerfile later to clean this up a bit
	if ($line =~ /START CHART SECTION/) {
		$inChartsSection = 1;
		# Should reprint all these lines so that the JS file can be reused
		# by this script again.
		print $outfile $line;
	} elsif ($line =~ /END CHART SECTION/) {
		$inChartsSection = 0;
		print $outfile $line;
	} elsif ($line =~ /START FILTER SECTION 1/) {
		$inFilterSection1 = 1;
		$contentPrinted = 0;
		print $outfile $line;
	} elsif ($line =~ /END FILTER SECTION 1/) {
		$inFilterSection1 = 0;
		print $outfile $line;
	} elsif ($line =~ /START FILTER SECTION 2/) {
		$inFilterSection2 = 1;
		$contentPrinted = 0;
		print $outfile $line;
	} elsif ($line =~ /END FILTER SECTION 2/) {
		$inFilterSection2 = 0;
		print $outfile $line;
	} else {

		# Check and print all lines outside of these customizable boundaries
		if (!$inChartsSection && !$inFilterSection1 && !$inFilterSection2) {
			print $outfile $line;

		# Throughout the entirety of the customizable sections, only want to print
		# the accumulated content once 
		} elsif (!$contentPrinted) {

			# Finally, embed the customizable JS into the file
			if ($inChartsSection) {

				print $outfile $chartsString;

			} elsif ($inFilterSection1) {

				print $outfile $filtersString1;
				print $outfile $filterForm;

			} elsif ($inFilterSection2) {

				print $outfile $filtersString2;
			}
			
			$contentPrinted = 1;
		}
	}
}

# The last step now is to overwrite the file that was passed in as the JS for the site
# Keep a backup incase the user wants the original copy
`cp $ARGV[1] ./lgtview.bak.js`;
`mv $tmpfile $ARGV[1]`;

# Use this function to replace spaces with underscores and format the filters sections
sub formatFiltersSection {
	my ($metadata, $comparison) = @_;
	my $underscoresOnly = $metadata;
	my $compareBy='';
	$underscoresOnly =~ s/\s/\_/;

	# Build an array of all filter values. These need underscores as they require
	# tying to JS variables. 
	push @filters, $underscoresOnly;

	# Format the Filters Section 1
	$filtersString1 .= "\tvar $underscoresOnly = new Ext.form.field.Text({\n";
	$filtersString1 .= "\t\tfieldLabel: '$metadata',\n";
	$filtersString1 .= "\t\tname: '$underscoresOnly'\n";
	$filtersString1 .= "\t});\n";

	# Format the Filters Section 2
	$filtersString2 .= "\tif($underscoresOnly.getValue() != '') {\n";

	if ($comparison eq '') {
		$compareBy = "'\$regex': $underscoresOnly.getValue()};\n";
	} elsif ($comparison eq '>') {
		$compareBy = "'\$lt': $underscoresOnly.getValue()*1};\n";
	} elsif ($comparison eq '<') {
		$compareBy = "'\$gt': $underscoresOnly.getValue()*1};\n";
	}

	if ($metadata =~ /^max\s/ || $metadata =~ /min\s/) {
		$metadata =~ /\s(.*)/;
		$filtersString2 .= "\t\tallfilters['$1'] = " . "$compareBy";
	} else {
		$filtersString2 .= "\t\tallfilters['$metadata'] = " . "$compareBy";
	}

	$filtersString2 .= "\t}\n"
}
