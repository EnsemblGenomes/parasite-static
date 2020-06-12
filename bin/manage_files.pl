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

# used to figure out which databases on staging server are core DBs
use constant CORE_DB_REGEX             => qr/^([a-z]+_[a-z0-9]+)_([a-z0-9]+)_core_$ENV{PARASITE_VERSION}_$ENV{ENSEMBL_VERSION}_[0-9]+$/;
# looks here to see if a genome has been published
use constant WBPS_BASE_URL             => 'https://parasite.wormbase.org/';
# files are created under this path
use constant ROOT_DIR                  => './species';
# database holding static content created by deprecated process
use constant STATIC_CONTENT_DB         => 'ensembl_production_parasite';
# suffix for placeholder files, allowing them to be differentiated on disc from "real" markdown files
use constant PLACEHOLDER_SUFFIX        => '.placeholder';
# file describing species has this name, prefixed with name of species, suffixes with '.md' or '.html'
use constant SPECIES_FILE              => 'about';
# database table and field with species static content
use constant SPECIES_STATIC_FIELD      => 'description';
use constant SPECIES_STATIC_TABLE      => 'static_species';
# database table and field with bioproject static content
# (bioproject file names and field names are the same so there's no separate constant for files)
use constant BIOPROJECT_STATIC_FIELDS  => [qw(summary assembly annotation resources publication)];
use constant BIOPROJECT_STATIC_TABLE   => 'static_genome';


my $root_dir = ROOT_DIR;
my ($find_missing,$create_missing,$placeholders,$md_to_html,$help);
GetOptions ("root-dir=s"      => \$root_dir,
            "find-missing"    => \$find_missing,
            "create-missing"  => \$create_missing,
            "placeholders"    => \$placeholders,
            "md2html"         => \$md_to_html,
            "help"            => \$help,
            )
            || die "failed to parse command line arguments";
$help && die   "Usage:    $0 [options]\n\n"
            .  "Options:  --root-dir         root of new species/bioproject directory structure; default \"".ROOT_DIR."\"\n"
            .  "          --find-missing     find missing markdown files for published genomes\n"
            .  "          --create-missing   create missing HTML and markdown files for published genomes from deprecated database\n"
            .  "          --placeholders     create placeholder markdown files for unpublished genomes\n"
            .  "          --md2html          create missing HTML files from markdown files\n"
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
            map {say} @{find_missing_md($species_dir,$species_base_name,['.'.SPECIES_FILE.'.md'])};
         }
         map {say} @{find_missing_md($bioproject_dir,$bioproject_base_name,[map {'.'.$_.'.md'} @{+BIOPROJECT_STATIC_FIELDS}])};
      }
      
      if($create_missing) {
         # create HTML files that are missing or empty
         
         # this hash stores the files to be created
         # 'species' in awkward as the db field name and the file name don't match...
         my %html_files = ( species => join('/', $species_dir, "${species_base_name}.".SPECIES_FILE.".html") );
         # ...but all other cases are files for the bioproject, where field names match file names
         foreach my $field ( @{+BIOPROJECT_STATIC_FIELDS} ) {
            $html_files{$field} = join('/', $bioproject_dir,  "${bioproject_base_name}.${field}.html"),
         }
         
         # get static content for species
         # if this returns nothing, the database doesn't include this species so we won't proceed further
         if(my $species_static_content = get_static_content(SPECIES_STATIC_TABLE, $species_base_name, SPECIES_STATIC_FIELD)) {
            foreach my $field (keys %html_files) {
               # create HTML file unless a non-empty one exists
               unless(-s $html_files{$field}) {
                  my $static_content;
                  if('species' eq $field) {
                     # already got this
                     $static_content =$species_static_content;
                  } else {
                     $static_content = get_static_content(BIOPROJECT_STATIC_TABLE, $bioproject_base_name, $field) || '';
                  }
                  if($static_content) {
                     File::Slurp::overwrite_file($html_files{$field}, {binmode => ':utf8'}, $static_content."\n") || die "failed to write ".$html_files{$field}.": $!";
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
      
      if($md_to_html) {
         # create missing HTML files from markdown files
         my @md_files = ();
         unless($species_count{$species}) {
            push( @md_files,
                  join('/',$species_dir,$species_base_name.'.'.SPECIES_FILE.'.md')
                  );
         }
         push( @md_files,
               map   {  join( '/',
                              $bioproject_dir,
                              $bioproject_base_name.'.'.$_.'.md'
                              )
                        }
                     @{+BIOPROJECT_STATIC_FIELDS}
               );
         # call html_from_markdown for each mardown file that exists on disk,
         # and "say" each file name returned
         map {$_ && say $_} map {-e $_ && html_from_markdown($_)} @md_files;
      }
      
   } catch {
      my $msg = $_;
      # 404 is expected for new genomes; anything else is an error
      unless('404' eq $wwwmech->status()) {
         confess $msg;
      }
      # say "Not yet published: ${species}_${bioproject}".($placeholders?' (creating placeholders)':'');
      if($placeholders) {
         unless($species_count{$species}) {
            map {say} @{create_placeholders($species_dir,$species,['.'.SPECIES_FILE.'.md'])};
         }
         map {say} @{create_placeholders($bioproject_dir,$bioproject_base_name,[map {'.'.$_.'.md'} @{+BIOPROJECT_STATIC_FIELDS}])};
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
         # creating this file just allows the directory structure to be pushed to git, even if a diretcory is empty
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

# gets the static content from the database
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
      my $db_cmd = qq(mysql-pan-prod -Ne 'SELECT $field FROM ).STATIC_CONTENT_DB.qq(.$table where species_name="$name"');
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


# creates HTML file from markdown unless an HTML file already exists and has non-zero size
# pass markdown file name, which must exist
# returns undef is HTML file existed already, otherwise name of newly created HTML file name
sub html_from_markdown
{  my $this = (caller(0))[3];
   my($md_file) = @_;
   die "$this requires name of existing markdown file" unless $md_file && -e $md_file;
   
   my $html_file = $md_file;
   $html_file =~ s/\.md$/\.html/ || die "failed to create HTML file name corresponding to $md_file";

   return(undef) if -s $html_file;
   
   my $markdown = File::Slurp::read_file($md_file);
   return(undef) unless $markdown =~ m/\S/;

   my $html =  "<!-- Created by $0 from $md_file on ".scalar(localtime(time()))." -->\n\n"
            .  Text::Markdown::markdown( $markdown );
   
   File::Slurp::overwrite_file($html_file, {binmode => ':utf8'}, $html."\n") || die "failed to write $html_file: $!";
   
   return($html_file);
}



# creates markdown file from HTML unless a markdown file already exists and has non-zero size
# this is NOT a good way to do it, buit it will populate files if we don't yet have markdown
# but HTML has previously been added to the database
# pass HTML file name, which must exist
# returns undef is markdown file existed already, otherwise name of newly created markdown file name
sub markdown_from_html
{  my $this = (caller(0))[3];
   my($html_file) = @_;
   die "$this requires name of existing HTML file" unless $html_file && -e $html_file;
   
   my $md_file = $html_file;
   $md_file =~ s/\.html$/\.md/ || die "failed to create markdown file name corresponding to $html_file";

   return(undef) if -s $md_file;
   
   my $html = File::Slurp::read_file($html_file);
   return(undef) unless $html =~ m/\S/;
   
   my $markdown = "[//]: # (Created by $0 from $html_file on ".scalar(localtime(time())).")\n";
   
   my $parser;
   try {
      # HTML::Parser needs the HTML to end with a newline or it fails to trigger the handler for the last token :-/
      $parser = new HTMLStaticContentParser->parse($html."\n") || die "HTML parsing error: $!";
   } catch {
      my $msg = $_;
      die "Failed to parse $html_file: $msg";
   };
   $markdown .= $parser->markdown() // '';
   
   File::Slurp::overwrite_file($md_file, {binmode => ':utf8'}, $markdown."\n") || die "failed to write $md_file: $!";
   
   return($md_file);
}


###   HTMLStaticContentParser   ###################################################################################################
# 
#       Subclasses HTML::Parser to parse HTML static content, and convert it to markdown.
# 
#       Only intended to cope with the subset of HTML actually used in the static content found in the
#       static_species and static_genome tables of ensembl_production_parasite!
#       

package HTMLStaticContentParser;

use Carp;
use HTML::Parser;
use HTML::Entities;
use base qw(HTML::Parser);

# Accessor for markdown.
# Optionally, a pair arguments can be passed (passing just one arg is an error); first arg must be 'set'
# or 'append', and second argument is a string:  'set' causes the stored markdown to be set to the string
# (replacing existing markdown), and 'append' causes the string to be appended to the existing markdown.
# Return value is the markdown (after any set/append operation)
sub markdown
{  my($self,$action,$md) = @_;
   my $this = (caller(0))[3];
   if($action) {
      confess "when an action param is passed to $this it must be 'set' or 'append'" unless grep {$_ eq $action} qw(set append);
      confess "when an action param is passed to $this, a value must also be passed" unless defined $md;
      if( 'set' eq $action ) {
         $self->{__MARKDOWN__} = $md;
      } elsif( 'append' eq $action ) {
         $self->{__MARKDOWN__} .= $md;
      }
   }
   return($self->{__MARKDOWN__});
}

# Accessor for flag that indicates a link ('a' element with 'href' attribute) is currently being read
# If a value is passed, it is set.
# Returns the value (after any setting, when applicable)
sub currently_reading_link
{  my($self,$bool) = @_;
   my $this = (caller(0))[3];
   $self->{__CURRENTLY_READING_LINK__} = ($bool ? 1 : 0) if defined $bool;
   return($self->{__CURRENTLY_READING_LINK__});
}

# Accessor for flag that indicates a list is currently being read
# If a value is passed, it is set.
# Returns the value (after any setting, when applicable)
sub currently_reading_list
{  my($self,$bool) = @_;
   my $this = (caller(0))[3];
   $self->{__CURRENTLY_READING_LIST__} = ($bool ? 1 : 0) if defined $bool;
   return($self->{__CURRENTLY_READING_LIST__});
}

# Accessor for most recently read value of a 'href' attribute of an 'a' element
# If a value is passed, it is set.
# Returns the value (after any setting, when applicable)
sub latest_uri
{  my($self,$uri) = @_;
   my $this = (caller(0))[3];
   $self->{__LATEST_URI__} = $uri if defined $uri;
   return($self->{__LATEST_URI__});
}

# deals with opening tags
sub start
{  my ($self, $tagname, $attr, $attrseq, $text) = @_;

   # start of text to be rendered in italics
   if('em' eq $tagname || 'i' eq $tagname) {
      $self->markdown(append => '_');
   }
   # start of text to be rendered bold
   elsif('b' eq $tagname || 'strong' eq $tagname) {
      $self->markdown(append => '**');
   }
   # linebreak
   elsif('br' eq $tagname) {
      # not allows within a list item in markdown
      $self->markdown(append => "\n\n") unless $self->currently_reading_list();
   }
   # start list
   elsif('ul' eq $tagname) {
      $self->currently_reading_list(1);
      $self->markdown(append => "\n\n");
   }
   # start list item
   elsif('li' eq $tagname) {
      $self->markdown(append => '* ');
   }
   # opening tag of a link
   elsif('a' eq $tagname && $attr && $attr->{href}) {
      $self->latest_uri($attr->{href});
      $self->currently_reading_link(1);
      $self->markdown(append => '[');
   }
   else {
      die "don't know how to deal with $tagname tags";
   }
}

# deals with closing tags
sub end
{  my ($self, $tagname, $text) = @_;
   
   # end of text to be rendered in italics
   if('em' eq $tagname || 'i' eq $tagname) {
      $self->markdown(append => '_');
   }
   # end of text to be rendered bold
   elsif('b' eq $tagname || 'strong' eq $tagname) {
      $self->markdown(append => '**');
   }
   # end of list
   elsif('ul' eq $tagname) {
      $self->currently_reading_list(0);
      $self->markdown(append => "\n");
   }
   # end of list item
   elsif('li' eq $tagname) {
      $self->markdown(append => "\n");
   }
   # closing tag of a link
   elsif('a' eq $tagname && $self->currently_reading_link()) {
      $self->markdown(append => ']('.$self->latest_uri().')');
      $self->latest_uri('');
      $self->currently_reading_link(0);
   }
   else {
      die "don't know how to deal with $tagname tags";
   }
}

# deals with text content
sub text
{  my ($self, $origtext) = @_;

   $self->markdown(append => decode_entities($origtext));
}

1;

###   end of HTMLStaticContentParser   ############################################################################################

