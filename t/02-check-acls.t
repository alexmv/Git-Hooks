# -*- cperl -*-

use 5.010;
use strict;
use warnings;
use lib 't';
use Test::More tests => 30;

BEGIN { require "test-functions.pl" };

my ($repo, $file, $clone, $T, $gerrit) = new_repos();
foreach my $git ($repo, $clone) {
    install_hooks($git, undef, qw/update pre-receive/);
}

sub check_can_push {
    my ($testname, $ref) = @_;
    new_commit($repo, $file);
    test_ok($testname, $repo,
	    'push', '--tags', $clone->repo_path(), $ref || 'master');
}

sub check_cannot_push {
    my ($testname, $ref, $error) = @_;
    new_commit($repo, $file);
    test_nok_match($testname, $error || qr/\) cannot \S+ ref /, $repo,
		   'push', '--tags', $clone->repo_path(), $ref || 'master');
}

# Enable plugin
$clone->command(config => 'githooks.update', 'check-acls');

# Without any specific configuration all pushes are denied
$ENV{USER} //= 'someone';	# guarantee that the user is known, at least.
check_cannot_push('deny by default');

# Check if disabling by ENV is working
$ENV{CheckAcls} = 0;
check_can_push('allow if plugin is disabled by ENV');
delete $ENV{CheckAcls};

# Configure admin environment variable
$clone->command(config => 'check-acls.userenv', 'ACL_ADMIN');
$clone->command(config => 'check-acls.admin', 'admin');

$ENV{'ACL_ADMIN'} = 'admin2';
check_cannot_push('deny if not admin');

$ENV{'ACL_ADMIN'} = 'admin';
check_can_push('allow if admin user');

$clone->command(config => '--replace-all', 'check-acls.admin', '^adm');
check_can_push('allow if admin matches regex');

$clone->command(config => '--replace-all', 'check-acls.userenv', 'eval:x y z');
check_cannot_push('disallow if userenv cannot eval', 'master', qr/error evaluating userenv value/);

$clone->command(config => '--replace-all', 'check-acls.userenv', 'eval:"nouser"');
check_cannot_push('disallow if userenv eval to nouser');

$clone->command(config => '--replace-all', 'check-acls.userenv', 'eval:$ENV{ACL_ADMIN}');
check_can_push('allow if userenv can eval');

# Configure groups
$clone->command(config => 'githooks.groups', <<'EOF');
admins1 = admin
admins = @admins1
EOF

$clone->command(config => '--replace-all', 'check-acls.admin', '@admins');
check_can_push('allow if admin in group');

$clone->command(config => '--unset', 'check-acls.admin');

$clone->command(config => 'check-acls.acl', 'admin U master');
check_cannot_push('deny ACL master');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin U refs/heads/master');
check_can_push('allow ACL refs/heads/master');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin U refs/heads/branch');
check_cannot_push('deny ACL other ref');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin U ^.*/master');
check_can_push('allow ACL regex ref');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin U !master');
check_cannot_push('deny ACL negated regex ref');

$clone->command(config => '--replace-all', 'check-acls.acl', '^adm U refs/heads/master');
check_can_push('allow ACL regex user');

delete $ENV{VAR};
$clone->command(config => '--replace-all', 'check-acls.acl', '^adm U refs/heads/{VAR}');
check_cannot_push('deny ACL non-interpolated ref');

$ENV{VAR} = 'master';
$clone->command(config => '--replace-all', 'check-acls.acl', '^adm U refs/heads/{VAR}');
check_can_push('allow ACL interpolated ref');

$clone->command(config => '--replace-all', 'check-acls.acl', '@admins U refs/heads/master');
check_can_push('allow ACL user in group ');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin DUR refs/heads/fix');
$repo->command(checkout => '-q', '-b', 'fix');
check_cannot_push('deny ACL create ref', 'heads/fix');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin C refs/heads/fix');
check_can_push('allow create ref', 'heads/fix');

$repo->command(checkout => '-q', 'master');
$repo->command(branch => '-D', 'fix');

check_cannot_push('deny ACL delete ref', ':refs/heads/fix');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin D refs/heads/fix');
check_can_push('allow ACL delete ref', ':refs/heads/fix');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin U refs/heads/master');
check_can_push('allow ACL refs/heads/master again, to force a successful push');

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin CDU refs/heads/master');
$repo->command(reset => '--hard', 'HEAD~2'); # rewind fix locally
check_cannot_push('deny ACL rewrite ref', '+master:master'); # try to push it

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin R refs/heads/master');
check_can_push('allow ACL rewrite ref', '+master:master'); # try to push it

$clone->command(config => '--replace-all', 'check-acls.acl', 'admin CRUD refs/heads/master');
$repo->command(tag => '-a', '-mtag', 'objtag'); # object tag
check_cannot_push('deny ACL push tag');

$clone->command(config => '--add', 'check-acls.acl', 'admin CRUD ^refs/tags/');
check_can_push('allow ACL push tag');


# Gerrit tests

sub check_can_push2gerrit {
    my ($testname) = @_;
    new_commit($gerrit->{git}, $gerrit->{file});
    test_ok($testname, $gerrit->{git}, 'push', 'origin', $gerrit->{branch});
}

sub check_cannot_push2gerrit {
    my ($testname, $error) = @_;
    new_commit($gerrit->{git}, $gerrit->{file});
    test_nok_match($testname, $error || qr/\) cannot \S+ ref /, $gerrit->{git}, 'push', 'origin', $gerrit->{branch});
}

my $markfile = catfile($T, 'patchset_mark');
$gerrit->{remote}->command(qw/config config githooks.gerrit.patchset-created-accept-cmd/, "echo 1 >$markfile");
$gerrit->{remote}->command(qw/config config githooks.gerrit.patchset-created-reject-cmd/, "echo 0 >$markfile");

sub check_can_push2gerrit_for {
    my ($testname) = @_;
    new_commit($gerrit->{local}, $gerrit->{file});
    unlink $markfile;
    my ($ok, $exit, $stdout, $stderr) = test_command($gerrit->{local}, qw[push origin HEAD:refs/for/master@]);
    if (! $ok) {
        fail($testname);
	diag(" exit=$exit\n stdout=$stdout\n stderr=$stderr\n git-version=$git_version\n");
    } elsif (! -r $markfile) {
        fail($testname);
	diag(" patchset-created did not create the mark file\n");
    } else {
        my $mark = read_file($markfile);
        if ($mark) {
            pass($testname);
        } else {
            fail($testname);
            diag(" patchset-created mark failed\n");
        }
    }
}

sub check_cannot_push2gerrit_for {
    my ($testname) = @_;
    new_commit($gerrit->{local}, $gerrit->{file});
    unlink $markfile;
    my ($ok, $exit, $stdout, $stderr) = test_command($gerrit->{local}, qw[push origin HEAD:refs/for/master@]);
    if (! $ok) {
        fail($testname);
	diag(" exit=$exit\n stdout=$stdout\n stderr=$stderr\n git-version=$git_version\n");
    } elsif (! -r $markfile) {
        fail($testname);
	diag(" patchset-created did not create the mark file\n");
    } else {
        my $mark = read_file($markfile);
        if ($mark) {
            fail($testname);
            diag(" patchset-created mark succeeded\n");
        } else {
            pass($testname);
        }
    }
}

SKIP: {
    skip "Gerrit tests need a t/GERRIT_CONFIG file", 3 unless $gerrit;

    install_hooks($gerrit->{remote}, undef, qw/ref-update patchset-created/);

    $gerrit->{remote}->command(qw/config githooks.plugin CheckAcls/);

    check_cannot_push2gerrit('gerrit: deny push by default');

    $gerrit->{remote}->command(qw/config --replace-all CheckAcls.acl/, "$gerrit->{userid} U refs/heads/master");

    check_can_push2gerrit('gerrit: allow ACL refs/heads/master');

    $gerrit->{remote}->command(qw/config --replace-all CheckAcls.acl/, "$gerrit->{userid} U refs/heads/branch");

    check_cannot_push2gerrit('gerrit: deny ACL other ref');

    check_cannot_push2gerrit_for('gerrit for: deny push by default');

    $gerrit->{remote}->command(qw/config --replace-all CheckAcls.acl/, "$gerrit->{userid} U refs/heads/master");

    check_can_push2gerrit_for('gerrit for: allow ACL refs/for/master');
};
