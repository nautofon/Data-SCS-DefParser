use 5.034;
use warnings;

package ATS_DB v1.41.0;

use Path::Tiny qw(path);
use File::Find qw(find);
use Feature::Compat::Try;
use XXX;
use Exporter qw(import);
our @EXPORT = qw(ats_db);

our $cargo = 0;
our $positions = 1;
our $tidy = 1;
# set @def to the list of def directories to use
# (if the list is empty, defaults will be used)
our @def;


sub trim ($) {
  my $str = shift;
  $str =~ s/^\s+//s;
  $str =~ s/\s+$//s;
  return $str;
}


sub find_file {
  my $file = shift;
  for my $def (@def, '.') {
    my $path = path("$def/$file")->absolute;
    return "$path" if $path->is_file;
  }
  die "Couldn't find file '$file' in: @def";
}


sub find_dirs {
  my $dir = shift;
  my @dirs;
  for my $def (@def, '.') {
    my $path = path("$def/$dir")->absolute;
    push @dirs, "$path" if $path->is_dir;
  }
  return @dirs;
}


sub parse_block {
  my $data = shift;
  my ($pre, $in) = $data =~ m/^([^\{]*)\{(.*)\}/s;
  return (trim $pre, trim $in);
}


sub include_file {
  my $file = shift;
  my $inc = path(find_file $file)->slurp;
  my @inc = grep {$_} map {trim $_} split m/\n/, $inc;
  return @inc;
}


sub parse_sii {
  my $file = shift;
  my ($magic, $unit) = parse_block path($file)->slurp;
  die "Expected SiiNunit, found '$magic'" unless $magic eq 'SiiNunit';
  my @input = grep {$_} map {trim $_} split m/\n/, $unit;
  my @lines;
  while (my $line = shift @input) {
    if (my ($inc) = $line =~ m/^\@include\s+"([^"]+)"$/) {
      unshift @input, include_file $inc;
      next;
    }
    push @lines, $line;
  }
  @lines = map {trim $_} map {
    m{/\*|\*/} and die "Multi-line comments unimplemented";
    # clip comments
    s{#.*$|//.*$}{}r;
  } @lines;
  @lines = grep {$_} map {trim $_} map {
    # make sure { and } stand by their own on a line
    my @line = ($_);
    while ($line[$#line] =~ m/^([^\{]+)([\{\}])(.*)/) {
      pop @line;
      push @line, $1, $2, $3;
    }
    @line;
  } @lines;
  return @lines;
}


sub parse_sui_data_value {
  my $value = shift;
  if ( $value =~ m/^"([^"]+)"$/
      || $value =~ m/^(\([^\)]+\))$/
      || $value =~ m/^(\S+)$/ ) {
    return "$1";
  }
  die "Unknown value format: '$value'";
}


sub parse_sui_data {
  my ($ats_data, $key, @raw) = @_;
  my $data = {};
  # parse block contents
  for (@raw) {
    if ($tidy) {
      # skip currently useless clutter
      next if /city_name_localized/ || /sort_name/ || /trailer_look/ || /time_zone/;
      next if /map_._offsets/ || /license_plate/;
    }
    if (/(\w+)\s*:\s*(.+)$/) {
      $data->{$1} = parse_sui_data_value $2;
      next;
    }
    if (/(\w+)\[(\d*)\]\s*:\s*(.+)$/) {
      if ($2) {
        $data->{$1}[0+$2] = parse_sui_data_value $3;
      }
      else {
        $data->{$1} //= [];
        push @{$data->{$1}}, parse_sui_data_value $3;
      }
      next;
    }
    die "Unkown data format: '$_'";
  }
  #$data->{_raw} = [@raw];
  #$data->{_key_raw} = $key;
  # parse key and insert data
  my ($type, $path) = $key =~ m/^(\S+)\s*:\s+(\S+)$/;
  #$data->{_type} = $type;
  if ($tidy) {
    # skip currently useless clutter
    return if $type eq 'license_plate_data';
  }
  if ($path =~ m/^[\.\w]+$/) {
    my $hashpath = $path =~ s/\./'}{'/gr;
    $hashpath =~ s/^\'}/_$type'}/;
    eval "\$ats_data->{'$hashpath'} = \$data";
  }
  else {
    die "Unimplemented path '$path'";
  }
}


sub parse_sui_blocks {
  my ($ats_data, @lines) = @_;
  my $block = 0;
  my @raw;
  my $key;
  for my $i (0..$#lines) {
    0 <= $block <= 1 or die $block;
    if ($lines[$i] eq '{') {
      $block++;
      $key = $lines[$i-1];
      @raw = ();
      next;
    }
    if ($lines[$i] eq '}') {
      parse_sui_data $ats_data, $key, @raw;
      $key = undef;
      $block--;
      next;
    }
    if ($block) {
      push @raw, $lines[$i];
      next;
    }
  }
}


sub read_pos {
  my $ats_data = shift;
  my $pos_dir = path(__FILE__)->absolute->parent->child('pos');
  $pos_dir->is_dir or return;
  my @files = grep { $_->basename =~ /\.txt$/ } $pos_dir->children;
  my (@pos, %pos);
  push @pos, split /\r?\n/, $_->slurp for @files;
  for my $line (grep {$_} map {trim $_} @pos) {
    $line =~ /^ *([^;]*) +;[^;]* \(sec([-+][0-9]+)([-+][0-9]+)\);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$/
      or next;
    $pos{$1} = {
      sx => $2, sy => $3,
      cx => $4, cz => $5, cy => $6,
      ca => $7, cb => $8,
    };
  }
  for my $city (sort keys $ats_data->{city}->%*) {
    $pos{$city} or next;
    $ats_data->{city}{$city}{_east} = $pos{$city}{cx};
    $ats_data->{city}{$city}{_north} = $pos{$city}{cy};
  }
}


sub init_def {
  return if @def;
  
  my @siblings = path(__FILE__)->absolute->parent->children;
  @def = sort map { "$_" } (
    (grep { $_->is_dir && $_->basename eq 'def' } @siblings),
    (grep { $_->is_dir } map { $_->child('def') } @siblings),
  );
}


sub ats_db_files {
  return @_ if @_;
  
  my @files;
  for my $def (@def) {
    my $path = path($def);
    my $basename = $path->basename;
    $basename = $path->parent->basename if $basename eq 'def';
    my @filenames = (
      "country.sii",
      "city.sii",
      "company.sii",
      "city.$basename.sii",
      "company.$basename.sii",
#      "map_data.sii",
      $cargo ? "cargo.sii" : (),
    );
    for my $file (@filenames) {
      push @files, $file if $path->child($file)->is_file;
    }
  }
  return sort @files;
}


# call this with a list of .sii files to read
# (if the list is empty, defaults will be used)
sub ats_db {
  init_def;
  
  # get base data for all cities and companies
  my @files = map {find_file $_} ats_db_files(@_);
  my @lines;
  push @lines, parse_sii $_ for @files;
  my $ats_data = {};
  parse_sui_blocks $ats_data, @lines;
  
  # read company in/out cargo data
  for my $company (sort keys $ats_data->{company}{permanent}->%*) {
    my (@in_files, @out_files);
    find({wanted=>sub{
      push @in_files, $File::Find::name if /\.sii$/;
    }}, find_dirs "company/$company/in");
    my $in_data = {};
    parse_sui_blocks $in_data, map { (parse_sii $_) } @in_files;
    my @in_cargo = map {
      $in_data->{_cargo_def}{$_}{cargo} =~ s/^cargo\.//r;
    } sort keys $in_data->{_cargo_def}->%*;
    find({wanted=>sub{
      push @out_files, $File::Find::name if /\.sii$/;
    }}, find_dirs "company/$company/out");
    my $out_data = {};
    parse_sui_blocks $out_data, map { (parse_sii $_) } @out_files;
    my @out_cargo = map {
      $out_data->{_cargo_def}{$_}{cargo} =~ s/^cargo\.//r;
    } sort keys $out_data->{_cargo_def}->%*;
    if ($cargo) {
      $ats_data->{company}{permanent}{$company}{in_cargo} = \@in_cargo;
      $ats_data->{company}{permanent}{$company}{out_cargo} = \@out_cargo;
    }
  }
  
  # relate city data and company data
  for my $company (sort keys $ats_data->{company}{permanent}->%*) {
    my @company_files;
    find({wanted=>sub{
      push @company_files, $File::Find::name if /\.sii$/;
    }}, find_dirs "company/$company/editor");
    my @lines = ();
    push @lines, parse_sii $_ for @company_files;
    my $company_data = {};
    parse_sui_blocks $company_data, @lines;
    my @company_defs = map {
      $company_data->{_company_def}{$_}
    } sort keys $company_data->{_company_def}->%*;
    push $ats_data->{company}{permanent}{$company}{company_def}->@*, @company_defs;
  }
  
  read_pos $ats_data if $positions;
  
  return $ats_data;
}


1;
