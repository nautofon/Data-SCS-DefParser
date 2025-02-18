#!perl

use lib 'lib';
use Test2::V0 -target => 'Data::SCS::DefParser';

{ my $todo = todo 'C-style comments unimplemented'; ok lives {
my $syntax = CLASS->new(
  mount => ['t/fixtures/syntax'],
  parse => 'syntax.sii',
)->raw_data;
is $syntax->{foo}{bar}, 123, 'comments';
}}

{ my $todo = todo 'comments are skipped even inside strings';
ok lives {
my $syntax = CLASS->new(
  mount => ['t/fixtures/syntax'],
  parse => 'syntax.sii',
)->raw_data;
is $syntax->{string}{in1}, 'a/*b*/c', 'block comment inside string';
is $syntax->{string}{in2}, 'a/*b"c*/', 'comment and quote';
is $syntax->{string}{in3}, 'a//b', 'line comment inside string';
};
}

ok dies { CLASS->new(
  mount => ['t/fixtures/syntax'],
  parse => 'multiline-cmt.sii',
)->raw_data }, 'multi-line comment';

ok dies { CLASS->new(
  mount => ['t/fixtures/syntax'],
  parse => 'nested-block.sii',
)->raw_data }, 'nested {} dies';

done_testing;
