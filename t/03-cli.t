use strict;
use warnings;
use lib 'lib';
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

my $dir = tempdir(CLEANUP => 1);
my $base = File::Spec->catfile($dir, 'base.txt');
my $left = File::Spec->catfile($dir, 'left.txt');
my $right = File::Spec->catfile($dir, 'right.txt');
my $merged = File::Spec->catfile($dir, 'merged.txt');
my $patch_path = File::Spec->catfile($dir, 'left.twpatch');
my $patched = File::Spec->catfile($dir, 'patched.txt');

_write($base, "one two three\n");
_write($left, "one TWO three\n");
_write($right, "one two THREE\n");

is system($^X, '-Ilib', 'bin/triweave', 'merge',
    '--base', $base, '--left', $left, '--right', $right, '--output', $merged),
    0, 'CLI writes a clean merge';
is _read($merged), "one TWO THREE\n", 'CLI output contains the merged words';

is system($^X, '-Ilib', 'bin/triweave', 'patch', 'write',
    '--base', $base, '--changed', $left, '--output', $patch_path),
    0, 'CLI writes a patch';
is system($^X, '-Ilib', 'bin/triweave', 'patch', 'apply',
    '--base', $base, '--patch', $patch_path, '--output', $patched),
    0, 'CLI applies a patch';
is _read($patched), _read($left), 'CLI patch output matches the changed file';

done_testing;

sub _write {
    my ($path, $text) = @_;
    open my $handle, '>:raw', $path or die "cannot write $path: $!";
    print {$handle} $text or die "cannot write $path: $!";
    close $handle or die "cannot close $path: $!";
}

sub _read {
    my ($path) = @_;
    open my $handle, '<:raw', $path or die "cannot read $path: $!";
    local $/;
    my $text = <$handle>;
    close $handle or die "cannot close $path: $!";
    return $text;
}