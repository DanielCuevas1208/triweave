package Triweave::Diff;

use strict;
use warnings;
use Exporter qw(import);
use Carp qw(croak);

our @EXPORT_OK = qw(diff_hunks apply_hunks);

sub diff_hunks {
    my ($base, $changed) = @_;
    croak 'diff_hunks expects two array references'
        unless ref $base eq 'ARRAY' && ref $changed eq 'ARRAY';

    my $base_count = scalar @$base;
    my $changed_count = scalar @$changed;
    my @lcs = map { [(0) x ($changed_count + 1)] } 0 .. $base_count;

    for (my $i = $base_count - 1; $i >= 0; $i--) {
        for (my $j = $changed_count - 1; $j >= 0; $j--) {
            $lcs[$i][$j] = $base->[$i] eq $changed->[$j]
                ? $lcs[$i + 1][$j + 1] + 1
                : ($lcs[$i + 1][$j] > $lcs[$i][$j + 1]
                    ? $lcs[$i + 1][$j]
                    : $lcs[$i][$j + 1]);
        }
    }

    my @hunks;
    my ($i, $j) = (0, 0);
    while ($i < $base_count || $j < $changed_count) {
        if ($i < $base_count && $j < $changed_count
            && $base->[$i] eq $changed->[$j]) {
            $i++;
            $j++;
            next;
        }

        my $start = $i;
        my @replacement;
        while ($i < $base_count || $j < $changed_count) {
            last if $i < $base_count && $j < $changed_count
                && $base->[$i] eq $changed->[$j];

            if ($i < $base_count && $j < $changed_count
                && $lcs[$i + 1][$j] >= $lcs[$i][$j + 1]) {
                $i++;
            } elsif ($j < $changed_count) {
                push @replacement, $changed->[$j];
                $j++;
            } else {
                $i++;
            }
        }

        push @hunks, {
            start    => $start,
            end      => $i,
            replace  => \@replacement,
        };
    }

    return \@hunks;
}

sub apply_hunks {
    my ($base, $hunks) = @_;
    croak 'apply_hunks expects two array references'
        unless ref $base eq 'ARRAY' && ref $hunks eq 'ARRAY';

    my @result;
    my $cursor = 0;
    for my $hunk (@$hunks) {
        croak 'invalid hunk' unless ref $hunk eq 'HASH'
            && ref $hunk->{replace} eq 'ARRAY'
            && defined $hunk->{start} && defined $hunk->{end}
            && $hunk->{start} >= $cursor
            && $hunk->{end} >= $hunk->{start}
            && $hunk->{end} <= scalar @$base;

        push @result, @{$base}[$cursor .. $hunk->{start} - 1]
            if $hunk->{start} > $cursor;
        push @result, @{$hunk->{replace}};
        $cursor = $hunk->{end};
    }
    push @result, @{$base}[$cursor .. $#$base] if $cursor <= $#$base;

    return \@result;
}

1;