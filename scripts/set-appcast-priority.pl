#!/usr/bin/perl
use strict;
use warnings;

my ($path, $build, $priority) = @ARGV;
die "usage: set-appcast-priority.pl APPCAST BUILD routine|important|critical\n"
    unless defined $path && defined $build && defined $priority;
die "invalid build\n" unless $build =~ /^[1-9][0-9]*$/;
die "invalid priority\n" unless $priority =~ /^(routine|important|critical)$/;

open my $input, '<', $path or die "cannot read $path: $!\n";
local $/;
my $xml = <$input>;
close $input;

if ($xml !~ /xmlns:broccoli=/) {
    $xml =~ s{<rss\s}{<rss xmlns:broccoli="https://yednapg.github.io/broccoli/appcast" };
}

my $quoted_build = quotemeta($build);
my $updated = 0;
$xml =~ s{(<item\b.*?</item>)}{
    my $item = $1;
    if ($item =~ /sparkle:version="$quoted_build"/ ||
        $item =~ /<sparkle:version>\s*$quoted_build\s*<\/sparkle:version>/) {
        $item =~ s{\s*<broccoli:priority>.*?</broccoli:priority>}{}gs;
        $item =~ s{\s*</item>}{\n            <broccoli:priority>$priority</broccoli:priority>\n        </item>}s;
        $updated++;
    }
    $item;
}gse;

die "expected exactly one appcast item for build $build, updated $updated\n" unless $updated == 1;
open my $output, '>', $path or die "cannot write $path: $!\n";
print {$output} $xml;
close $output;

