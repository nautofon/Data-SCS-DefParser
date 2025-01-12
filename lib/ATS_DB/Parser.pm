use v5.36;

package ATS_DB::Parser;

use Archive::SCS 1.06;
use Archive::SCS::GameDir;
use Path::Tiny qw(path);
use Feature::Compat::Try;
use JSON::MaybeXS;
use Gzip::Faster;
use XXX;
use Exporter qw(import);
our @EXPORT = qw(ats_db);

our $cargo = 0;
our $positions = 1;
our $tidy = 1;

# The list of directories or archives to mount.
our @def;

# The game name or game/sii directory to use if @def isn't specified.
our $source = path(__FILE__)->absolute->parent->parent->parent->child('sii');

# The list of def file names to parse; def file names may also be
# passed in as arguments to ats_db().
our @filenames = (
  "def/country.sii",
  "def/city.sii",
  "def/company.sii",
  #"def/map_data.sii",
  #"def/sign/mileage_targets.sii",
  "def/world/prefab.sii",
  "def/world/prefab.baker.sii",
  $cargo ? "def/cargo.sii" : (),
);

our $archive;
our %archive_has_entry;
our @company_files;


sub trim :prototype($) {
  my $str = shift;
  $str =~ s/^\s+//s;
  $str =~ s/\s+$//s;
  return $str;
}


sub find_file {
  my $file = shift;
  return $file if $archive_has_entry{ $file };
  warn "Couldn't find file '$file' in: @def";
  return;
}


sub parse_block {
  my $data = shift;
  my ($pre, $in) = $data =~ m/^([^\{]*)\{(.*)\}/s;
  return (trim $pre, trim $in);
}


sub include_file {
  my $file = find_file shift;
  return unless $file;
  my $inc = $archive->read_entry($file);
  utf8::decode($inc);
  my @inc = grep {$_} map {trim $_} split m/\n/, $inc;
  return @inc;
}


sub parse_sii {
  my $file = shift;
  my ($magic, $unit) = parse_block $archive->read_entry($file);
  utf8::decode($unit);
  die "Expected SiiNunit, found '$magic'" unless $magic eq 'SiiNunit';
  my @input = grep {$_} map {trim $_} split m/\n/, $unit;
  my @lines;
  while (my $line = shift @input) {
    if (my ($inc) = $line =~ m/^\@include\s+"([^"]+)"$/) {
      my $inc_path = path("/$file")->parent->relative("/")->child($inc);
      unshift @input, include_file $inc_path;
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
  # parse key and insert data
  my ($type, $path) = $key =~ m/^(\S+)\s*:\s+(\S+)$/;
  if ($tidy) {
    # skip currently useless clutter
    return if $type eq 'license_plate_data';
  }
  # parse block contents
  for (@raw) {
    if ($tidy) {
      # skip currently useless clutter
      next if /city_name_localized/ || /sort_name/ || /time_zone/;
      next if /city_pin_scale_factor/;
      next if /map_._offsets/ || /license_plate/;
      next if $type eq 'prefab_model' && (/model_desc/ || /semaphore_profile/ || /use_semaphores/ || /gps_avoid/ || /use_perlin/ || /detail_veg_max_distance/ || /traffic_rules_input/ || /traffic_rules_output/ || /invisible/ || /category/ || /tweak_detail_vegetation/);
      next if $type eq 'prefab_model' && (/dynamic_lod_/ || /corner\d/);  # code dies for these; not sure why
    }
    if (/(\w+)\s*:\s*(.+)$/) {
      $data->{$1} = parse_sui_data_value $2;
      next;
    }
    if (/(\w+)\[(\d*)\]\s*:\s*(.+)$/) {
      # init array, overwriting scalar array size if present
      $data->{$1} = [] unless ref $data->{$1};
      if (length $2) {
        $data->{$1}[0+$2] = parse_sui_data_value $3;
      }
      else {
        push @{$data->{$1}}, parse_sui_data_value $3;
      }
      next;
    }
    die "Unkown data format: '$_'";
  }
  #$data->{_raw} = [@raw];
  #$data->{_key_raw} = $key;
  #$data->{_type} = $type;
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
    if ($block && $lines[$i] !~ m/"/ && $lines[$i] =~ m/:/) {  # parse Reforma one-liners
      push @raw, split m/(?<=[a-z])\s+/, $lines[$i];
      next;
    }
    if ($block) {
      push @raw, $lines[$i];
      next;
    }
  }
}


sub prefab_json_cache {
  my $ats_data = shift;
  my $cache_dir = path(__FILE__)->absolute->parent->parent->parent->child('data')->child('cache');
  $cache_dir->mkpath;
  my $cache_file = $cache_dir->child('prefab.json.gz');
  if ($cache_file->is_file) {  # read cache
    $ats_data->{prefab} = decode_json gunzip $cache_file->slurp;
  }
  elsif (! $cache_file->exists) {  # write cache
    $cache_file->spew( gzip encode_json $ats_data->{prefab} );
  }
}


my $wiki_names;
sub add_wiki_names {
  my $ats_data = shift;
  for my $city (sort keys $ats_data->{city}->%*) {
    my $wiki_name = $wiki_names->{city}{$city};
    $wiki_name //= $ats_data->{city}{$city}{city_name};
    $ats_data->{city}{$city}{wiki_name} = $wiki_name;
  }
  for my $company (sort keys $ats_data->{company}{permanent}->%*) {
    my $company_name = $ats_data->{company}{permanent}{$company}{name};
    my $wiki_name = $wiki_names->{company}{$company_name} // $company_name;
    $ats_data->{company}{permanent}{$company}{wiki_name} = $wiki_name;
  }
}


sub ats_db_positions {
  my $ats_data = shift;
  my $pos_dir = path(__FILE__)->absolute->parent->parent->parent->child('pos');
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

  my $is_path = $source isa Path::Tiny || $source =~ m|/|;
  if ( $is_path && path($source)->realpath->is_dir ) {
    @def = sort map { "$_" } path( $source )->children( qr/^def|^dlc_/ );

    # ATS_DB originally expected def.scs to be extracted directly into the
    # source dir. In this legacy case, the source dir must be mounted first.
    my $def_dir = "$source/def";
    if ( path($def_dir)->is_dir && ! path($def_dir)->child('def')->is_dir ) {
      @def = ( $source, grep { $_ ne $def_dir } @def );
    }
  }
  else {  # $source is abstract, e.g. 'ATS'
    my $gamedir = Archive::SCS::GameDir->new(game => $source);
    @def = grep { /^def|^dlc_/ } $gamedir->archives;
    @def = map { $gamedir->path->child($_)->stringify } @def;
  }
}


sub ats_db_files {
  return @_ if @_;

  my @files = grep $archive_has_entry{$_}, @filenames;
  for my $def (@def) {
    # Include files from DLCs, with file names containing the DLC archive name.
    my $dlc_name = path($def)->basename =~ s/\.scs$//r;
    push @files, grep $archive_has_entry{$_}, map { s/\.sii$/.$dlc_name.sii/r } @filenames;
  }
  return sort @files;
}


# call this with a list of .sii files to read
# (if the list is empty, defaults will be used)
sub ats_db {
  init_def;
  my $ats_data = ats_db_base_data(@_);
  ats_db_company_cargo($ats_data) if $cargo;
  ats_db_company_city($ats_data);
  ats_db_company_filter($ats_data) if $tidy;
  ats_db_positions($ats_data) if $positions;
  return $ats_data;
}


sub ats_db_base_data {
  if (@def) {
    $archive = Archive::SCS->new;
    $archive->mount($_) for @def;
  }
  undef %archive_has_entry;
  $archive_has_entry{$_} = 1 for my @archive_files = $archive->list_files;
  @company_files = grep { m|^/?def/company/| } @archive_files;

  my @files = grep {defined} map {find_file $_} ats_db_files(@_);
  my @lines;
  push @lines, parse_sii $_ for @files;
  my $ats_data = {};
  parse_sui_blocks $ats_data, @lines;
  add_wiki_names $ats_data;
  return $ats_data;
}


sub ats_db_company_cargo {
  my $ats_data = shift;
  
  # read company in/out cargo data
  for my $company (sort keys $ats_data->{company}{permanent}->%*) {
    my (@in_files, @out_files);
    @in_files = grep { m|/$company/in/[^/]+\.sii$| } @company_files;
    my $in_data = {};
    parse_sui_blocks $in_data, map { (parse_sii $_) } @in_files;
    my @in_cargo = map {
      $in_data->{_cargo_def}{$_}{cargo} =~ s/^cargo\.//r;
    } sort keys $in_data->{_cargo_def}->%*;
    @out_files = grep { m|/$company/out/[^/]+\.sii$| } @company_files;
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
}


sub ats_db_company_city {
  my $ats_data = shift;
  
  # relate city data and company data
  for my $company (sort keys $ats_data->{company}{permanent}->%*) {
    my @editor_files;
    @editor_files = grep { m|/$company/editor/[^/]+\.sii$| } @company_files;
    my @lines = ();
    push @lines, parse_sii $_ for @editor_files;
    my $company_data = {};
    parse_sui_blocks $company_data, @lines;
    my @company_defs = map {
      $company_data->{_company_def}{$_}
    } sort keys $company_data->{_company_def}->%*;
    push $ats_data->{company}{permanent}{$company}{company_def}->@*, @company_defs;
  }
}


sub ats_db_company_filter {
  my $ats_data = shift;
  
  # fix data errors (leftovers from earlier versions etc.)
  delete $ats_data->{company}{permanent}{mcs_con_sit};  # Mud Creek slide
  
  # remove prefab data, except for that of company depots
  my %prefabs;
  for my $company (sort keys $ats_data->{company}{permanent}->%*) {
    $prefabs{$_->{prefab}}++ for $ats_data->{company}{permanent}{$company}{company_def}->@*;
  }
  $ats_data->{prefab}{$_}{_count} = $prefabs{$_} for sort keys %prefabs;
  for my $prefab (sort keys $ats_data->{prefab}->%*) {
    delete $ats_data->{prefab}{$prefab} unless $prefabs{$prefab};
  }
  prefab_json_cache $ats_data;
}


# Legacy wiki_name adjustments
$wiki_names = {
  city => {  # token => fandom page name
    aberdeen_wa  => 'Aberdeen (Washington)',
    carlsbad     => 'Carlsbad (California)',
    carlsbad_nm  => 'Carlsbad (New Mexico)',
    glasgow_mt   => 'Glasgow (Montana)',
    longview_tx  => 'Longview (Texas)',
    longview     => 'Longview (Washington)',
    pajarito     => 'Santa Rosa',
    pedro        => 'Deming',
    sidney       => 'Sidney (Montana)',
    sidney_ne    => 'Sidney (Nebraska)',
    salina_ks    => 'Salina (Kansas)',
  },
  company => {  # name => fandom page name
    '18 Wheels' => '18 Wheels Garage',
    'Airport Dallas Fort Worth' => 'Dallas-Fort Worth Airport',
    'Airport Denver' => 'Denver Air Cargo',
    'Azure' => 'Azure Glasswork',
    'Chemso Ltd.' => 'Chemso',
    'Coastline mining' => 'Coastline Mining',
    'Drake Cars' => 'Drake Car Dealer',
    'Elimax' => 'EliMax',
    'Equos Power Transport' => 'Equos Power',
    'Fish Tail Food' => 'Fish Tail Foods',
    'GARC' => 'GARC Railroads',
    'GF Cargo' => 'Great Falls Cargo Terminal',
    'GreenPetrol' => 'Green Petrol',
    'Intercontinental Airport Houston' => 'Houston Intercontinental Airport',  # 1.46 only
    'Houston Intercont. Airport' => 'Houston Intercontinental Airport',
    'Johnson and Smith‎' => 'Johnson & Smith‎',
    'Lonestar Forwarding' => 'Lone Star Forwarding',
    'Lumen auto' => 'Lumen Auto',
    'Mud Creek slide' => 'Mud Creek Slide',
    'Port of SF' => 'Port of San Francisco',
    'SellGoods' => 'Sell Goods',
    'Sweetbeets' => 'Sweet Beets',
    'Space Center' => 'Space Park Houston',  # 1.46 only
    'Space Park' => 'Space Park Houston',
    'Taylor Construction Group' => 'Taylor',
    'Tera' => 'TERA',
    'US Beverages & Bottling' => 'USBB',
    'Voltison' => 'Voltison Motors',
    'Waldens' => "Walden's",
    'Western Star' => 'Western Star Trucks',
  },
};


1;
