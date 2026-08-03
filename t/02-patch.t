use strict;
use warnings;
use lib 'lib';
use Test::More;
use Triweave::Patch;

my $base = "alpha\nbeta\ngamma\n";
my $changed = "alpha\nBETA\ngamma\ndelta\n";
my $patch = Triweave::Patch->from_text($base, $changed);
my $serialized = $patch->as_string;

like $serialized, qr/^Triweave-Patch: 1/m, 'patch has a version header';
like $serialized, qr/^Base-Digest: [0-9a-f]{64}$/m, 'patch has a base digest';
my $parsed = Triweave::Patch->parse($serialized);
is $parsed->apply_to_text($base), $changed, 'parsed patch round-trips the changed text';

my $empty = Triweave::Patch->from_text($base, $base);
is $empty->apply_to_text($base), $base, 'empty patch preserves the base';
my $empty_round_trip = Triweave::Patch->parse($empty->as_string);
is $empty_round_trip->apply_to_text($base), $base, 'empty patch can be serialized and parsed';

ok !eval { $parsed->apply_to_text("wrong\n") }, 'wrong base is rejected';
like $@, qr/base does not match/, 'wrong base reports the digest failure';

ok !eval { Triweave::Patch->parse("Triweave-Patch: 1\nHunks:\n0\n") }, 'incomplete patch is rejected';
like $@, qr/missing Base-Lines/, 'incomplete patch reports the missing field';

done_testing;