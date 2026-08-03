package Triweave::Patch;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Triweave::Diff qw(diff_hunks apply_hunks);

sub from_text {
    my ($class, $base_text, $changed_text) = @_;
    croak 'from_text expects base and changed text'
        unless defined $base_text && defined $changed_text;

    my ($base, $base_newline) = _split_text($base_text);
    my ($changed, $changed_newline) = _split_text($changed_text);
    return bless {
        base_lines       => scalar @$base,
        base_newline     => $base_newline,
        changed_newline  => $changed_newline,
        base_digest      => sha256_hex($base_text),
        hunks            => diff_hunks($base, $changed),
    }, $class;
}

sub parse {
    my ($class, $patch_text) = @_;
    croak 'parse expects patch text' unless defined $patch_text;
    croak 'patch must use LF line endings' if $patch_text =~ /\r/;

    my @lines = split /\n/, $patch_text, -1;
    pop @lines if @lines && $lines[-1] eq '';
    croak 'invalid patch header' unless shift(@lines) eq 'Triweave-Patch: 1';

    my %header;
    while (@lines && $lines[0] ne 'Hunks:') {
        my $line = shift @lines;
        my ($key, $value) = $line =~ /^(Base-Lines|Base-Final-Newline|Changed-Final-Newline|Base-Digest): (.+)$/;
        croak "invalid patch header line: $line" unless defined $key;
        croak "duplicate patch header: $key" if exists $header{$key};
        $header{$key} = $value;
    }
    croak 'missing Hunks header' unless @lines && shift(@lines) eq 'Hunks:';
    my $hunk_count = shift @lines;
    croak 'invalid hunk count' unless defined $hunk_count && $hunk_count =~ /^\d+$/;
    croak 'missing Base-Lines' unless defined $header{'Base-Lines'} && $header{'Base-Lines'} =~ /^\d+$/;
    croak 'missing Base-Digest' unless defined $header{'Base-Digest'} && $header{'Base-Digest'} =~ /^[0-9a-f]{64}$/;
    for my $key ('Base-Final-Newline', 'Changed-Final-Newline') {
        croak "invalid $key" unless defined $header{$key} && $header{$key} =~ /^(yes|no)$/;
    }

    my @hunks;
    for (1 .. $hunk_count) {
        my $header_line = shift @lines;
        my ($start, $delete_count, $replace_count) = defined $header_line
            ? $header_line =~ /^@@ (\d+),(\d+) \+(\d+) @@$/
            : ();
        croak "invalid hunk header: " . (defined $header_line ? $header_line : 'end of patch')
            unless defined $start;
        croak 'hunk starts before line one' if $start == 0;
        my $zero_start = $start - 1;
        my @replacement;
        for (1 .. $replace_count) {
            my $replacement = shift @lines;
            croak 'missing replacement line' unless defined $replacement && $replacement =~ /^\+(.*)$/;
            push @replacement, $1;
        }
        croak 'hunk exceeds base line count'
            if $zero_start > $header{'Base-Lines'}
            || $zero_start + $delete_count > $header{'Base-Lines'};
        push @hunks, {
            start   => $zero_start,
            end     => $zero_start + $delete_count,
            replace => \@replacement,
        };
    }
    croak 'unexpected content after hunks' if @lines;

    return bless {
        base_lines      => 0 + $header{'Base-Lines'},
        base_newline    => $header{'Base-Final-Newline'} eq 'yes' ? 1 : 0,
        changed_newline => $header{'Changed-Final-Newline'} eq 'yes' ? 1 : 0,
        base_digest     => $header{'Base-Digest'},
        hunks           => \@hunks,
    }, $class;
}

sub as_string {
    my ($self) = @_;
    my @lines = (
        'Triweave-Patch: 1',
        "Base-Lines: $self->{base_lines}",
        'Base-Final-Newline: ' . ($self->{base_newline} ? 'yes' : 'no'),
        'Changed-Final-Newline: ' . ($self->{changed_newline} ? 'yes' : 'no'),
        "Base-Digest: $self->{base_digest}",
        'Hunks:',
        scalar @{$self->{hunks}},
    );
    for my $hunk (@{$self->{hunks}}) {
        my $start = $hunk->{start} + 1;
        my $delete_count = $hunk->{end} - $hunk->{start};
        my $replace_count = scalar @{$hunk->{replace}};
        push @lines, "@@ $start,$delete_count +$replace_count @@";
        push @lines, map { "+$_" } @{$hunk->{replace}};
    }
    return join("\n", @lines) . "\n";
}

sub apply_to_text {
    my ($self, $base_text) = @_;
    croak 'apply_to_text expects base text' unless defined $base_text;
    croak 'patch base does not match' unless sha256_hex($base_text) eq $self->{base_digest};

    my ($base, $base_newline) = _split_text($base_text);
    croak 'patch base line count does not match' unless @$base == $self->{base_lines};
    my $changed = apply_hunks($base, $self->{hunks});
    return join("\n", @$changed) . ($self->{changed_newline} ? "\n" : '');
}

sub write_file {
    my ($self, $path) = @_;
    open my $handle, '>:raw', $path or croak "cannot write $path: $!";
    print {$handle} $self->as_string or croak "cannot write $path: $!";
    close $handle or croak "cannot close $path: $!";
}

sub _split_text {
    my ($text) = @_;
    my $trailing_newline = $text =~ /\n\z/ ? 1 : 0;
    $text =~ s/\n\z// if $trailing_newline;
    my @lines = length $text ? split(/\n/, $text, -1) : ();
    return (\@lines, $trailing_newline);
}

1;