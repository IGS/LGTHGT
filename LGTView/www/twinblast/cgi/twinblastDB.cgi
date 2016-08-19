#!/usr/bin/perl -w

=head1 NAME

twinblastDB - Component to access a DB for curation purposes using TwinBlast

=head1 SYNOPSIS

Communicates curation/annotations from TwinBlast page to a DB.

=head1 DESCRIPTION

This script uses MySQL but can be reconfigured to work with other DBs.

=head1 AUTHOR - James Matsumura

e-mail: jmatsumura@som.umaryland.edu

=cut

use strict;
use CGI;
use MongoDB;
use JSON;
use Config::IniFiles;

my $cgi = CGI->new;
my $conf = Config::IniFiles->new( -file => "$ENV{CONF}");
my $chosen_db = $ENV{CHOSEN_DB};

# Deal with the CGI inputs.
my $id = $cgi->param('seq_id');
my $annot = $cgi->param('annot_note'); # annotation note

my $db = $conf->val($chosen_db, 'dbname');
my $host = $conf->val($chosen_db, 'hostname');
my $mongo_conn = MongoDB->connect($host);
my $mongo_db = $mongo_conn->get_database($db);
my $mongo_coll = $mongo_db->get_collection('bwa_mapping');

# Update the curation note for the document denoting a pair of reads.  
$mongo_coll->update_one({ 'read' => $id }, { '$set' => { 'curation_note' => $annot } });
