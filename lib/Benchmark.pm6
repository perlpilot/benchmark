unit module Benchmark;

my sub time_it (Int $count where { $_ > 0 }, Code $code) {
    my $start-time = time;
    for 1..$count { $code.(); }
    my $end-time = time;
    my $difference = $end-time - $start-time;
    my $average = $difference / $count;
    return ($start-time, $end-time, $difference, $average);
}

multi sub timethis (Int $count, Str $code) is export {
    my $routine = { EVAL $code };
    return time_it($count, $routine);
}

multi sub timethis (Int $count, Code $code) is export { 
    return time_it($count, $code);
}

sub timethese (Int $count, %h) is export {
    my %results;
    for %h.kv -> $k, $sub { 
        %results{$k} = timethis($count, $sub);
    }
    return %results;
}

use NativeCall;

# Only works on systems where clock_t == long int
constant clock_t = int64;

class tms is repr('CStruct') {
    has clock_t $.user-time;
    has clock_t $.system-time;
    has clock_t $.children-user-time;
    has clock_t $.children-system-cstime;
}

class Timing {
    has $.time = time;
    has tms $.times = times;
}

my sub _times(tms) returns clock_t
    is symbol('times')
    is native {*}

sub times() {
    my tms $buf .= new;
    _times($buf);
    return $buf;
}

sub timediff(tms $a, tms $b) returns $tms
{
    return tms.new( 
        :user-time($a.user-time - $b.user-time),
        :system-time($a.system-time - $b.system-time),
        :children-user-time($a.children-user-time - $b.children-user-time),
        :children-system-time($a.children-system-time - $b.children-system-time),
    );
}

sub count-it(Int $tmax, &code)
{
    my ($n, $tc);
 
    # First find the minimum $n that gives a significant timing.
    my $zeros = 0;
    loop ($n = 1; ; $n *= 2 ) {
        my $t0 = times;
        my $td = timeit($n, $code);
        my $t1 = times;
        $tc = $td.user-time + $td.system-time;
        if ( $tc <= 0 and $n > 1024 ) {
            my $d = timediff($t1, $t0);
            # note that $d is the total CPU time taken to call timeit(),
            # while $tc is is difference in CPU secs between the empty run
            # and the code run. If the code is trivial, its possible
            # for $d to get large while $tc is still zero (or slightly
            # negative). Bail out once timeit() starts taking more than a
            # few seconds without noticeable difference.
            if ($d.user-time + $d.system-time > 8
                || ++$zeros > 16)
            {
                die "Timing is consistently zero in estimation loop, cannot benchmark. N=$n\n";
            }
        } else {
            $zeros = 0;
        }
        last if $tc > 0.1;
    }
 
    my $nmin = $n;
 
    # Get $n high enough that we can guess the final $n with some accuracy.
    my $tpra = 0.1 * $tmax; # Target/time practice.
    while $tc < $tpra {
        # The 5% fudge is to keep us from iterating again all
        # that often (this speeds overall responsiveness when $tmax is big
        # and we guess a little low).  This does not noticeably affect
        # accuracy since we're not counting these times.
        $n = ( $tpra * 1.05 * $n / $tc ).Int; # Linear approximation.
        my $td = timeit($n, $code);
        my $new_tc = $td.user-time + $td.system-time;
        # Make sure we are making progress.
        $tc = $new_tc > 1.2 * $tc ? $new_tc : 1.2 * $tc;
    }
 
    # Now, do the 'for real' timing(s), repeating until we exceed
    # the max.
    my $ntot  = 0;
    my $rtot  = 0;
    my $utot  = 0.0;
    my $stot  = 0.0;
    my $cutot = 0.0;
    my $cstot = 0.0;
    my $ttot  = 0.0;
 
    # The 5% fudge is because $n is often a few % low even for routines
    # with stable times and avoiding extra timeit()s is nice for
    # accuracy's sake.
    $n = ( $n * ( 1.05 * $tmax / $tc ) ).Int;
    $zeros=0;
    loop {
        my $td = timeit($n, $code);
        $ntot  += $n;
        $rtot  += $td->[0];
        $utot  += $td->[1];
        $stot  += $td->[2];
        $cutot += $td->[3];
        $cstot += $td->[4];
        $ttot = $utot + $stot;
        last if $ttot >= $tmax;
        if ( $ttot <= 0 ) {
            ++$zeros > 16
                and die "Timing is consistently zero, cannot benchmark. N=$n\n";
        } else {
            $zeros = 0;
        }
        $ttot = 0.01 if $ttot < 0.01;
        my $r = $tmax / $ttot - 1; # Linear approximation.
        $n = int( $r * $ntot );
        $n = $nmin if $n < $nmin;
    }
 
    return bless [ $rtot, $utot, $stot, $cutot, $cstot, $ntot ];
} 
}
