#!perl

use strict;
use warnings FATAL => 'all';
use FindBin;
use lib "$FindBin::Bin/../../";
use File::Temp qw/tempdir/;
use Mojo::Util qw/spurt  trim/;
use Test::Most;
use Test::Script;
use t::Helper;

use ModulesPerl6::Model::Dists;
BEGIN { use_ok 'ModulesPerl6::DbBuilder::Dist' };

my $db_file = t::Helper::setup_db_file;
END { unlink $db_file };

my $m = ModulesPerl6::Model::Dists->new( db_file => $db_file );
my $logos_dir = tempdir CLEANUP => 0;
my $re = t::Helper::time_stamp_re;
my $meta_list = File::Temp->new;

spurt get_meta_list() => $meta_list;

diag 'Running build on 2 dists (might take a while)';
my $out;
script_runs [
    'bin/build-project-list.pl',
    "--meta-list=$meta_list",
    "--db-file=$db_file",
    "--logos-dir=$logos_dir",
], { stdout => \$out, stderr => \$out };

my @out = map trim($_), split /---/, $out;
like $out[0], qr{^
    $re\Q [info] Starting build \E ([\w=+/.!:~-]{12,76}) \s
    $re\Q [info] Using database file $db_file\E \s
    $re\Q [info] Will be saving images to $logos_dir\E \s
    $re\Q [info] Loading META.list from $meta_list\E \s
    $re\Q [info] ... a file detected; trying to read\E \s
    $re\Q [info] Found 2 dists\E
$}x, 'part 0 of output matches';

like $out[1], qr{^
    $re\Q [info] Processing dist 1 of 2\E \s
    $re\Q [info] Using ModulesPerl6::DbBuilder::Dist::Source::GitHub to \E
        \Qload https://raw.githubusercontent.com/zoffixznet/perl6-modules\E
        \Q.perl6.org-test3/master/META.info\E \s
    $re\Q [info] Fetching distro info and commits\E \s
    $re\Q [info] Downloading META file from https://raw.githubusercontent.\E
        \Qcom/zoffixznet/perl6-modules.perl6.org-test3/master/META.info\E \s
    $re\Q [info] Parsing META file\E \s
    $re\Q [warn] Required `perl` field is missing\E \s
    $re\Q [info] Dist has new commits. Fetching more info.\E \s
    $re\Q [info] Dist has a logotype of size 160 bytes.\E \s
    $re\Q [info] Did not find cached dist logotype. Downloading.\E
$}x, , 'part 1 of output matches';

like $out[2], qr{^
    $re\Q [info] Processing dist 2 of 2\E \s
    $re\Q [info] Using ModulesPerl6::DbBuilder::Dist::Source::GitHub to \E
        \Qload https://raw.githubusercontent.com/zoffixznet/perl6-Color/\E
        \Qmaster/META6.json\E \s
    $re\Q [info] Fetching distro info and commits\E \s
    $re\Q [info] Downloading META file from https://raw.githubusercontent.com\E
        \Q/zoffixznet/perl6-Color/master/META6.json\E \s
    $re\Q [info] Parsing META file\E \s
    $re\Q [info] Dist has new commits. Fetching more info.\E \s
    $re\Q [info] Dist has a logotype of size 1390 bytes.\E \s
    $re\Q [info] Did not find cached dist logotype. Downloading.\E \s
    $re\Q [info] Determined travis status is \E ([a-z]+)
$}x, , 'part 2 of output matches';

like $out[3], qr{^
$}x, , 'part 3 of output matches';

like $out[4], qr{^
    $re\Q [info] Finished building all dists. Performing cleanup.\E \s
    $re\Q [info] Removed 2 dists that are no longer in the ecosystem\E \s
    $re\Q [info] Finished build \E ([\w=+/.!:~-]{12,76})
$}x, , 'part 4 of output matches';

my ( $build_id ) = $out[4] =~ m{\QFinished build \E ([\w=+/.!:~-]{12,76})}x;

subtest 'pop open the DB and check all values are correct in it' => sub {
    cmp_deeply [$m->find->each], [
        {
            'build_id' => $build_id,
            'date_added' => 0,
            'meta_url' => 'https://raw.githubusercontent.com/zoffixznet/'
                            . 'perl6-modules.perl6.org-test3/master/META.info',
            'name' => 'TestRepo3',
            'issues' => 0,
            'stars' => 0,
            'date_updated' => re('\A\d{10}\z'),
            'description' => 'Test dist for modules.perl6.org build script',
            'author_id' => 'Zoffix Znet',
            'travis_status' => 'not set up',
            'url' => 'https://github.com/zoffixznet/perl6-modules.perl6'
                        . '.org-test3'
        },
        {
            'build_id' => $build_id,
            'date_updated' => re('\A\d{10}\z'),
            'stars' => re('\A\d+\z'),
            'url' => 'https://github.com/zoffixznet/perl6-Color',
            'description' => 'Format conversion, manipulation, and math '
                                . 'operations on colours',
            'author_id' => 'Zoffix Znet',
            'travis_status' => 'passing',
            'date_added' => re('\A\d+\z'),
            'meta_url' => 'https://raw.githubusercontent.com/zoffixznet/'
                            . 'perl6-Color/master/META6.json',
            'name' => 'Color',
            'issues' => re('\A\d+\z'),
        }
    ], 'data matches';
};

done_testing;


sub get_meta_list {
    return <<'END'
https://raw.githubusercontent.com/zoffixznet/perl6-modules.perl6.org-test3/master/META.info
https://raw.githubusercontent.com/zoffixznet/perl6-Color/master/META6.json
END
}
