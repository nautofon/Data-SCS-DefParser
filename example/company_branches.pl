#! /usr/bin/env perl

use v5.36;
use lib 'lib';

use Archive::SCS::GameDir;
use Data::SCS::DefParser;
use Encode qw( encode );
use Getopt::Long qw( GetOptions :config auto_help );

GetOptions 'yaml' => \my $yaml;


# Detect company/branch relationships

my $game = $ARGV[0] // '';
my $data = Data::SCS::DefParser->new( mount => $game )->data;
my $base = Archive::SCS::GameDir->new( game => $game )->mounted('base.scs');

# Note: Using raw_data() above is possible, too, and it would be considerably
# faster than data(). However, the output format of raw_data() is still
# evolving and there is a (very small) risk that the company.permanent data
# will be moved to another location in the output hash tree.

my %companies;
for my $branch ( sort keys $data->{company}{permanent}->%* ) {

  # The .mat of a company's UI logo texture is usually shared between all
  # branches of that company. We can use the name of this texture to identify
  # and gather branches that belong to the same company.
  my $company = eval {
    my $logo_mat = $base->read_entry("material/ui/company/small/$branch.mat");
    $logo_mat =~ m/source *: *"(.+?)\.tobj"/ and $1
  };

  # If a company branch doesn't have a .mat file, it's probably not actually
  # used anywhere in the game. This is a rare situation, but it can happen.
  # Depending on what your goal is, you could just use the $branch token as
  # fallback value, which will treat each such branch as a separate company,
  # or a constant string, which will gather all such branches in one place.
  $company ||= 'fallback';

  push $companies{$company}{branches}->@*, $branch;
  $companies{$company}{name} = $data->{company}{permanent}{$branch}{name};
}


# Output result

# Make sure the human-readable name in the fallback hash entry isn't misleading.
undef $companies{fallback}{name}
  if exists $companies{fallback} and $companies{fallback}{branches}->@* > 1;

if ($yaml) {
  require YAML::PP;
  print encode 'UTF-8', YAML::PP->new->dump_string( \%companies );
}
else {
  require JSON::PP;
  print JSON::PP->new->ascii->canonical->pretty->encode( \%companies );
}


=head1 NAME

company_branches.pl - Show company/branch relationships

=head1 SYNOPSIS

  example/company_branches.pl        # Mount game install dir
  example/company_branches.pl ATS    # Mount dir for named game
  example/company_branches.pl path/  # Mount given game dir

  example/company_branches.pl        > companies.json
  example/company_branches.pl --yaml > companies.yaml

=head1 AUTHOR

L<nautofon|https://github.com/nautofon>

=head1 COPYRIGHT

nautofon has dedicated this example code to the Commons by waiving
all of their rights to the example code worldwide under copyright
law and all related or neighboring legal rights they had in the
example code, to the extent allowable by law (CC0).

Works under CC0 do not require attribution. When using or citing
the example code, you should not imply endorsement by the author.
