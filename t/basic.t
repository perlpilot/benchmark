use Benchmark;
use Test;
plan 19;

my $count = 1;

my $code-sub = sub { ok 1 }
my $code-str = q[use Test; ok 1];

my $a = timethis(4, $code-sub); # 4 runs
ok $a ~~ Positional;
$a = timethis(4, $code-str);    # 4 runs
ok $a ~~ Positional;

my %h = foo => $code-sub, bar => $code-str;
$a = timethese 4, %h;           # 8 runs
ok $a ~~ Hash;
