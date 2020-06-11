# parasite-static

Keeping static contents for ParaSite website



## Structure

1. species
1.1 Ancylostoma ceylanicum
1.1.1 Ancylostoma ceylanicum.about.md
1.1.3 PRJNA231479
1.1.3.1 Ancylostoma_ceylanicum_PRJNA231479.summary.md
1.1.3.2 Ancylostoma_ceylanicum_PRJNA231479.assembly.md
1.3.3 Ancylostoma_ceylanicum_PRJNA231479.annotation.md
1.1.3.4 Ancylostoma_ceylanicum_PRJNA231479.resources.md
1.1.3.5 Ancylostoma_ceylanicum_PRJNA231479.publication.md
1.1.4 PRJNA72583
1.1.4.1 Ancylostoma_ceylanicum_PRJNA72583.summary.md
1.1.4.1 Ancylostoma_ceylanicum_PRJNA72583.assembly.md
1.1.4.1 Ancylostoma_ceylanicum_PRJNA72583.annotation.md
1.1.4.1 Ancylostoma_ceylanicum_PRJNA72583.resources.md
1.1.4.1 Ancylostoma_ceylanicum_PRJNA72583.publication.md
1.2 ...etc



## Managing files

The script `./bin/manage_files.pl` helps manage the files.


### Creating files from the static content in the database

The static content in the database cannot be maintained any longer, so the content needs to
be placed into Markdown files.  This is hopefully be a one-off operation.

To create files for the content that is currently in the database `ensembl_production_parasite`:

```bash
./bin/manage_files.pl --create-missing [--root-dir ./my_dir]
```
Output: a list of all files that have been created.

This creates only the missing files, i.e. where a Markdown or HTML file is not already present on disk
and has non-zero size.  The `--root-dir` option can be used to create a structure (with a complete set
of new files) under a different subdirectory.

The HTML files contain the database content.  The species' `.about.html` file containms the `description` field from
the table `static_species`.  The other HTML files are the contents of fields from the table `static_genome`; the file
names match field names (e.g. `.summary.html` is the content of the `summary` field).

The Markdown files are created automatically from the HTML files.


### Creating files for new species or genomes that are not in the database

Genomes added from WBPS15 will not have static content in the database; the species will also have no existing static content,
unless there was already another assembly.

To find all the files that need to be added:

```bash
./bin/manage_files.pl --placeholders [--root-dir ./my_dir]
```
Output: a list of all palceholder files that have been created.

This creates a "placeholder" for every Markdown file that needs to be created.  These have the name of the file that is required
with `.placeholder` as a suffix.


### Find all missing files

To find all files that, for any reason, are missing from the structure:

```bash
./bin/manage_files.pl --find-missing [--root-dir ./my_dir]
```
Output: a list of all missing files.


### Creating HTML files from Markdown

**Not yet implemented**

The Markdown files are used to make authoring easier, but the web site requires HTML.

To create HTML files from all Markdown files:

```bash
./bin/manage_files.pl --make-html [--root-dir ./my_dir]
```
Output: a list of all HTML files that have been created.

This creates only the missing files, i.e. where a Markdown file exists but there is no corresponding HTML file that has non-zero size.

If you want to create new HTML files, delete existing HTML files before running this command.  e.g. for a complete
set of new HTML files (ensuring each one is up-to-date with the current state of the Markdown), first run
`find ./species -name '*.html' -type f -exec rm {} \;`; or to renew all HTML files for _Ancylostoma ceylanicum_
run `find ./species/Ancylostoma_ceylanicum -name '*.html' -type f -exec rm {} \;`.

