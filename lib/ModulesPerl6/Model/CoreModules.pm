package ModulesPerl6::Model::CoreModules;

use Mew;
use Mojo::Collection qw/c/;
use Mojo::Util qw/trim/;

use constant MODULES => c
    {
        name        => 'Test',
        description => 'Routines for testing your code',
        url         => 'https://docs.perl6.org/language/testing',
    },
    {
        name        => 'NativeCall',
        description => 'Native calling interface for using C libraries',
        url         => 'https://docs.perl6.org/language/nativecall',
    },
    {
        name        => 'Pod::To::Text',
        description => 'Render POD as Text',
        url         => 'https://docs.perl6.org/language/pod#Text',
    },
    {
        name        => 'Telemetry',
        description => 'Collect performance state for analysis',
        url         => 'https://docs.perl6.org/type/Telemetry',
    },
    {
        name        => 'snapper',
        description => 'Start a thread taking repeated system state snapshots',
        url         => 'https://docs.perl6.org/type/Telemetry#module_snapper',
    };

sub __clone {
    shift->each(sub { +{%$_} })
}

sub all { __clone MODULES }

sub named {
    my ($self, $name) = @_;
    __clone MODULES->grep(sub {
        CORE::fc($_->{name}) eq CORE::fc($name)
    })
}

sub find {
    my ($self, $q) = @_;
    __clone MODULES->grep(sub {
        "$_->{name} $_->{description}" =~ /\Q$q\E/i
    })
}

1;

__END__
