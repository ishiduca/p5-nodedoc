use inc::Module::Install;
name 'Nodedoc';
all_from 'lib/Nodedoc.pm';

requires 'File::Basename';
requires 'File::Spec';
requires 'Cwd';
requires 'JSON::pp';
requires 'Smart::Options';  # for nodedoc
requires 'Mouse::Util::TypeConstraints';  # for nodedoc
requires 'Data::Validator'; # for nodedoc
requires 'YAML';            # for nodedoc

tests 't/*.t';
#author_tests 'xt';

install_script 'bin/nodedoc';

test_requires 'Test::More';

WriteAll;

