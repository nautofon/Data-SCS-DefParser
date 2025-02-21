requires 'perl' => 'v5.36';

requires 'Archive::SCS';
requires 'Archive::SCS::GameDir';
requires 'Archive::SCS::Directory'; # 1.06
requires 'Path::Tiny' => '0.054';

on test => sub {
  requires 'Test2::V0';
};
