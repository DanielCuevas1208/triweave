package Triweave;

use strict;
use warnings;
use Exporter qw(import);
use Carp qw(croak);
use Triweave::Diff qw(diff_hunks);

our $VERSION = '0.1.0';
our @EXPORT_OK = qw(merge_text merge_files);

sub merge_text {
    my ($base_text, $left_text, $right_text, %options) = @_;
    croak 'merge_text expects base, left, and right text'
        unless defined $base_text && defined $left_text && defined $right_text;

    my ($base, $base_newline) = _split_text($base_text);
    my ($left, $left_newline) = _split_text($left_text);
    my ($right, $right_newline) = _split_text($right_text);

    my ($lines, $conflicts) = _merge_segments($base, $left, $right, 1, \%options);
    my $final_newline = _choose_final_newline(
        $base_newline, $left_newline, $right_newline
    );

    return {
        text      => join("\n", @$lines) . ($final_newline ? "\n" : ''),
        conflicts => $conflicts,
        clean     => $conflicts == 0 ? 1 : 0,
    };
}

sub merge_files {
    my ($base_path, $left_path, $right_path, $output_path, %options) = @_;
    for my $path ($base_path, $left_path, $right_path, $output_path) {
        croak 'merge_files expects four file paths' unless defined $path;
    }

    my $result = merge_text(
        _read_file($base_path),
        _read_file($left_path),
        _read_file($right_path),
        %options,
    );
    _write_file($output_path, $result->{text});
    return $result;
}

sub _read_file {
    my ($path) = @_;
    open my $handle, '<:raw', $path or croak "cannot read $path: $!";
    local $/;
    my $content = <$handle>;
    close $handle or croak "cannot close $path: $!";
    return defined $content ? $content : '';
}

sub _write_file {
    my ($path, $content) = @_;
    open my $handle, '>:raw', $path or croak "cannot write $path: $!";
    print {$handle} $content or croak "cannot write $path: $!";
    close $handle or croak "cannot close $path: $!";
}

sub _split_text {
    my ($text) = @_;
    my $trailing_newline = $text =~ /\n\z/ ? 1 : 0;
    $text =~ s/\n\z// if $trailing_newline;
    my @lines = length $text ? split(/\n/, $text, -1) : ();
    return (\@lines, $trailing_newline);
}

sub _choose_final_newline {
    my ($base, $left, $right) = @_;
    return $left if $left == $right;
    return $right if $left == $base;
    return $left if $right == $base;
    return $left;
}

sub _merge_segments {
    my ($base, $left, $right, $allow_word_merge, $options) = @_;
    my @events;
    push @events, map { { %$_, side => 'left' } } @{diff_hunks($base, $left)};
    push @events, map { { %$_, side => 'right' } } @{diff_hunks($base, $right)};
    @events = sort {
        $a->{start} <=> $b->{start}
            || $a->{end} <=> $b->{end}
            || $a->{side} cmp $b->{side}
    } @events;

    return ([ @$base ], 0) unless @events;

    my @merged;
    my $conflicts = 0;
    my $cursor = 0;
    while (@events) {
        my $first = shift @events;
        my @group = ($first);
        my ($start, $end) = ($first->{start}, $first->{end});

        my $expanded = 1;
        while ($expanded) {
            $expanded = 0;
            for (my $index = 0; $index < @events;) {
                my $event = $events[$index];
                if (_event_overlaps_span($event, $start, $end)) {
                    push @group, splice(@events, $index, 1);
                    $start = $event->{start} if $event->{start} < $start;
                    $end = $event->{end} if $event->{end} > $end;
                    $expanded = 1;
                } else {
                    $index++;
                }
            }
        }

        push @merged, @{$base}[$cursor .. $start - 1] if $start > $cursor;
        my @base_segment = $start < $end ? @{$base}[$start .. $end - 1] : ();
        my @left_hunks = map { $_ } grep { $_->{side} eq 'left' } @group;
        my @right_hunks = map { $_ } grep { $_->{side} eq 'right' } @group;
        my @left_segment = @{_segment_for($base, $start, $end, \@left_hunks)};
        my @right_segment = @{_segment_for($base, $start, $end, \@right_hunks)};

        if (_same_sequence(\@left_segment, \@right_segment)) {
            push @merged, @left_segment;
        } elsif (_same_sequence(\@left_segment, \@base_segment)) {
            push @merged, @right_segment;
        } elsif (_same_sequence(\@right_segment, \@base_segment)) {
            push @merged, @left_segment;
        } elsif ($allow_word_merge && @base_segment == 1
            && @left_segment == 1 && @right_segment == 1) {
            my $word_merge = _merge_word_line(
                $base_segment[0], $left_segment[0], $right_segment[0]
            );
            if (defined $word_merge) {
                push @merged, $word_merge;
            } else {
                $conflicts++;
                push @merged, _conflict_block(
                    \@left_segment, \@base_segment, \@right_segment, $options
                );
            }
        } else {
            $conflicts++;
            push @merged, _conflict_block(
                \@left_segment, \@base_segment, \@right_segment, $options
            );
        }

        $cursor = $end;
    }
    push @merged, @{$base}[$cursor .. $#$base] if $cursor <= $#$base;

    return (\@merged, $conflicts);
}

sub _event_overlaps_span {
    my ($event, $start, $end) = @_;
    return 1 if $start == $end && $event->{start} == $start;
    return 1 if $event->{start} < $end && $start < $event->{end};
    return 1 if $event->{start} == $event->{end}
        && $start < $event->{start} && $event->{start} < $end;
    return 0;
}

sub _segment_for {
    my ($base, $start, $end, $hunks) = @_;
    my @segment;
    my $cursor = $start;
    for my $hunk (sort { $a->{start} <=> $b->{start} } @$hunks) {
        push @segment, @{$base}[$cursor .. $hunk->{start} - 1]
            if $hunk->{start} > $cursor;
        push @segment, @{$hunk->{replace}};
        $cursor = $hunk->{end};
    }
    push @segment, @{$base}[$cursor .. $end - 1] if $cursor < $end;
    return \@segment;
}

sub _same_sequence {
    my ($left, $right) = @_;
    return 0 unless @$left == @$right;
    for my $index (0 .. $#$left) {
        return 0 unless $left->[$index] eq $right->[$index];
    }
    return 1;
}

sub _merge_word_line {
    my ($base, $left, $right) = @_;
    my @base_words = ($base =~ /(\s+|[^\s]+)/g);
    my @left_words = ($left =~ /(\s+|[^\s]+)/g);
    my @right_words = ($right =~ /(\s+|[^\s]+)/g);
    my ($words, $conflicts) = _merge_segments(
        \@base_words, \@left_words, \@right_words, 0, {}
    );
    return undef if $conflicts;
    return join '', @$words;
}

sub _conflict_block {
    my ($left, $base, $right, $options) = @_;
    my $labels = $options->{labels} || {};
    my $left_label = $labels->{left} || 'left';
    my $base_label = $labels->{base} || 'base';
    my $right_label = $labels->{right} || 'right';
    return (
        "<<<<<<< $left_label",
        @$left,
        "||||||| $base_label",
        @$base,
        '=======',
        @$right,
        ">>>>>>> $right_label",
    );
}

1;