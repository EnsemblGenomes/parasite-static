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
use File::Slurp;
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
use constant BIOPROJECT_MD_FILES => ['.summary.md', '.assembly.md', '.annotation.md', '.resources.md', '.publication.md'];
use constant PLACEHOLDER_SUFFIX  => '.placeholder';


my $root_dir = ROOT_DIR;
my ($find_missing,$create_missing,$placeholders,$help);
GetOptions ("root_dir=s"      => \$root_dir,
            "find_missing"    => \$find_missing,
            "create_missing"  => \$create_missing,
            "placeholders"    => \$placeholders,
            "help"            => \$help,
            )
            || die "failed to parse command line arguments";
$help && die   "Usage:    $0 [options]\n\n"
            .  "Options:  --root_dir         root of new species/bioproject directory structure; default \"".ROOT_DIR."\"\n"
            .  "          --find_missing     find missing markdown files for published genomes\n"
            .  "          --create_missing   create missing markdown files for published genomes from deprecated database\n"
            .  "          --placeholders     create placeholder markdown files for unpublished genomes\n"
            .  "          --help             this message\n"
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

   # core database names all lowercase, but paths on WBPS web site have capitalized genus
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
         # print list of markdown files that are missing
         unless($species_count{$species}) {
            map {say} @{find_missing_md($species_dir,$species_base_name,SPECIES_MD_FILES)};
         }
         map {say} @{find_missing_md($bioproject_dir,$bioproject_base_name,BIOPROJECT_MD_FILES)};
      }
      if($create_missing) {
         # create HTML files that are missing or empty
         my %html_files = (   species     => join('/', $species_dir,     "${species_base_name}.about.html"),
                              summary     => join('/', $bioproject_dir,  "${bioproject_base_name}.summary.html"),
                              assembly    => join('/', $bioproject_dir,  "${bioproject_base_name}.assembly.html"),
                              annotation  => join('/', $bioproject_dir,  "${bioproject_base_name}.annotation.html"),
                              publication => join('/', $bioproject_dir,  "${bioproject_base_name}.publication.html"),
                              resources   => join('/', $bioproject_dir,  "${bioproject_base_name}.resources.html"),
                              );
         # get static content for species
         # if this returns nothing, the database doesn't include this species so we won't proceed further
         if(my $species_static_content = get_static_content(static_species => $species_base_name, 'description')) {
            foreach my $field (keys %html_files) {
               # create HTML file unless a non-empty one exists
               unless(-s $html_files{$field}) {
                  my $static_content;
                  if('species' eq $field) {
                     # already got this
                     $static_content =$species_static_content;
                  } else {
                     $static_content = get_static_content(static_genome => $bioproject_base_name, $field) || '';
                  }
                  if($static_content) {
                     File::Slurp::overwrite_file($html_files{$field}, {binmode => ':utf8'}, $static_content) || die "failed to write ".$html_files{$field}.": $!";
                     say $html_files{$field};
                  }
               }
               # if there is an HTML file (an old one, or a newly created one) create markdown
               if(-s $html_files{$field}) {
                  # note this won't craete a md file if one exists and isn't empty
                  my $md = markdown_from_html($html_files{$field});
                  $md && say $md;
               }
            } # foreach my $field
         } # if(my $species_static_content
      } # if($create_missing)
   } catch {
      my $msg = $_;
      # 404 is expected for new genomes; anything else is an error
      unless('404' eq $wwwmech->status()) {
         confess $msg;
      }
      # say "Not yet published: ${species}_${bioproject}".($placeholders?' (creating placeholders)':'');
      if($placeholders) {
         unless($species_count{$species}) {
            map {say} @{create_placeholders($species_dir,$species,SPECIES_MD_FILES)};
         }
         map {say} @{create_placeholders($bioproject_dir,$bioproject_base_name,BIOPROJECT_MD_FILES)};
      }
   };
   
   ++$species_count{$species};   
}

# creates root->species->bioproject subirectory structure as required
# returns path of bioproject subd irectory
sub create_subdir
{  my $this = (caller(0))[3];
   my($root, $species, $bioproject) = @_;
   die "$this requires root directory, species and bioproject" unless $root && $species && $bioproject;

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
                           push( @{$missing}, $this_file );
                        }     
                     }
                  );
      
   return( $missing );
}

# looks for missing MD files in a directory, and creates placeholders
# pass directory path, file name base and expected file suffixes
# returns ref to array of paths of placeholder files
# (N.B. if there were any placeholder files already in existence,
# these are included in the array referenced by the return value)
sub create_placeholders
{  my($dir, $base, $expected) = @_;

   my $placeholders = [];
   list_md_files( $dir,
                  $base,
                  $expected,
                  sub{  my $this_file = shift();
                        unless(-e $this_file) {
                           my $placeholder = $this_file.PLACEHOLDER_SUFFIX;
                           -e $placeholder || touch($placeholder);
                           push( @{$placeholders}, $placeholder );
                        }
                     }
                  );
   
   return( $placeholders );
}

# provides list of MD files that are expected to exist in a directory
# pass directory path, file name base, and expected file suffixes
# returns ref to array of paths of expected files
sub list_md_files
{  my $this = (caller(0))[3];
   my($dir, $base, $expected, $callback) = @_;
   confess "$this requires directory"              unless $dir && -d $dir;
   confess "$this requires file name base"         unless $base;
   confess "$this requires list of expected files" unless $expected  && ref([])    eq ref($expected);
   confess "$this callabck must be CODE ref"       unless !$callback || ref(sub{}) eq ref($callback);

   my @files = map($dir.'/'.$base.$_, @{$expected});
   
   if($callback) {
      map( $callback->($_), @files );
   }
   
   return( \@files );
}

# gets the static content from ensembl_production_parasite database
# (deprecated: the content here is no longer being maintained)
# pass the table, name and field required
# returns description as string
sub get_static_content
{  my $this = (caller(0))[3];
   my($table, $name, $field) = @_;
   die "$this requires table name"           unless $table;
   die "$this requires species/genome name"  unless $name;
   die "$this requires field name"           unless $field;

   my @field_content = ();
   try {
      my $db_cmd = qq(mysql-pan-prod -Ne 'SELECT $field FROM ensembl_production_parasite.$table where species_name="$name"');
      open(DB, " { $db_cmd 2>&1 1>&3 | grep -v \"can be insecure\" 1>&2; } 3>&1 |");
      while(my $rec = <DB>) {
         chomp $rec;
         push(@field_content, $rec) if $rec;
      }   
      close(DB);
      scalar(@field_content) < 2 || die "expected zero or one record but got ".scalar(@field_content). "(command: $db_cmd)";
   } catch {
      my $msg = $_;
      die "database error: $msg";
   };
   
   return( ($field_content[0] && 'NULL' ne $field_content[0]) ? $field_content[0] : undef );
}

# creates markdown file from HTML
# this isn't a good way to do it, buit it will populate files if we don't yet
# have markdown but HTML has previously been added to the database
# pass HTML file name, which must exist
# returns undef is markdown file existed already; otherwise name of newly created markdown file name
sub markdown_from_html
{  my $this = (caller(0))[3];
   my($html_file) = @_;
   die "$this requires name of existing HTML file" unless $html_file && -e $html_file;
   
   my $md_file = $html_file;
   $md_file =~ s/\.html$/\.md/ || die "failed to create markdown file name corresponding to $html_file";

   return(undef) if -s $md_file;
   
   my $html = File::Slurp::read_file($html_file);
# TO DO: transform into MD!
my $markdown = $html;
   File::Slurp::overwrite_file($md_file, {binmode => ':utf8'}, $markdown) || die "failed to write $md_file: $!";
   
   return($md_file);
}

