package ModulesPerl6::DbBuilder::Dist::PostProcessor::p05DataFetcher;

use strictures 2;
use base 'ModulesPerl6::DbBuilder::Dist::PostProcessor';

use Mojo::UserAgent;
use Mojo::File qw/path/;
use Mojo::Util qw/b64_decode  trim/;
use ModulesPerl6::DbBuilder::Log;
use experimental 'postderef';
use feature 'state';

############################################################################
############################################################################
#
# This postprocessor fetches data (e.g. content of READMEs) for use by other
# post processors or anything else that runs afterwards.
#
############################################################################
############################################################################

sub process {
    my $self = shift;

    $self->__fetch_file(sub {$_[0]->{name} =~ /^README/i   }, 'README'     );
    $self->__fetch_file(sub {$_[0]->{name} eq '.travis.yml'}, '.travis.yml');

    return 1;
}

sub __fetch_file {
    my ($self, $file_grep, $error_name) = @_;
    my $dist = $self->_dist;
    my ($file) = grep {$file_grep->($_)}
        ($dist->{_builder}{files} || [])->@*
    or return;

    state $token = trim path($ENV{MODULES_PERL6_GITHUB_TOKEN_FILE})->slurp;
    my $content = eval {
        my $res_json = Mojo::UserAgent->new( max_redirects => 5 )
            ->get( $file->{url} => {
                Authorization => "token $token"
            })->result->json;
        defined $res_json->{content} or die $res_json->{message};
        $res_json;
    };
    if ($@) {
        log error => "ERROR fetching README content: $@";
        $file->{error} = "$@";
        return;
    }

    # TODO XXX: the JSON+decode step is valid for GitHub, but
    # if other dist sources are taught to provide READMEs, they
    # may have other mechanism that will need to be taken care of
    # here. You can use $dist->{dist_source} to find out which
    # dist source the dist came from.

    # Possible encodings are 'utf-8' and 'base64', per
    # https://developer.github.com/v3/git/blobs/#parameters
    $file->{content} = $content->{encoding} eq 'base64'
        ? (b64_decode $content->{content})
        :             $content->{content};
}

1;

__END__
