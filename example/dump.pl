#! /usr/bin/env perl

use v5.36;
use lib 'lib';

use Data::SCS::DefParser;
use Encode qw( encode );
use Getopt::Long qw( GetOptions :config auto_help );


# Interpret command-line arguments

GetOptions(
  'parse=s@' => \my @parse,
  'yaml!'    => \my $yaml,
);

my $mount_archives;
if (@ARGV == 0) {
  # Archive::SCS::GameDir default: Mount the first game install it can find.
  $mount_archives = '';
}
elsif (@ARGV == 1 && ! -f $ARGV[0]) {
  # If the arg is a dir name, mount def.scs and all dlc_*.scs inside the dir.
  # Otherwise, pass on the arg string to Archive::SCS::GameDir.
  $mount_archives = $ARGV[0];
}
else {
  # Assume all args are the pathnames of archives to mount.
  $mount_archives = [@ARGV];
}

my $parse_entries;
$parse_entries = [@parse] if @parse;


# Parse and output game data

my $parser = Data::SCS::DefParser->new(
  mount => $mount_archives,
  parse => $parse_entries,
);
my $data = $parser->data;

if ($yaml) {
  require YAML::PP;
  print encode 'UTF-8', YAML::PP->new->dump_string( $data );
}
else {
  require JSON::PP;
  print JSON::PP->new->ascii->canonical->pretty->encode( $data );
}


=head1 NAME

dump.pl - Dump city/company data in JSON or YAML format

=head1 SYNOPSIS

  example/dump.pl         # Mount game install dir
  example/dump.pl ATS     # Mount install dir for named game
  example/dump.pl path/to/gamedir/    # Mount given game dir
  example/dump.pl archive.scs ...     # Mount archive files

  example/dump.pl        > data.json
  example/dump.pl --yaml > data.yaml  # requires YAML::PP

  # Parse specific archive entries only
  # (defaults to city, company, country SII entries)
  example/dump.pl --parse foo.sii --parse bar.sii

=head1 AUTHOR

L<nautofon|https://github.com/nautofon>

=head1 COPYRIGHT

nautofon has dedicated this example code to the Commons by waiving
all of their rights to the example code worldwide under copyright
law and all related or neighboring legal rights they had in the
example code, to the extent allowable by law (CC0).

Works under CC0 do not require attribution. When using or citing
the example code, you should not imply endorsement by the author.
