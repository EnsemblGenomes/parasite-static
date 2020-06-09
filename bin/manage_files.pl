#!/usr/bin/env perl

=pod

=head1 SYNOPSIS

To provide a directory structure for static files for every genome in the core databases, creating
new directories where they do not yet exist:
 
   manage_files.pl
   
To look for all the expected markdown files for all B<published> genomes (the ones on the
WBPS web site), and list any that are missing
   
   manage_files.pl --find_missing

To create "placeholder" markdown files for all B<unpublished> genomes (those with a core database
but not yet on the web site), i.e. the files that need to be created for the next release:

   manage_files.pl --placeholders
   
=cut


use warnings;
use strict;
use feature 'say';

use ProductionMysql;

use Carp;
use File::Touch;
use Getopt::Long;
use IO::Socket::SSL;
use Text::Markdown;
use Try::Tiny;
use WWW::Mechanize;

BEGIN{
   foreach my $required (qw(PARASITE_VERSION ENSEMBL_VERSION WORMBASE_VERSION)) {
      die "$required environment variable is not defined (PARASITE_VERSION, ENSEMBL_VERSION and WORMBASE_VERSION all required): baling"
         unless defined $ENV{$required} && length $ENV{$required};
   }
}

use constant CORE_DB_REGEX       => qr/^([a-z]+_[a-z0-9]+)_([a-z0-9]+)_core_$ENV{PARASITE_VERSION}_$ENV{ENSEMBL_VERSION}_[0-9]+$/;
use constant WBPS_BASE_URL       => 'https://parasite.wormbase.org/';
use constant ROOT_DIR            => './species';
use constant SPECIES_MD_FILES    => ['.about.md'];
use constant BIOPROJECT_MD_FILES => ['.assembly.md', '.annotation.md', '.referenced.md'];
use constant PLACEHOLDER_SUFFIX  => '.placeholder';


my $root_dir = ROOT_DIR;
my ($find_missing,$placeholders,$help);
GetOptions ("root_dir=s"   => \$root_dir,
            "find_missing" => \$find_missing,
            "placeholders" => \$placeholders,
            "help"         => \$help,
            )
            || die "failed to parse command line arguments";
$help && die   "Usage:    $0 [options]\n\n"
            .  "Options:  --root_dir      root of new species/bioproject directory structure; default \"".ROOT_DIR."\"\n"
            .  "          --find_missing  find missing markdown files for published genomes\n"
            .  "          --placeholders  create placeholder markdown files for unpublished genomes\n"
            .  "          --help          this message\n"
            ;

my $wwwmech =  WWW::Mechanize->new( autocheck   => 1,
                                    ssl_opts    => {  SSL_verify_mode   => IO::Socket::SSL::SSL_VERIFY_NONE,
                                                      verify_hostname   => 0,
                                                      },
                                    )
               || die "failed to instantiate WWW::Mechanize: $!";
            
my %species_count = ();
CORE: foreach my $this_core_db ( ProductionMysql->staging->core_databases() ) {
  
   my($species, $bioproject);
   if( $this_core_db =~ CORE_DB_REGEX) {
      $species    = $1;
      $bioproject = $2;
   } else {
      # say "Ignoring: $this_core_db";
      next CORE
   }

   # core datbase names all lowercase, but paths on WBPS web site have capitalized genus
   $species = ucfirst($species);
   
   # get/create subdirectory for the bioproject
   my $species_dir            = join('/',$root_dir, $species);
   my $species_base_name      = $species;
   my $bioproject_dir         = create_subdir($root_dir, $species_base_name, $bioproject);
   my $bioproject_base_name   = $species.'_'.uc($bioproject);

   # get genome page from WBPS
   # path on WBPS web site is like "Acanthocheilonema_viteae_prjeb1697" (note capitalized genus)
   try {
      $wwwmech->get( WBPS_BASE_URL.$species.'_'.$bioproject );
      if($find_missing) {
         $species_count{$species} || find_missing_md($species_dir,$species_base_name,SPECIES_MD_FILES);
         find_missing_md($bioproject_dir,$bioproject_base_name,BIOPROJECT_MD_FILES);
      }
   } catch {
      my $msg = $_;
      # 404 is expected for new genomes; anything else is an error
      unless('404' eq $wwwmech->status()) {
         die $msg;
      }
      # say "Not yet published: ${species}_${bioproject}".($placeholders?' (creating placeholders)':'');
      if($placeholders) {
         $species_count{$species} || create_placeholders($species_dir,$species,SPECIES_MD_FILES);
         create_placeholders($bioproject_dir,$bioproject_base_name,BIOPROJECT_MD_FILES);
      }
   };
   
   ++$species_count{$species};   
}




# creates root->species->bioproject subirectory structure as required
# returns path of bioproject subd irectory
sub create_subdir
{  my($root, $species, $bioproject) = @_;
   die "create_subdirs() requires root directory, species and bioproject" unless $root && $species && $bioproject;

   my $species_dir      = join('/',$root, $species);
   my $bioproject_dir   = join('/',$root, $species, uc($bioproject));
   
   for my $this_dir ($root, $species_dir, $bioproject_dir) {
      if(-e $this_dir) {
         -d $this_dir || die "$this_dir exists, but isn't a directory";
      } else {
         mkdir($this_dir) || die "Couldn't create directory $this_dir: $!";
         touch(join('/',$this_dir,'.created'));
      }
   }
   
   return( $bioproject_dir );
}

# looks for missing MD files in a directory
# pass directory path, file name base and expected file suffixes
# returns ref to array of paths of missing files
sub find_missing_md
{  my($dir, $base, $expected) = @_;
   
   my $missing = [];
   list_md_files( $dir,
                  $base,
                  $expected,
                  sub{  my $this_file = shift();
                        unless( -e $this_file ) {
                           say "MISSING: $this_file";
                           push( @{$missing}, $this_file );
                        }     
                     }
                  );
      
   return( $missing );
}

# looks for missing MD files in a directory, and creates placeholders
# pass directory path, file name base and expected file suffixes
# returns ref to array of paths of placeholder files
sub create_placeholders
{  my($dir, $base, $expected) = @_;

   my $files = [];
   list_md_files( $dir,
                  $base,
                  $expected,
                  sub{  my $this_file = shift();
                        unless(-e $this_file) {
                           my $placeholder = $this_file.PLACEHOLDER_SUFFIX;
                           -e $placeholder || touch($placeholder);
                           say "NEW: $placeholder";
                           push( @{$files}, $placeholder );
                        }
                     }
                  );
   
   return( $files );
}

# provides list of MD files that are expected to exist in a directory
# pass directory path, file name base, and expected file suffixes
# returns ref to array of paths of expected files
sub list_md_files
{  my($dir, $base, $expected, $callback) = @_;
   confess "list_md_files() requires directory"              unless $dir && -d $dir;
   confess "list_md_files() requires file name base"         unless $base;
   confess "list_md_files() requires list of expected files" unless $expected  && ref([])    eq ref($expected);
   confess "list_md_files() callabck must be CODE ref"       unless !$callback || ref(sub{}) eq ref($callback);

   my @files = map($dir.'/'.$base.$_, @{$expected});
   
   if($callback) {
      map( $callback->($_), @files );
   }
   
   return( \@files );
}
