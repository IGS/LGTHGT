#!/usr/bin/perl
use strict;
use MongoDB;
use MongoDB::Code;
use CGI;
use File::Basename;
use Data::Dumper;
use JSON;
use lib (`ktGetLibPath`);
use KronaTools;
use Digest::MD5 qw(md5_hex);

my $cgi = CGI->new;

my $TMP_DIR = '/var/www/html/tmp';
my $TMP_URL = '/tmp';

my $host = $cgi->param('host');
my $db = $cgi->param('db');
my $list = $cgi->param('coll');
my $criteria = $cgi->param('criteria');
my $cond = $cgi->param('cond');
my $condfield = $cgi->param('condfield');
my $group = $cgi->param('group');
my $start = $cgi->param('start');
my $limit = $cgi->param('limit');
my $format = $cgi->param('format') ? $cgi->param('format') : 'json';
my $filter_limit = $cgi->param('flimit');
my $file_format = $cgi->param('file_format');
my $site_holder = $cgi->param('site');

my $mongo_conn = MongoDB->connect($host);
#$mongo_conn->query_timeout(-1);
my $mongo_db = $mongo_conn->get_database($db);
my $mongo_coll = $mongo_db->get_collection('bwa_mapping');
my $outputcollname = "$criteria\_mappings";
$outputcollname =~ s/\s/_/g;
my $outputcoll = $mongo_db->get_collection($outputcollname);
my $result;

my $json = JSON->new;
$json->allow_blessed;
$json->convert_blessed;

if($format eq 'krona') {
    &makeKronaTree();
    exit;
}

# Regardless of the types of conditions passed, always want to
# remove old instances of the curation counts as these can be 
# updated in TwinBLAST and will not be recognized as having changed
# due to the way this script was originally set up. Thus, this next
# step aims to remove old collections/counts so that they have to 
# be rebuilt each time ensuring any change is recognized.
my @cols = $mongo_db->collection_names;
foreach my $col_map (@cols) {
    local $_ = $col_map;
    if ( m/^curation\_note.*/ ) {
        my $coll_to_drop = $mongo_db->get_collection($col_map);
        $coll_to_drop->drop;
    }
}

print STDERR "output to $outputcollname\n";
if(!$outputcoll->find_one() && (!$cond || !$condfield)) {
    print STDERR "Running map reduce 1\n";
#    &runMapReduce();
}

if($criteria =~ /\./) {
    print STDERR "running mapreduce 2\n";
    &runMapReduce2();
    &pullFromColl();
}

elsif($criteria && $cond) {
    print STDERR "running map reduce 3\n";
    &runMapReduce3();
    &pullFromColl();
}
elsif($criteria) {
    print STDERR "pulling from coll 1\n";
    &pullFromColl();
}
else {
    &pullFromColl2();
}


if($format eq 'text') {
    my $md5 = md5_hex(to_json($cgi->Vars));
    my $keys = [];

	# Need to do a little extra checking here whether this file is being generated
	# for the user as a download ('dl') or it is to be used in the generation of a
	# heatmap and is input for an R script ('local'). 
	my $outfile = "lgtview_$db\_$md5.txt";
	my $out;

	if($file_format eq 'dl') {
    	print "Content-Disposition: attachment; filename=$outfile\n\n";
	}

	elsif($file_format eq 'local') {
		open($out, ">$TMP_DIR/$outfile" || die "Can't open file $TMP_DIR/$outfile");
	}

    my $headers = [];
    map {
        push(@$headers,$_->{header});
    } @{$result->{metaData}->{columns}};

    map {
        push(@$keys,$_->{name});
    } @{$result->{metaData}->{fields}};

	if($file_format eq 'dl') {
    	print join("\t",@$headers);
    	print "\n";
	}

	elsif($file_format eq 'local') {
    	print $out join("\t",@$headers);
    	print $out "\n";
	}

    foreach my $row (@{$result->{retval}}) {
        my @vals;
        foreach my $key (@$keys) {
            if(ref($row->{$key}) eq 'ARRAY') {
                push(@vals,join(';',@{$row->{$key}}));
            }
            else {
                chomp $row->{$key};
                push(@vals,$row->{$key});
            }
        }

		if($file_format eq 'dl') {
        	print join("\t",@vals);
        	print "\n";
		}

		elsif($file_format eq 'local') {
        	print $out join("\t",@vals);
        	print $out "\n";
		}
    }

	# Now that the file is present, use it to run the heatmap R script
	if($file_format eq 'local') {

		# These are all the params, in order, required for the R script
		my $infile = $cgi->param('infile');
		my $tax_rank = $cgi->param('tax_rank');
		my $chosen_metadata = $cgi->param('chosen_metadata');
		my $abudance_type = $cgi->param('abundance_type');
		my $filter = "$TMP_DIR/$outfile";
	}
}

else {
    
    print "Content-type: text/plain\n\n";
    print $json->encode($result);
}

sub makeKronaTree {
    my $tree = newTree();
    my $md5 = md5_hex(to_json($cgi->Vars));

    if(-e "$TMP_DIR/$md5.html") {
        print "Content-type: text/plain\n\n";
        print to_json({'file' => "$TMP_URL/$md5.html"});
        #print `cat $md5.html`;
        exit;
    }
    setOption('out',"$TMP_DIR/$md5.html");
    setOption('name', 'all');
    my $condhash = {};
    my $field = $condfield;
    if($cond) {
        $condhash = from_json($cond);
    }
    print STDERR Dumper $condhash;
    my $cursor = $mongo_coll->query($condhash)->fields({$field=>1});
    my @res = $cursor->all();
    
    my $set =0;
    foreach my $r (@res) {
        if($r->{$field} && @{$r->{$field}}) {
            addByLineage($tree, $set, $r->{$field}, undef, 1);
        }
    }
    my @attributeNames = ('magnitude');

    my @attributeDisplayNames = ('Total');

    print "Content-type: text/plain\n\n";
    writeTree(
        $tree,
        \@attributeNames,
        \@attributeDisplayNames,
        []);
    print to_json({'file' => "$TMP_URL/$md5.html"});
    #print `cat $md5.html`;
}

sub pullFromColl2 {
    my $condhash = {};
    if($cond) {
        $condhash = from_json($cond);
    }
    my $cursor = $mongo_coll->query($condhash);
#    my $cursor = $mongo_coll->query($condhash)->limit($limit)->skip($start)->fields({'read'=>1});
    my $total = $cursor->count();
    my $fields = [];
    my $columns = [];
    my $limitcursor;
    if(defined($start) && defined($limit)) {
        $limitcursor = $cursor->skip($start)->limit($limit);
    }
    else {
        $limitcursor = $cursor;
    }
    my @res = $limitcursor->all();
    my $i = 0;
    foreach my $key (keys %{$res[0]}) {
        push(@$columns,{'header' => "$key ($i)", 'dataIndex' => $key});
        push(@$fields, {'name' => $key});
        $i++;
    }
#    my @res = $cursor->skip($start)->limit($limit)->all();
    $result = {'total'=> $total,'retval' => \@res, 'metaData' => {'fields' => $fields,'columns' => $columns}};
}

sub pullFromColl {

    my $cursor = $outputcoll->find({});
    $cursor->sort({'value.count' =>1});
    my @res = $cursor->all();
    my @retval;
    my $len = scalar @res;
    my $min = 10;
    my $other = {'_id' => 'Other', 'count' => 0};
    
    my $total = 0;
    if($len > 200) {
        map {$total += $_->{value}->{count}; }@res;
    } 

    foreach my $ret (@res) {
        my $id = $ret->{'_id'} ? $ret->{'_id'} : 'Unknown';
        if($len <= 200 || ($len > 200 && $ret->{value}->{count}/$total >= .001)) {
        push(@retval, {'_id' => $id,
                       'count' => $ret->{value}->{count}});
        }
        else {
            $other->{count} += $ret->{value}->{count};
        }
    }
    if($other->{count}) {
        push(@retval, $other);
    }
#   my @srted_vals = sort {$a->{'_id'} <=> $b->{'_id'}} @res;
    $result = {'retval' => \@retval};
}

sub runMapReduce {
    my $map = <<MAP;
    function() {
        emit(this.$criteria, {count:1});
    }
MAP
        
    my $reduce = <<RED;
    function(key,values) {
        var result = {count:0.0};
        values.forEach(function(value) {
            result.count += value.count;
                       });
        return result;
    }
RED
        
    my $cmd = Tie::IxHash->new("mapreduce" => "bwa_mapping",
                               "map" => $map,
                               "reduce" => $reduce,
                               "out" => $outputcollname);
                               
    $mongo_db->run_command($cmd);

}

sub runMapReduce2 {

    my ($list,$val) = split(/\./,$criteria);
    my $scond = $cond ? from_json($cond) : undef;
    my $mapconds = [];
    my $otherconds = {};
    if($cond) {
        map {
            my $key = $_;
            if($key =~ /$list/) {
                $key =~ s/$list\.//;
                my $val = $scond->{$_};
                my $noteq = JSON::false;
                if(ref $scond->{$_} eq 'HASH') {
                    my @keys = keys %{$scond->{$_}};
                    $val = $scond->{$_}->{$keys[0]};
                    if($keys[0] eq '$ne') {
                        $noteq = JSON::true;
                    }
                }
                push(@$mapconds, {
                    'key' => $key,
                    'value' => $val,
                    'noteq' => $noteq
                });
            }
            else {
                $otherconds->{$_} = $scond->{$_};
            }
        } keys %$scond;
    }
    my $mapcondsjson = $json->encode($mapconds);
    my $map = <<MAP;
    function() {
        var conds = $mapcondsjson;
        var thiselm = this;
        var seen = {};
        var goods = [];
        var ggood = true;
        this.$list.forEach(
            function(h) {
                var good = true;
                if(conds.length > 0 && !seen[h.$val]) {
                    conds.forEach(
                        function(c) {
                            if(!c.noteq && h[c.key] != c.value) {                            
                                good = false;
                            }
                            else if(c.noteq && h[c.key] == c.value) {                            
                                good = false;
                                ggood = false;
                            }

                    });
                }
                if(good && !seen[h.$val]) {
                    goods.push(h.$val);
                    seen[h.$val] = true;
                }
            }
        );
        if(ggood) {
            goods.forEach(
                function(v) {
                    emit(v, {count:1});
                }
            );
        }
    }
    
MAP

    my $reduce = <<RED;
    function(key,values) {
        var result = {count:0.0};
        values.forEach(function(value) {
            result.count += value.count;
                       });
        return result;
    }
RED
#    print STDERR $map;
#    print STDERR $reduce;
    my $first = $scond ? $json->encode($scond) : '';
    my $second = $otherconds ? $json->encode($otherconds) : '';
    my $checksum = md5_hex(join('_',$first,$second,$list,$val));
    $outputcollname = "$list\_$val\_".$checksum."\_mappings";
#    print STDERR "$outputcollname\n";
    $outputcoll = $mongo_db->get_collection($outputcollname);
    if(!$outputcoll->find_one()) {
        my $cmd = Tie::IxHash->new("mapreduce" => "bwa_mapping",
                                   "map" => $map,
                                   "reduce" => $reduce,
                                   "out" => $outputcollname,
                                   "query" => $otherconds
            );
#        if($cond) {
#            $cmd->{cond} = $scond;
#        }
        $mongo_db->run_command($cmd);
    }
}
sub runMapReduce3 {

    my $scond = $cond ? from_json($cond) : undef;
    my $mapconds = [];
    my $otherconds = {};
    
    my $map = <<MAP;
    function() {
        emit(this['$criteria'], {count:1});
    }
    
MAP

    my $reduce = <<RED;
    function(key,values) {
        var result = {count:0.0};
        values.forEach(function(value) {
            result.count += value.count;
                       });
        return result;
    }
RED

    my $first = $scond ? $json->encode($scond) : '';
    my $checksum = md5_hex($first);
    $outputcollname = "$criteria\_".$checksum."\_mappings";
    $outputcollname =~ s/\s/_/g;
#    print STDERR "$outputcollname\n";
#    print STDERR $scond;
    $outputcoll = $mongo_db->get_collection($outputcollname);
    if(!$outputcoll->find_one()) {
        print STDERR "Loading $outputcollname\n";
        my $cmd = Tie::IxHash->new("mapreduce" => "bwa_mapping",
                                   "map" => $map,
                                   "reduce" => $reduce,
                                   "query" => $scond,
                                   "out" => {"replace" => $outputcollname}
            );
#        if($cond) {
#            $cmd->{cond} = $scond;
#        }
#        print STDERR Dumper $cmd;
        $mongo_db->run_command($cmd);
    }
}

sub dogroup {
    my $red = <<GROUP;
    function(obj,out){
        out.count++;
    }
GROUP
    my $scond = $cond ? from_json($cond) : undef;
    my $cmd = {
        group => {
            'ns' => 'bwa_mapping',
            'key' => {$criteria => 1},
            'initial' => {'count' => 0.0},
            '$reduce' => MongoDB::Code->new(code => $red)
#            'cond' => $condfield { => {'$regex' => qr/^$cond/}}
        }
    };
##    if($condfield eq 'scientific') {
 #       $cmd->{group}->{cond} = {$condfield => {'$regex' => qr/^$cond/}};
 #   }
 #   else {
        $cmd->{group}->{cond} = $scond;
#    }
    $result = $mongo_db->run_command($cmd);
    my @retval;
    my $res = $result->{retval};
    my @srted = sort {$a->{count} <=> $b->{count}} @$res;
    foreach my $ret (@srted) {
        my $id = $ret->{$criteria} ? $ret->{$criteria} : 'Unknown';
        push(@retval, {'_id' => $id,
                       'count' => $ret->{count}});
    }
    $result = {'retval' => \@retval};
}
