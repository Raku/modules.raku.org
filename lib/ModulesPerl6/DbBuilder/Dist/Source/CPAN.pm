package ModulesPerl6::DbBuilder::Dist::Source::CPAN;

use base 'ModulesPerl6::DbBuilder::Dist::Source';

use Archive::Any;
use File::Spec::Functions qw/catfile  splitdir/;
use File::Basename qw/fileparse dirname/;
use File::Copy qw/move/;
use File::Glob qw/bsd_glob/;
use File::Path qw/make_path  remove_tree/;
use File::Temp qw/tempdir/;
use List::Util qw/uniq/;
use ModulesPerl6::DbBuilder::Log;
use Mew;
use Mojo::File qw/path/;
use Mojo::JSON qw/to_json  from_json/;
use Mojo::URL;
use Text::FileTree;
use experimental 'postderef';

use constant LOCAL_CPAN_DIR => 'dists-from-CPAN';
use constant UNPACKED_DISTS => 'dists-from-CPAN-unpacked';

sub re {
    qr{
        ^   cpan://
            (               # file
                id/
                (           # dist dir portion
                    [A-Z]/[A-Z]{2}/
                    ([A-Z]+) # author
                )
                /Perl6/
                (\S+)       # dist
            )
        $
    }ix;
}

sub load {
    my $self = shift;
    my $dist = $self->_dist or return;
    my ($file, $dist_dir, $author, $basename) = $self->_meta_url =~ $self->re;
    $dist_dir = catfile $dist_dir, $basename =~ s/.meta$//r;
    $file = catfile LOCAL_CPAN_DIR, $file;

    $dist->{dist_source} = 'cpan';
    $dist->{author_id} = $author;
    $dist->{date_updated} = (stat $file)[9]; # mtime
    $dist->{name} ||= $basename =~ s/-[^-]+$//r;

    my @files = $self->_extract($file, catfile UNPACKED_DISTS, $dist_dir);
    $dist->{files} = +{
        files_dir => $dist_dir,
        files     => Text::FileTree->new->parse(
            join "\n", map { catfile grep length, splitdir $_ } @files
        ),
    };
    if ($dist->{files}{files}{'META6.json'}) {
        my $meta_file = catfile UNPACKED_DISTS, $dist_dir, 'META6.json';
        if (-f $meta_file and -r _) {
            my $meta = eval { from_json path($meta_file)->slurp };
            if ($@) {
                log error =>
                    "Found META6.json file but could not read/decode: $@"
            }
            else {
                $dist->{repo_url}
                     = $meta->{'source-url'}
                    // $meta->{'repo-url'}
                    // $meta->{support}{source}
                    // $dist->{url};
                if ($dist->{repo_url}) {
                    $dist->{url} = $dist->{repo_url}
                        if $dist->{url} eq 'N/A';

                    $dist->{repo_url} = "https://github.com/$1/$2"
                        if $dist->{repo_url} =~ m{^git\@github\.com:([^/]+)/([^/]+\.git)$};
                    $dist->{repo_url} = Mojo::URL->new(
                        $dist->{repo_url}
                    )->scheme('https')
                }
            }
        }
    }
    $dist->{_builder}{post}{no_meta_checker} = 1;

    return $dist;
}

sub _extract {
    my ($self, $file, $dist_dir) = @_;
    my $base = $file =~ s/.meta$//r;
    my $archive_file;
    for (qw/.tar.gz  .zip  .tar  .tgz  .tg/) {
        next unless -e "$base$_";
        $archive_file = "$base$_";
        last;
    }
    unless ($archive_file) {
        log error => "Could not find archive for $file";
        return [];
    }

    my $archive = Archive::Any->new($archive_file);
    if ($archive->is_naughty) {
        log error => "Refusing archive that unpacks outside its directory";
        return [];
    };

    remove_tree $dist_dir;

    my $base_dist_dir = dirname $dist_dir;
    make_path $base_dist_dir;
    -d $base_dist_dir or return [];

    my $base_tmp_dir = "$ENV{HOME}/tmp";
    -d $base_tmp_dir or make_path $base_tmp_dir;

    my $extraction_dir = tempdir CLEANUP => 1, DIR => $base_tmp_dir;

    log info => "extract $archive_file to $extraction_dir";
    $archive->extract($extraction_dir);

    my @files;
    if ($archive->is_impolite) {
        move $extraction_dir, $dist_dir;
        @files = $archive->files;
    }
    else {
	log info => "move ".+(bsd_glob "$extraction_dir/*")[0].", $dist_dir";
	move +(bsd_glob "$extraction_dir/*")[0], $dist_dir or log warn => $!;
        @files = map {
            my @bits = splitdir $_;
            shift @bits;
            catfile @bits;
        } $archive->files;
    }

    grep length, uniq @files;
}

sub _save_logo {}

sub _download_meta {
    my $self = shift;
    my $path = catfile LOCAL_CPAN_DIR,
        substr $self->_meta_url, length 'cpan://';

    log info => "Loading META file from $path";
    if (my $contents = eval { path($path)->slurp }) {
        return $contents;
    } else {
        log error => "Failed to read META file: $@";
        return;
    }
}


1;

__END__
