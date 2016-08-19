
=head1 NAME

LGTSeekMongo - Find Lateral Gene Transfer in sequencing data

=head1 SYNOPSIS

Need to put something useful here

=head1 DESCRIPTION

A module to run computes and process the output of data for purposes
of finding putative lateral gene transfer.

*** NOTE ***
This is a modified version of the original PM to just load the MongoDB. 
***********

=head1 AUTHOR - David R. Riley & Karsten B. Sieber 
James Matsumura (updated July 2016)

e-mail: Karsten.Sieber@gmail.com
jmatsumura@som.umaryland.edu

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

=head2 LGTSeek.pm

 Title   : LGTSeek.pm
 Usage   : Suite of subroutines used to identify LGT
 Routines:
        new                 : Create lgtseek object
        getGiTaxon          : Create gi2taxon object
=cut

package LGTSeekMongo;
our $VERSION = '1.12';
use warnings;
no warnings 'misc';
no warnings 'uninitialized';
use strict;
use version;

# Dependencies
use File::Basename;
use Data::Dumper;
use GiTaxon;
use Time::SoFar qw( runtime ); 
use Cwd;
$| = 1;

=head2 new2

 Title   : new2
 Usage   : my $lgtseek = LGTSeek->new2(\%options)
 Function: Creates a new LGTSeek object, key=>values take #1= %options, #2=  ~/.lgtseek.config 
 Returns : An instance of LGTSeek

=cut

sub new2 {
    my ( $class, $options ) = @_;

    # Usefull list for fileparse: @{$lgtseek->{'list'}}
    my $self = {
        sam_suffix_list => [ '.sam.gz', '.sam' ],
        bam_suffix_list => [
            '_resorted.\d+.bam', '_resorted\.bam', '\.gpg\.bam',  '_prelim\.bam', '_name-sort\.bam', '_pos-sort\.bam', '_psort\.bam', '
-psort\.bam',
            '\.psort\.bam',      '\.psrt\.bam',    '_nsort\.bam', '\.nsrt\.bam',  '\.srt\.bam',      '\.sorted\.bam',  '.bam'
        ],
        fastq_suffix_list   => [ qr/_[12]{1}\.f\w{0,3}q(.gz)?/, qr/_[12]{1}(\.\w+)?\.f\w*q(.gz)?/, qr/((_[12]{1})?\.\w+)?\.f\w*q(.gz)?/, '\.fastq\.gz', '\.f\w{0,3}q' ],
        fasta_suffix_list   => [ qr/.f\w{3}a(.gz)?/,            '.fasta',                          '.fa' ],
        mpileup_suffix_list => [ '.mpileup',                    '_COVERAGE.txt',                   '.txt' ],
        suffix_regex        => qr/\.[^\.]+/,
    };

=head
	(JM 2016) - Something is odd here and causing crashes. Leave out for now as it doesn't seem necessary for 
	the main functionality anyway. 
    ## Now open the config file
    ## First determine the proper file path for the config file
    if ( defined $options->{conf_file} and $options->{conf_file} =~ /^\~(.*)/ ) {
        $options->{conf_file} = File::HomeDir->my_home . $1;
    }    ## This is incase the user passed a config file like ~/config.file
    my $conf_file
        = defined $options->{conf_file}
        ? $options->{conf_file}
        : File::HomeDir->my_home . "/.lgtseek.conf";    ## Open --conf_file or the default ~/.lgtseek.conf
    ## Open the config file and build a hash of key=>value for each line delimited on white space
    if ( -e $conf_file ) {
        my %config;
        open( IN, "<", "$conf_file" ) or confess "Can't open conf_file: $conf_file\n";
        while (<IN>) {
            chomp;
            next if ( $_ =~ /^#/ );
            $_ =~ /(\w+)\s+([A-Za-z0-9-._\/: \@]+)/;
            my ( $key, $value ) = ( $1, $2 );
            map { $_ =~ s/\s+$//g; } ( $key, $value );    ## Remove trailing white space.
            $config{$key} = $value;
        }
        close IN or confess "*** Error *** can't close conf_file: $conf_file\n";
        ## Make sure all keys from --options and config.file have a value, priority goes to --option
        ## If a key was passed from --options use the --option=>value if avail, or use config.file=>value
        foreach my $opt_key ( keys %$options ) {
            $self->{$opt_key} = defined $options->{$opt_key} ? $options->{$opt_key} : $config{$opt_key};
        }
        ## Make sure all the keys from the config file have a value, use --options=>value if avail or use the config.file=>value
        foreach my $conf_key ( keys %config ) {
            $self->{$conf_key} = defined $options->{$conf_key} ? $options->{$conf_key} : $config{$conf_key};
        }
    }
    else {
=cut

    $self = $options;
    #}

    bless $self;
    return $self;
}

=head2 getGiTaxon

 Title   : getGiTaxon
 Usage   : my $gi2tax = $lgtseek->getGiTaxon({'host' => 'foobar.com'...});
 Function: Retrieve a GiTaxon object ready to assign taxonomic information
 Returns : A GiTaxon object
 Args    : A hash options to pass to GiTaxon. These could have been
           passed in globally. They can also be overridden here.

           taxon_dir - Directory where taxon information lives
           taxon_idx_dir - Directory where taxon indices can be created (or where they are)
           taxon_host - Hostname of taxon mongo database

=cut

sub getGiTaxon {
    my ( $self, $config ) = @_;
    if ( $self->{verbose} ) { print STDERR "======== &getGiTaxon: Start ========\n"; }

    # If we already have a gitaxon object we'll just return it.
    if ( !$self->{gitaxon} ) {

        # Apply any config options that came over.
        if ($config) {
            map { $self->{$_} = $config->{$_} } keys %$config;
        }

        # Create the object.
        $self->{gitaxon} = GiTaxon->new(
            {   'taxon_dir'  => $self->{taxon_dir},
                'chunk_size' => 10000,
                'idx_dir'    => $self->{taxon_idx_dir},
                'host'       => $self->{taxon_host},
                'type'       => 'nucleotide',
                'verbose'    => $self->{verbose},
            }
        );
    }
    if ( $self->{verbose} ) { print STDERR "======== &getGiTaxon: Finished ========\n"; }
    $self->time_check;
    return $self->{gitaxon};
}

=head2 &time_check

 Title   : time_check
 Usage   : $lgtseek->time_check;
 Function: Print STDERR the clock time that has passed since start.

=cut

sub time_check {
    my $self        = shift;
    my $no_optimize = 1;
    my $elapsed     = runtime( [$no_optimize] );
    if ( $self->{verbose} ) { print STDERR "Time Since Start: $elapsed\n"; }
}

1;

__END__
