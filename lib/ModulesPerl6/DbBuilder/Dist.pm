package ModulesPerl6::DbBuilder::Dist;

use ModulesPerl6::DbBuilder::Log;
use Mojo::File qw/path/;
use Mojo::Util qw/decode/;
use Mew;
use Module::Pluggable search_path => ['ModulesPerl6::DbBuilder::Dist::Source'],
                      sub_name    => '_sources',
                      require     => 1;
use Module::Pluggable search_path
                        => ['ModulesPerl6::DbBuilder::Dist::PostProcessor'],
                      sub_name    => '_postprocessors',
                      require     => 1;
use Pithub;

has [qw/_build_id  _logos_dir  _meta_url/] => Str;
has _dist_db => InstanceOf['ModulesPerl6::Model::Dists'];
has _token => Str, (
    is => 'lazy',
    default => sub {
        my $file = $ENV{MODULES_PERL6_GITHUB_TOKEN_FILE} // 'github-token';
        -r $file or log fatal => "GitHub token file [$file] is missing "
                            . 'or has no read permissions';
        return decode 'utf8', path($file)->slurp;
    },
);

#########################

sub info {
    my $self = shift;
    my $info = $self->_load_info
        or return;

    return $info;
}

#########################

sub _load_info {
    my $self = shift;

    my $dist = $self->_load_from_source
        or return;

    $dist->{build_id} = $self->_build_id;

    return $dist;
}

sub _load_from_source {
    my $self = shift;

    my $url = $self->_meta_url;
    for my $candidate ( $self->_sources ) {
        next unless $url =~ $candidate->re;
        log info => "Using $candidate to load $url";
        my $dist = $candidate->new(
            meta_url  => $url,
            logos_dir => $self->_logos_dir,
            dist_db   => $self->_dist_db,
        )->load or return;
        $dist->{build_id} = $self->_build_id;

        $self->_fill_from_github($dist);

        for my $postprocessor ( $self->_postprocessors ) {
            $postprocessor->new(
                meta_url => $url,
                dist     => $dist,
            )->process;
        }

        delete $dist->{_builder};
        return $dist;
    }
    log error => "Could not find a source module that could handle dist URL "
        . "[$url]\nHere are all the source modules currently available:\n"
        . join "\n", map "$_ looks for " . $_->re, $self->_sources;

    return;
}

sub _fill_from_github {
    my ($self, $dist) = @_;
    return unless ($dist->{dist_source} eq 'cpan' || $dist->{dist_source} eq 'zef') && $dist->{repo_url};

    if ($dist->{repo_url} =~ m#(?<protocol>[^/]+)://github.com/(?<user>[^/]+)/(?<repo>[^/]+).git#) {

        $dist->{_builder}->@{qw/repo_user  repo/} = ( $+{user}, $+{repo} );

        my $pithub = Pithub->new(
            user  => $+{user},
            repo  => $+{repo},
            token => $self->_token,
            ua    => LWP::UserAgent->new(
                agent   => 'Perl 6 Ecosystem Builder',
                timeout => 20,
            ),
        );

        my $repo = $self->_repo($pithub->repos->get) or return;
        $dist->{stars} = $repo->{stargazers_count} // 0;
        $dist->{issues} = $repo->{open_issues_count};
        $dist->{stargazer_url} = $repo->{html_url} . '/stargazers';
        $dist->{issue_url} = $repo->{html_url} . '/issues';
    }
}

sub _repo {
    my ( $self, $res ) = @_;

    unless ( $res->success ) {
        log error => "Error accessing GitHub API. HTTP Code: " . $res->code;
        return
    }

    return $res->content;
}

1;
