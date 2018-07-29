#!perl

use strict;
use warnings FATAL => 'all';
use FindBin;
use lib "$FindBin::Bin/../../";
use Pithub;
use Test::Most;
use Test::Output qw/combined_from/;
use t::Helper;
use File::Temp qw/tempdir/;
use ModulesPerl6::Model::Dists;
BEGIN { use_ok 'ModulesPerl6::DbBuilder::Dist' };

my $db_file = t::Helper::setup_db_file;
END { unlink $db_file };

my $m = ModulesPerl6::Model::Dists->new( db_file => $db_file );
my $logos_dir = tempdir CLEANUP => 1;
my $time_stamp_re = t::Helper::time_stamp_re;

ok 1;

done_testing;
