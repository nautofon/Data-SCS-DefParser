#! /usr/bin/env perl

use v5.36;
use lib 'lib';

use Archive::SCS::GameDir;
use Data::SCS::DefParser;
use Getopt::Long qw( GetOptions :config auto_help );

GetOptions 'csv' => \my $csv;


# Detect company/branch relationships
# (see also: example/company_branches.pl)

my $game   = $ARGV[0] // '';
my $base   = Archive::SCS::GameDir->new( game => $game )->mounted('base.scs');
my $parser = Data::SCS::DefParser->new( mount => $game );
my $data   = $parser->data;

my %companies;
for my $branch ( keys $data->{company}{permanent}->%* ) {
  my $company = eval {
    my $logo_mat = $base->read_entry("material/ui/company/small/$branch.mat");
    $logo_mat =~ m/source *: *"(.+?)\.tobj"/ and $1
  };
  $company ||= $branch;
  push $companies{$company}{branches}->@*, $branch;
  $companies{$company}{name} = $data->{company}{permanent}{$branch}{name};
}


# Create and output locations table

my @locations = $parser->all_locations(\%companies, $data);

for my $loc (@locations) {
  # Get human-readable names for the output
  $loc->{city}    = $data->{city}{ $loc->{city} }{city_name};
  $loc->{country} = $data->{country}{data}{ $loc->{country} }{name};
  $loc->{company} = $companies{ $loc->{company} }{name};
}

if ($csv) {
  require Text::CSV;
  Text::CSV::csv(
    headers     => [qw( city country company branch prefab )],
    in          => \@locations,
    out         => \*STDOUT,
    encoding    => 'UTF-8',
    eol         => $/,
    quote_space => 0,
  );
}
else {
  require JSON::PP;
  print JSON::PP->new->ascii->canonical->pretty->encode( \@locations );
}


=head1 NAME

all_locations.pl - Produce table showing all company locations in the game

=head1 SYNOPSIS

  example/all_locations.pl        # Mount game install dir
  example/all_locations.pl ATS    # Mount dir for named game
  example/all_locations.pl path/  # Mount given game dir

  example/all_locations.pl        > locations.json
  example/all_locations.pl --csv  > locations.csv

=head1 AUTHOR

L<nautofon|https://github.com/nautofon>

=head1 COPYRIGHT

nautofon has dedicated this example code to the Commons by waiving
all of their rights to the example code worldwide under copyright
law and all related or neighboring legal rights they had in the
example code, to the extent allowable by law (CC0).

Works under CC0 do not require attribution. When using or citing
the example code, you should not imply endorsement by the author.
