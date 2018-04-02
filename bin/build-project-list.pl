#!/usr/bin/env perl

use strictures 2;
use 5.014;

use Fcntl                 qw/LOCK_EX  LOCK_NB/;
use File::Spec::Functions qw/catdir   catfile/;
use Getopt::Long;
use Pod::Usage;
use Mojo::File qw/path/;

use lib qw/lib/;
use ModulesPerl6::DbBuilder;

use constant DB_FILE           => 'modulesperl6.db';
use constant GITHUB_TOKEN_FILE => 'github-token';
use constant APP               => 'bin/ModulesPerl6.pl';
use constant LOGOS_DIR         => catdir  qw/public  content-pics  dist-logos/;
use constant META_LIST_FILE    => 'https://raw.githubusercontent.com'
                                    . '/perl6/ecosystem/master/META.list';

my $meta_list         = META_LIST_FILE;
my $github_token_file = GITHUB_TOKEN_FILE;
my $logos_dir         = LOGOS_DIR;
my $db_file           = DB_FILE;

GetOptions(
    'db-file=s'           => \$db_file,
    'github-token-file=s' => \$github_token_file,
    'help|?'              => \my $help,
    'man'                 => \my $man,
    'meta-list=s'         => \$meta_list,
    'limit=i'             => \my $limit,
    'logos-dir=s'         => \$logos_dir,
    'restart-app'         => \my $restart_app,
    'no-p6c|?'            => \my $no_p6c,
    'no-cpan|?'           => \my $no_cpan,
    'no-rsync|?'          => \my $no_rsync,
) or pod2usage 2;

pod2usage 1 if $help;
pod2usage -exitval => 0, -verbose => 2 if $man;

$ENV{MODULES_PERL6_GITHUB_TOKEN_FILE} = $github_token_file;
ModulesPerl6::DbBuilder->new(
    app         => APP,
    db_file     => $db_file,
    limit       => $limit,
    logos_dir   => $logos_dir,
    meta_list   => $meta_list,
    restart_app => $restart_app,
    no_p6c      => $no_p6c,
    no_cpan     => $no_cpan,
    no_rsync    => $no_rsync,
)->run;

__END__

=encoding utf8

=head1 NAME

./bin/build-project-list.pl - update database of modules in Perl 6 ecosystem

=head1 SYNOPSIS

./bin/build-project-list.pl [options]

 All options are optional.

 Options:
   --db-file=FILE
   --github-token-file=FILE
   --help
   --limit=N
   --logos_dir=DIR
   --man
   --meta-list=FILE
   --meta-list=URL
   --restart-app
   --no-p6c
   --no-cpan
   --no-rsync

   Short form (first letter of the option or more when need to disambiguate):
   -d=FILE
   -g=FILE
   -h
   -li=N
   -lo=DIR
   -ma
   -me=FILE
   -me=URL
   -r

=head1 OPTIONS

=over 8

=item B<--db-file=FILE>

An SQLite file where the modules database will be written. Will be created
if does not exist. B<Default to:> C<modulesperl6.db> in the current
directory.

=item B<--github-token-file=FILE>

A file containing a GitHub token the build script can use to make API requests.
B<Defaults to:> C<github-token> in the current directory.

=item B<--help>

Print a brief help message and exits.

=item B<--limit=N>

Limit build to at most C<N> number of modules. This is useful for debugging
purposes.

=item B<--logos-dir=DIR>

Path where to download distribution logotypes to. B<Defaults to:>
C<public/content-pics/dist-logos>

=item B<--man>

View the manual page.

=item B<--meta-list=FILE/URL>

A filename or a URL to the META.list ecosystem file. This file should contain
URLs to modules' META files, one per line.  B<Defaults to:>
C<https://raw.githubusercontent.com/perl6/ecosystem/master/META.list>

=item B<--restart-app>

If specified, the script will restart the Mojolicious front-end app, once
the database build completes.

=item B<--no-p6c>

Do not process p6c ecosystem (the GitHub-/GitLab-based one).

=item B<--no-cpan>

Do not process CPAN ecosystem.

=item B<--no-rsync>

Do not C<rsync> fresh CPAN dists from CPAN. Implied when C<--no-cpan> is used.

=back

=head1 DESCRIPTION

B<./bin/build-project-list.pl> will update (or generate new) modules database
given a META.list ecosystem file. Optionally, the build script can also
restart the front-end Mojolicious app

=cut
