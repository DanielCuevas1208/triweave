# Triweave

Triweave is a small Perl library for merging two changed text files against one common base.

It keeps independent edits and marks overlapping edits with readable conflict regions.

## Value

Three-way merging helps preserve both edits when two branches changed different source lines.

Word-level merging also combines independent edits inside one line.

Triweave fits review tools, generated text workflows, and small command-line utilities.

## Architecture

- `Triweave::Diff` computes deterministic longest-common-subsequence hunks.
- `Triweave` merges line hunks, then tries token-level merging for one changed line.
- `Triweave::Patch` writes and reads a small, validated patch format.
- `bin/triweave` provides merge, patch-write, and patch-apply commands.

The library uses Perl core modules only.

## Setup

Requirements:

- Perl 5.30 or newer.
- `cpanminus` for dependency installation.
- `Test::More` for tests.

Install dependencies:

```text
cpanm --installdeps --with-develop .
```

Run tests:

```text
prove -Ilib -v
```

The committed `cpanfile.snapshot` is empty because the project uses no CPAN distributions.

## Merge example

Run the clean fixture:

```text
perl -MFile::Path=make_path -e "make_path('examples/output')"
perl -Ilib bin/triweave merge --base examples/base.txt --left examples/left-clean.txt --right examples/right-clean.txt --output examples/output/clean.txt
```

Sample output:

```text
clean merge written to examples/output/clean.txt
```

The merged file contains:

```text
The swift brown hound
jumps over the sleepy dog.
Owner: platform-team
Status: ready
```

A conflict writes markers and exits with status `2`:

```text
<<<<<<< left
Status: ready
||||||| base
Status: draft
=======
Status: blocked
>>>>>>> right
```

## Patch example

Write a patch from one changed file:

```text
perl -Ilib bin/triweave patch write --base examples/base.txt --changed examples/left-clean.txt --output examples/left.twpatch
perl -Ilib bin/triweave patch apply --base examples/base.txt --patch examples/left.twpatch --output examples/output/left.txt
```

The patch stores line hunks, newline state, and a SHA-256 base digest.

## Library API

```perl
use Triweave qw(merge_text);

my $result = merge_text($base, $left, $right);
print $result->{text};
die 'conflicts found' unless $result->{clean};
```

`merge_files` reads three files, writes the result, and returns the same result structure.

## Limitations

- The merger treats LF as the line separator.
- Word merging preserves whitespace tokens but does not understand programming language syntax.
- Conflict markers are line-oriented when word edits overlap.
- Binary files and directory trees are outside the project scope.
- Different final-newline edits use the left version when both branches changed that state.

## Test status

`prove -Ilib -v` covers clean merges, word-level merges, conflicts, files, patch round trips, validation, and the CLI.

The CI workflow tests Perl 5.30 and Perl 5.38 on Ubuntu.

Local execution is blocked here because Perl, cpanminus, and prove are unavailable.

## License

Triweave is available under the MIT License.