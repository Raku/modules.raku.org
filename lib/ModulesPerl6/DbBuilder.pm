package ModulesPerl6::DbBuilder;

use Data::GUID;
use File::Basename        qw/fileparse/;
use File::Glob            qw/bsd_glob/;
use File::Path            qw/make_path  remove_tree/;
use File::Find            qw/find/;
use File::Spec::Functions qw/catfile/;
use Mojo::File            qw/path/;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util            qw/trim/;
use Sort::Versions        qw/versioncmp/;
use Try::Tiny;

use ModulesPerl6::DbBuilder::Log;
use ModulesPerl6::DbBuilder::Dist;
use ModulesPerl6::Model::BuildStats;
use ModulesPerl6::Model::Dists;
use Mew;
use experimental 'postderef';

use constant CPAN_RSYNC_URL => 'cpan-rsync.perl.org::CPAN/authors/id';
use constant CPAN_RSYNC_FALLBACK_URL => 'ftp-stud.hs-esslingen.de::CPAN/authors/id';
use constant LOCAL_CPAN_DIR => 'dists-from-CPAN';

has [qw/_app  _db_file  _logos_dir/] => Str;
has -_limit       => Maybe[ PositiveNum ];
has -_restart_app => Maybe[ Bool ];
has -_no_p6c      => Maybe[ Bool ];
has -_no_cpan     => Maybe[ Bool ];
has -_no_rsync    => Maybe[ Bool ];
has _meta_list    => Str;
has _model_build_stats => (
    is      => 'lazy',
    default => sub {
        ModulesPerl6::Model::BuildStats->new( db_file => shift->_db_file );
    },
);
has _model_dists => (
    is      => 'lazy',
    default => sub {
        ModulesPerl6::Model::Dists->new( db_file => shift->_db_file );
    },
);

#########################

sub run {
    my $self = shift;

    my $build_id = Data::GUID->new->as_base64;
    log info => "Starting build $build_id";
    $ENV{FULL_REBUILD}
        and log info => "Full rebuild requested. Caches should be invalid";

    $self->_deploy_db;

    log info => "Will be saving images to " . $self->_logos_dir;
    make_path $self->_logos_dir => { mode => 0755 };

    my @metas = $self->_metas;
    for my $idx ( 0 .. $#metas ) {
        try {
            warn "---\n";
            log info => 'Processing dist ' . ($idx+1) . ' of ' . @metas;
            my $dist = ModulesPerl6::DbBuilder::Dist->new(
                meta_url  => $metas[$idx],
                build_id  => $build_id,
                logos_dir => $self->_logos_dir,
                dist_db   => $self->_model_dists,
            )->info or die "Failed to build dist\n";
            $self->_model_dists->add( $dist );
        }
        catch {
            log error=> "Received fatal error while building $metas[$idx]: $_";
            $self->_model_dists->salvage_build( $metas[$idx], $build_id );
        };
    }

    warn "---\n---\n";
    log info => 'Finished building all dists. Performing cleanup.';

    $self->_remove_old_dists( $build_id )
        ->_remove_old_logotypes->_save_build_stats;

    if ( $self->_restart_app ) {
        log info => 'Restarting app ' . $self->_app;
        if ( $^O eq 'MSWin32' ) {
            $SIG{CHLD} = 'IGNORE';
            my $pid = fork;
            $pid == 0 and exec $self->_app => 'daemon';
            not defined $pid and log error => "Failed to fork to exec the app";
        }
        else {
            0 == system hypnotoad => $self->_app
                or log error => "Failed to restart the app: $?";
        }
    }

    log info => "Finished build $build_id\n\n\n";

    $self;
}

#########################

sub _deploy_db {
    my $self = shift;

    my $db = $self->_db_file;
    log info => "Using database file $db";
    return $self if -e $db;

    log info => "Database file not found... deploying new database";
    $self->_model_dists      ->deploy;
    $self->_model_build_stats->deploy;

    $self;
}

sub _metas {
    my $self = shift;
    return
        ($self->_no_cpan ? () : $self->_cpan_metas),
        ($self->_no_p6c  ? () : $self->_p6c_metas );
}

sub _cpan_metas {
    my $self = shift;

    if ($self->_no_rsync) {
        log info => '--no-rsync option used; skipping rsync; '
            . 'searching for META files';
    }
    else {
        my $success = 0;
        for my $rsync_url (CPAN_RSYNC_URL, CPAN_RSYNC_FALLBACK_URL) {
            log info => 'rsyncing CPAN dists from ' .$rsync_url;
            my @command = (qw{
                /usr/bin/rsync  --prune-empty-dirs  --delete  -av
                --exclude="/id/P/PS/PSIXDISTS/Perl6"
                --include="/id/*/*/*/Perl6/"
                --include="/id/*/*/*/Perl6/*.meta"
                --include="/id/*/*/*/Perl6/*.tar.gz"
                --include="/id/*/*/*/Perl6/*.tgz"
                --include="/id/*/*/*/Perl6/*.zip"
                --exclude="/id/*/*/*/Perl6/*"
                --exclude="/id/*/*/*/*"
                --exclude="id/*/*/CHECKSUMS"
                --exclude="id/*/CHECKSUMS"
            }, $rsync_url, LOCAL_CPAN_DIR);
            qx/@command/;
            if ($? == 0) {
                log info => 'rsync done; searching for META files';
                $success = 1;
                last;
            }
            else {
                log info => "rsync for $rsync_url errored out with return code $?";
            }
        }
        if (!$success) {
            log warn => "could not rsync cpan :(";
        }
    }

    my @metas;
    find sub {
        no warnings 'substr';
        for (grep length, substr $File::Find::name, 1+length LOCAL_CPAN_DIR) {
            push @metas, $_ if /\.meta$/;
        }
    }, LOCAL_CPAN_DIR;

    # exclude trial releases
    @metas = grep !/
        -(?!.*-)    # last dash in the filename
        .*(TRIAL|_) # trial versions
    /x, @metas;

    my %metas;
    for (@metas) { # bunch up different versions of the same dist together
        my ($file, $dir) = fileparse $_, '.meta';
        my ($name, $version) = $file =~ /(.+)-([^-]+)$/;
        unless (length $name and length $version) {
            log warn => "Could not figure out name and version for dist: $_";
            next;
        }
        $metas{$name}{dir} = $dir;
        push $metas{$name}{versions}->@*, $version;
    }

    # find which version is latest and use that to build meta URL
    @metas = map {
        'cpan://' . catfile $metas{$_}{dir},
            "$_-" .
            (reverse sort { versioncmp $a, $b } $metas{$_}{versions}->@*)[0]
            . '.meta',
    } sort keys %metas;

    log info => 'Found ' . @metas . ' CPAN dists';
    return @metas
}

sub _p6c_metas {
    my $self = shift;
    my $meta_list = $self->_meta_list;

    log info => "Loading META.list from $meta_list";
    my $url = Mojo::URL->new( $meta_list );
    my $raw_data;
    if ( $url->scheme and $url->scheme =~ /(ht|f)tps?/i ) {
        log info => '... a URL detected; trying to fetch';
        my $tx = Mojo::UserAgent->new( max_redirects => 10 )->get( $url );

        if ( $tx->success ) { $raw_data = $tx->res->body }
        else {
            my $err = $tx->error;
            log fatal => "$err->{code} response: $err->{message}"
                if $err->{code};
            log fatal => "Connection error: $err->{message}";
        }
    }
    elsif ( -r $meta_list ) {
        log info => '... a file detected; trying to read';
        $raw_data = path($meta_list)->slurp;
    }
    else {
        log fatal => 'Could not figure out how to load META.list. It does '
            . 'not seem to be a URL, but is not a [readable] file either';
    }

    my @metas = grep /\S/, map trim($_), split /\n/, $raw_data;
    log info => 'Found ' . @metas . ' dists';

    if ( my $limit = $self->_limit ) {
        @metas = splice @metas, 0, $limit;
        log info => "Limiting build to $limit dists due to explicit request";
    }

    # We reverse the list, since users tend to add their modules to the
    # bottom of the list, by reversing it, we can load new modules to the site
    # at the start of the run, instead of at the end.
    return reverse @metas;
}

sub _remove_old_dists {
    my ( $self, $build_id ) = @_;

    my $delta = $self->_model_dists->remove_old( $build_id );
    log info => "Removed $delta dists that are no longer in the ecosystem"
        if $delta;

    $self;
}

sub _remove_old_logotypes {
    my $self = shift;

    # TODO: we can probably move this code into the ::Dists model so we don't
    # have to pull all the dists in DB into a giant list of hashrefs
    my $dir = $self->_logos_dir;
    my %logos = map +( $_ => 1 ),
        grep -e, map catfile($dir, 's-' . $_->{name} =~ s/\W/_/gr . '.png'),
            $self->_model_dists->find->each;

    for ( grep ! $logos{$_}, bsd_glob catfile $dir, '*' ) {
        log info => "Removing logotype file without a dist in db: $_";
        unlink;
    }

    $self;
}

sub _save_build_stats {
    my $self = shift;

   my $dist_num = scalar( $self->_model_dists->find->@* );
    $self->_model_build_stats->update(
        last_updated => time(),
        dists_num    => $dist_num,
        has_appveyor => $dist_num - scalar( $self->_model_dists->find({ appveyor_status  => 'not set up'})->@* ),
        has_travis   => $dist_num - scalar( $self->_model_dists->find({ travis_status    => 'not set up'})->@* ),
    );

    $self;
}

1;

__END__
