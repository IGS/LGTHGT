#!/usr/bin/perl -w

=head1 NAME

generateReport - Generate a tab-delimited report from a set of TwinBLAST inputs

=head1 SYNOPSIS

Generates a concise BLAST report for the user that details the following:

--------------------------------------------------------------------------------------------------------------------------------------------
| Query ID | Algorithm+Database | Length1 | Length2 | Top Hit 1 | Top Hit 2 | E-value  1 | E-value 2 | Strand 1 | Strand 2 | Curation Note |
--------------------------------------------------------------------------------------------------------------------------------------------
1. Query ID - The shared read ID of two pair mates
2. Algorithm+Database - The BLAST algorithm and database BLASTed against
3. Length 1 - Length of read 1
4. Length 2 - Length of read 2
5. Top Hit 1 - Best match to read 1
6. Top Hit 2 - Best match to read 2
7. E-value 1 - E-value for best match to read 1
8. E-value 2 - E-value for best match to read 2
9. Strand 1 - Strands for (query / hit)
10. Strand 2 - Strand (query / hit)
11. Curation Note - The presence of this field is determined by whether or
not the user added curation notes using TwinBLAST

=head1 DESCRIPTION

Script to pull the data from a paired set of BLAST files or a single file 
that has the results merge and has the mates of each pair following one
after the other.

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use lib '.';
use Bio::SearchIO;
use CGI;
use JSON;
use POSIX qw(strftime);
use Config::IniFiles;
use File::Slurp;
use MongoDB;
use URI::Escape;

my $conf = Config::IniFiles->new( -file => "$ENV{CONF}");
my $chosen_db = $ENV{CHOSEN_DB};
my $db = $conf->val($chosen_db, 'dbname');
my $host = $conf->val($chosen_db, 'hostname');
my $mongo_conn = MongoDB->connect($host);
my $mongo_db = $mongo_conn->get_database($db);
my $mongo_coll = $mongo_conn->get_collection('bwa_mapping');

# Deal with the CGI inputs.
my $cgi = CGI->new;
my $file = uri_unescape($cgi->param('file'));
my $list = uri_unescape($cgi->param('list'));
my $qlist = uri_unescape($cgi->param('qlist'));
my $print_report = $cgi->param('printreport');

# Web root for placing files that can be found by JS
my $web_root = $ENV{WEB_ROOT};

# Required prefix for all input files
my $prefix = $ENV{PREFIX};

# Required prefix for tmp directory
my $tmp_dir = $ENV{IMG_URL};

# Deal with a single blast file here
if($file) {
    $file = "$prefix/$file";
    $file =~ s/\/\//\//g;
}

if($qlist) {
	$qlist = "$prefix/$qlist";
	$qlist =~s /\/\//\//g;
}

# This block is all that is called when the 'download report' button
# is clicked through the site. This check is present to enable this 
# script to take on some additional functionality down the line. 
if($print_report){								  

	my $format = 'blast';
	my $searchio = Bio::SearchIO->new(-format => $format,
                                  -file   => $file);

	my $curr_id = '';
	my $prev_id = '';
	my $q1len = '';
	my $q2len = '';
	my $hit1 = '';
	my $hit2 = '';
	my $qid = '';
	my $qdb = '';
	my $algo = '';
	my $cur_note = '';
	my @res1;
	my @res2;
	my $do_include;
	my $qcount = 0;
	my $qtotal;

	if($qlist) {
		$do_include = read_file($qlist);
		$qtotal = $do_include =~ tr/\n//; # count number of new lines/entries
	}

	my $report_file	= "$tmp_dir/twinBLASTreport.tsv";
	my $out_location = $web_root . $report_file;
	open(my $fh, '>', $out_location) or die "Could not open file!";

	while (my $result = $searchio->next_result()) {
	
		my $qid = $result->query_name;
		$qid =~ /(.*)\//;
		$curr_id = $1;

		# If a subset is provided, only provide the results that matter
		if($qlist) {
			if ($qcount == $qtotal){
				last;
			}
			my $quoted_id = quotemeta($curr_id); # can't use \Q because need to include newline char
			unless($do_include =~ /$quoted_id\n/){ # careful, find exact matches
				next;
			} 
		}
	
		# If we have seen both mates of a pair, gather the rest of the info and output
		if($curr_id eq $prev_id){
	
			$cur_note = &getCurationNote($curr_id);
			$qdb = $result->database_name;
			$algo = $result->algorithm;
			$q2len = $result->query_length;
	
			# Build an array of results for top hit if hit is present
			$hit2 = $result->next_hit;
			@res1 = &getTopHitInfo($hit1);	
			@res2 = &getTopHitInfo($hit2);
	
			print $fh "$curr_id\t$algo+$qdb\t$q1len\t$q2len\t$res1[1]\t$res2[1]\t$res1[0]\t$res2[0]\t$res1[3]\t$res2[3]\t$res1[2]\t$res2[2]\t$cur_note\n";

			if($qlist) {
				$qcount++;
			}

			undef(@res1); # remove any straggler data for next round
			undef(@res2); 
	
		} else {
	
			$prev_id = $curr_id;
			$q1len = $result->query_length;
	
			$hit1 = $result->next_hit;
		}
	}
	
	close $fh;
	$dbh->disconnect();

	print "Content-Type: application/json\n\n";
	print to_json({message => "finished", success => 1, path => "$report_file"});
	exit;
}

# Function to query the DB for the particular curation note given a sequence ID
sub getCurationNote {
	my($query_id) = @_;
	my $cur_res = $mongo_coll->( { 'read' => "$query_id" } );
	my @arr = $cur_res->next; # grab doc from cursor
	my $curation_note = $arr[0]->{'curation_note'};
	if(not defined $curation_note){
		$curation_note='';
	}
	return $curation_note;
}

# Function to get the data tied to the top hit from a SearchIO result. Will handle
# the case where the top hit is not present.
sub getTopHitInfo {
	my($top_hit) = @_;
	my @results;
	if(defined $top_hit) {
		$results[0] = $top_hit->length;
		$results[1] = $top_hit->accession();
		$results[1] .= ":".$top_hit->description();
		$results[2] = $top_hit->strand('query');
		$results[2] .= "/".$top_hit->strand('hit');
		$results[3] = $top_hit->significance();
	} else {$results[1] = "No significant hit found";}
	return @results;
}
