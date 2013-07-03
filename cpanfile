requires 'Carp';
requires 'Cwd';
requires 'Data::Util';
requires 'Error';
requires 'Exporter';
requires 'File::Basename';
requires 'File::Slurp';
requires 'File::Spec::Functions';
requires 'File::Temp';
requires 'Gerrit::REST';
requires 'List::MoreUtils';
requires 'parent';
requires 'perl', '5.010';

recommends 'JIRA::Client';
recommends 'Text::SpellChecker';

on build => sub {
    requires 'Config';
    requires 'File::Path', '2.08';
    requires 'File::Remove';
    requires 'File::pushd';
    requires 'Test::More';
    requires 'URI::file';
};
