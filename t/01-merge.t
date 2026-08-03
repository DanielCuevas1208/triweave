use strict;
use warnings;
use lib 'lib';
use Test::More;
use Triweave qw(merge_text);

my $base = <<'TEXT';
The quick brown fox
jumps over the lazy dog.
Owner: core-team
Status: draft
TEXT
my $left = <<'TEXT';
The swift brown fox
jumps over the lazy dog.
Owner: platform-team
Status: draft
TEXT
my $right = <<'TEXT';
The quick brown hound
jumps over the sleepy dog.
Owner: core-team
Status: ready
TEXT
my $expected = <<'TEXT';
The swift brown hound
jumps over the sleepy dog.
Owner: platform-team
Status: ready
TEXT

my $clean = merge_text($base, $left, $right);
is $clean->{text}, $expected, 'independent line and word edits merge';
is $clean->{conflicts}, 0, 'clean merge has no conflicts';
is $clean->{clean}, 1, 'clean merge reports clean status';

my $conflicting = merge_text(
    "Status: draft\n",
    "Status: ready\n",
    "Status: blocked\n",
);
is $conflicting->{text}, <<'TEXT', 'conflict contains all three regions';
<<<<<<< left
Status: ready
||||||| base
Status: draft
=======
Status: blocked
>>>>>>> right
TEXT
is $conflicting->{conflicts}, 1, 'one overlap reports one conflict';
is $conflicting->{clean}, 0, 'conflict reports non-clean status';

my $identical = merge_text("one\ntwo\n", "one\nchanged\n", "one\nchanged\n");
is $identical->{text}, "one\nchanged\n", 'identical edits are emitted once';
is $identical->{conflicts}, 0, 'identical edits do not conflict';

my $inserted = merge_text("one\n", "one\ntwo\n", "one\n");
is $inserted->{text}, "one\ntwo\n", 'one-sided insertion is preserved';

my $adjacent = merge_text(
    "first\nsecond\nthird\n",
    "FIRST\nsecond\nthird\n",
    "first\nsecond\nTHIRD\n",
);
is $adjacent->{text}, "FIRST\nsecond\nTHIRD\n", 'adjacent line edits remain independent';
is $adjacent->{conflicts}, 0, 'adjacent line edits do not conflict';

my $custom = merge_text(
    "key: old\n",
    "key: left\n",
    "key: right\n",
    labels => { left => 'ours', base => 'common', right => 'theirs' },
);
like $custom->{text}, qr/^<<<<<<< ours/m, 'custom conflict labels are supported';
like $custom->{text}, qr/\|\|\|\|\|\|\| common/m, 'custom base label is supported';
like $custom->{text}, qr/>>>>>>> theirs/m, 'custom right label is supported';

ok !eval { merge_text(undef, '', '') }, 'undefined input is rejected';
like $@, qr/expects base/, 'undefined input reports a useful error';

done_testing;