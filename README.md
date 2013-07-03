# NAME

Git::Hooks - A framework for implementing Git hooks.

# VERSION

version 0.046

# SYNOPSIS

A single script can implement several Git hooks:

        #!/usr/bin/env perl

        use Git::Hooks;

        PRE_COMMIT {
            my ($git) = @_;
            # ...
        };

        COMMIT_MSG {
            my ($git, $msg_file) = @_;
            # ...
        };

        run_hook($0, @ARGV);

Or you can use Git::Hooks plugins or external hooks, driven by the
single script below. These hooks are enabled by Git configuration
options. (More on this later.)

        #!/usr/bin/env perl

        use Git::Hooks;

        run_hook($0, @ARGV);

# INTRODUCTION

"Git is a fast, scalable, distributed revision control system with an
unusually rich command set that provides both high-level operations
and full access to
internals. ([Git README](https://github.com/gitster/git\#readme))"

In order to really understand what this is all about you need to
understand [Git](http://git-scm.org/) and its hooks. You can read
everything about this in the
[documentation](http://git-scm.com/documentation) references on that
site.

A [Git hook](http://schacon.github.com/git/githooks.html) is a
specifically named program that is called by the git program during
the execution of some operations. At the last count, there were
exactly 16 different hooks which can be used. They must reside under
the `.git/hooks` directory in the repository. When you create a new
repository, you get some template files in this directory, all of them
having the `.sample` suffix and helpful instructions inside
explaining how to convert them into working hooks.

When Git is performing a commit operation, for example, it calls these
four hooks in order: `pre-commit`, `prepare-commit-msg`,
`commit-msg`, and `post-commit`. The first three can gather all
sorts of information about the specific commit being performed and
decide to reject it in case it doesn't comply to specified
policies. The `post-commit` can be used to log or alert interested
parties about the commit just done.

There are several useful hook scripts available elsewhere, e.g.
[https://github.com/gitster/git/tree/master/contrib/hooks](https://github.com/gitster/git/tree/master/contrib/hooks) and
[http://google.com/search?q=git+hooks](http://google.com/search?q=git+hooks). However, when you try to
combine the functionality of two or more of those scripts in a single
hook you normally end up facing two problems.

- __Complexity__

    In order to integrate the functionality of more than one script you
    have to write a driver script that's called by Git and calls all the
    other scripts in order, passing to them the arguments they
    need. Moreover, some of those scripts may have configuration files to
    read and you may have to maintain several of them.

- __Inefficiency__

    This arrangement is inefficient in two ways. First because each script
    runs as a separate process, which usually have a high start up cost
    because they are, well, scripts and not binaries. (For a dissent view
    on this, see
    [this](http://gnustavo.wordpress.com/2012/06/28/programming-languages-start-up-times/).)
    And second, because as each script is called in turn they have no
    memory of the scripts called before and have to gather the information
    about the transaction again and again, normally by calling the `git`
    command, which spawns yet another process.

Git::Hooks is a framework for implementing Git hooks and driving
existing external hooks in a way that tries to solve these problems.

Instead of having separate scripts implementing different
functionality you may have a single script implementing all the
functionality you need either directly or using some of the existing
plugins, which are implemented by Perl scripts in the Git::Hooks::
namespace. This single script can be used to implement all standard
hooks, because each hook knows when to perform based on the context in
which the script was called.

If you already have some handy hooks and want to keep using them,
don't worry. Git::Hooks can drive external hooks very easily.

# USAGE

There are a few simple steps you should do in order to set up
Git::Hooks so that you can configure it to use some predefined plugins
or start coding your own hooks.

The first step is to create a generic script that will be invoked by
Git for every hook. If you are implementing hooks in your local
repository, go to its `.git/hooks` sub-directory. If you are
implementing the hooks in a bare repository in your server, go to its
`hooks` sub-directory.

You should see there a bunch of files with names ending in `.sample`
which are hook examples. Create a three-line script called, e.g.,
`git-hooks.pl`, in this directory like this:

        $ cd /path/to/repo/.git/hooks

        $ cat >git-hooks.pl <<EOT
        #!/usr/bin/env perl
        use Git::Hooks;
        run_hook($0, @ARGV);
        EOT

        $ chmod +x git-hooks.pl

Now you should create symbolic links pointing to it for each hook you
are interested in. For example, if you are interested in a
`commit-msg` hook, create a symbolic link called `commit-msg`
pointing to the `git-hooks.pl` file. This way, Git will invoke the
generic script for all hooks you are interested in. (You may create
symbolic links for all 16 hooks, but this will make Git call the
script for all hooked operations, even for those that you may not be
interested in. Nothing wrong will happen, but the server will be doing
extra work for nothing.)

        $ ln -s git-hooks.pl commit-msg
        $ ln -s git-hooks.pl post-commit
        $ ln -s git-hooks.pl pre-receive

As is, the script won't do anything. You have to implement some hooks
in it, use some of the existing plugins, or set up some external
plugins to be invoked properly. Either way, the script should end with
a call to `run_hook` passing to it the name with which it was called
(`$0`) and all the arguments it received (`@ARGV`).

## Implementing Hooks

You may implement your own hooks using one of the hook _directives_
described in the HOOK DIRECTIVES section below. Your hooks may be
implemented in the generic script you have created. They must be
defined after the `use Git::Hooks` line and before the `run_hook()`
line.

A hook should return a boolean value indicating if it was
successful. __run\_hook__ dies after invoking all hooks if at least one
of them returned false.

__run\_hook__ invokes the hooks inside an eval block to catch any
exception, such as if a __die__ is used inside them. When an exception
is detected the hook is considered to have failed and the exception
string (__$@__) is showed to the user.

The best way to produce an error message is to invoke the
__Git::More::error__ method passing a prefix and a message for uniform
formating.

For example:

    # Check if every added/updated file is smaller than a fixed limit.

    my $LIMIT = 10 * 1024 * 1024; # 10MB

    PRE_COMMIT {
        my ($git) = @_;

        my @changed = $git->command(qw/diff --cached --name-only --diff-filter=AM/);

        my $errors = 0;

        foreach ($git->command('ls-files' => '-s', @changed)) {
            chomp;
            my ($mode, $sha, $n, $name) = split / /;
            my $size = $git->command('cat-file' => '-s', $sha);
            $size <= $LIMIT
                or $git-error('CheckSize', "File '$name' has $size bytes, more than our limit of $LIMIT.\n"
                    and $errors++;
        }

        return $errors == 0;
    };

    # Check if every added/changed Perl file respects Perl::Critic's code
    # standards.

    PRE_COMMIT {
        my ($git) = @_;
        my %violations;

        my @changed = grep {/\.p[lm]$/} $git->command(qw/diff --cached --name-only --diff-filter=AM/);

        foreach ($git->command('ls-files' => '-s', @changed)) {
            chomp;
            my ($mode, $sha, $n, $name) = split / /;
            require Perl::Critic;
            state $critic = Perl::Critic->new(-severity => 'stern', -top => 10);
            my $contents = $git->command('cat-file' => $sha);
            my @violations = $critic->critique(\$contents);
            $violations{$name} = \@violations if @violations;
        }

        if (%violations) {
            # FIXME: this is a lame way to format the output.
            require Data::Dumper;
            $git->error('Perl::Critic Violations', Data::Dumper::Dumper(\%violations));
            return 0;
        }

        return 1;
    };

Note that you may define several hooks for the same operation. In the
above example, we've defined two PRE\_COMMIT hooks. Both are going to
be executed when Git invokes the generic script during the pre-commit
phase.

You may implement different kinds of hooks in the same generic
script. The function `run_hook()` will activate just the ones for
the current Git phase.

## Using Plugins

There are several hooks already implemented as plugin modules, which
you can use. Some are described succinctly below. Please, see their
own documentation for more details.

- Git::Hooks::CheckAcls

    Allow you to specify Access Control Lists to tell who can commit or
    push to the repository and affect which Git refs.

- Git::Hooks::CheckJira

    Integrate Git with the [JIRA](http://www.atlassian.com/software/jira/)
    ticketing system by requiring that every commit message cites valid
    JIRA issues.

- Git::Hooks::CheckLog

    Check commit log messages formatting.

- Git::Hooks::CheckRewrite

    Check if a __git rebase__ or a __git commit --amend__ is safe, meaning
    that no rewritten commit is contained by any other branch besides the
    current one. This is useful, for instance, to prevent rebasing commits
    already pushed.

- Git::Hooks::CheckStructure

    Check if newly added files and references (branches and tags) comply
    with specified policies, so that you can impose a strict structure to
    the repository's file and reference hierarchies.

- Git::Hooks::GerritChangeId

    Inserts a `Change-Id` line in the commit log message to allow
    integration with Gerrit's code review system.

Each plugin may be used in one or, sometimes, multiple hooks. Their
documentation is explicit about this.

These plugins are configured by Git's own configuration framework,
using the `git config` command or by directly editing Git's
configuration files. (See `git help config` to know more about Git's
configuration infrastructure.)

To enable a plugin you must add it to the `githooks.plugin`
configuration option.

The CONFIGURATION section below explains this in more detail.

## Invoking external hooks

Since the default Git hook scripts are taken by the symbolic links to
the Git::Hooks generic script, you must install any other hooks
somewhere else. By default, the `run_hook` routine will look for
external hook scripts in the directory `.git/hooks.d` (which you must
create) under the repository. Below this directory you should have
another level of directories, named after the default hook names,
under which you can drop your external hooks.

For example, let's say you want to use some of the hooks in the
[standard Git package](https://github.com/gitster/git/blob/b12905140a8239ac687450ad43f18b5f0bcfb62e/contrib/hooks/)).
You should copy each of those scripts to a file under the appropriate
hook directory, like this:

- `.git/hooks.d/pre-auto-gc/pre-auto-gc-battery`
- `.git/hooks.d/pre-commit/setgitperms.perl`
- `.git/hooks.d/post-receive/post-receive-email`
- `.git/hooks.d/update/update-paranoid`

Note that you may install more than one script under the same
hook-named directory. The driver will execute all of them in a
non-specified order.

If any of them exits abnormally, __run\_hook__ dies with an appropriate
error message.

## Gerrit Hooks

[Gerrit](http://search.cpan.org/perldoc?gerrit.googlecode.com) is a web based code review and project
management for Git based projects. It's based on
[JGit](http://www.eclipse.org/jgit/), which is a pure Java
implementation of Git.

Up to version 2.6.0, Gerrit still doesn't support Git standard
hooks. However, it implements its own [special hooks](http://gerrit-documentation.googlecode.com/svn/Documentation/2.6/config-hooks.html).
__Git::Hooks__ currently supports only two of Gerrit hooks:

### ref-update

The __ref-update__ hook is executed synchronously when a user performs
a push to a branch. It's purpose is the same as Git's __update__ hook
and Git::Hooks's plugins usually support them both together.

### patchset-created

The __patchset-created__ hook is executed asynchrounously when a user
performs a push to one of Gerrit's virtual branches (refs/for/\*) in
order to record a new review request. This means that one cannot stop
the request from happening just by dying inside the hook. Instead,
what one needs to do is to use Gerrit's API to accept or reject the
new patchset as a reviewer.

Git::Hooks does this using a `Gerrit::REST` object. There are a few
configuration options to set up this Gerrit interaction, which are
described below.

This hook's purpose is usually to verify the project's policy
compliance. Plugins that implement `pre-commit`, `commit-msg`,
`update`, or `pre-receive` hooks usually also implement this Gerrit
hook.

# CONFIGURATION

Git::Hooks is configured via Git's own configuration
infrastructure. There are a few global options which are described
below. Each plugin may define other specific options which are
described in their own documentation. The options specific to a plugin
usually are contained in a configuration subsection of section
`githooks`, named after the plugin base name. For example, the
`Git::Hooks::CheckAcls` plugin has its options contained in the
configuration subsection `githooks.checkacls`.

You should get comfortable with `git config` command (read `git help
config`) to know how to configure Git::Hooks.

When you invoke `run_hook`, the command `git config --list` is
invoked to grok all configuration affecting the current
repository. Note that this will fetch all `--system`, `--global`,
and `--local` options, in this order. You may use this mechanism to
define configuration global to a user or local to a repository.

## githooks.plugin PLUGIN

To enable a plugin you must add it to this configuration option, like
this:

    $ git config --add githooks.plugin CheckAcls

To enable more than one plugin, simply repeat the command for the next
one:

    $ git config --add githooks.plugin CheckJira

A plugin may hook itself to one or more hooks. `CheckJira`, for
example, hook itself to three: `commit-msg`, `pre-receive`, and
`update`. It's important that the corresponding symbolic links be
created pointing from the hook names to the generic script so that the
hooks are effectively invoked.

In the previous examples, the plugins were referred to by their short
names. In this case they are looked for in three places, in this
order:

1. In the `githooks` directory under the repository path (usually in
`.git/githooks`), so that you may have repository specific hooks (or
repository specific versions of a hook).
2. In every directory specified with the `githooks.plugins` option.  You
may set it more than once if you have more than one directory holding
your hooks.
3. In Git::Hooks installation.

The first match is taken as the desired plugin, which is executed (via
`do`) and the search stops. So, you may want to copy one of the
standard plugins and change it to suit your needs better. (Don't shy
away from sending your changes back to the author, please.)

However, if you use the fully qualified module name of the plugin in
the configuration, then it will be simply `required` as a normal
module. For example:

    $ git config --add githooks.plugin My::Hook::CheckSomething

## githooks.disable PLUGIN

This option disables plugins enabled by the `githooks.plugin`
option. It's useful if you want to enable a plugin globally and only
disable it for some repositories. For example:

    $ git config --global --add githooks.plugin  CheckJira
    $ git config --local  --add githooks.disable CheckJira

You also may temporarily disable a plugin by assigning to "0" an
environment variable with its name. This is useful sometimes, when you
are denied some perfectly fine commit by one of the check plugins. For
example, suppose you got an error from the CheckLog plugin because you
used an uncommon word that is not in the system's dictionary yet. If
you don't intend to use the word again you can bypass all CheckLog
checks this way:

    $ CheckLog=0 git commit

This works for every hook. For plugins specified by fully qualified
module names, the environment variable name has to match the last part
of it. For example, to disable the `My::Hook::CheckSomething` plugin
you must define an environment variable called `CheckSomething`.

Note, however, that this works for local hooks only. Remote hooks
(like __update__ or __pre-receive__) are run on the server. You can set
up the server so that it defines the appropriate variable, but this
isn't so useful as for the local hooks, as it's intended for
once-in-a-while events.

## githooks.plugins DIR

This option specify a list of directories where plugins are looked for
besides the default locations, as explained in the `githooks.plugin`
option above.

## githooks.externals \[01\]

By default the driver script will look for external hooks after
executing every enabled plugins. You may disable external hooks
invocation by setting this option to 0.

## githooks.hooks DIR

You can tell this plugin to look for external hooks in other
directories by specifying them with this option. The directories
specified here will be looked for after the default directory
`.git/hooks.d`, so that you can use this option to have some global
external hooks shared by all of your repositories.

Please, see the plugins documentation to know about their own
configuration options.

## githooks.groups GROUPSPEC

You can define user groups in order to make it easier to configure
access control plugins. Use this option to tell where to find group
definitions in one of these ways:

- file:PATH/TO/FILE

    As a text file named by PATH/TO/FILE, which may be absolute or
    relative to the hooks current directory, which is usually the
    repository's root in the server. It's syntax is very simple. Blank
    lines are skipped. The hash (\#) character starts a comment that goes
    to the end of the current line. Group definitions are lines like this:

        groupA = userA userB @groupB userC

    Each group must be defined in a single line. Spaces are significant
    only between users and group references.

    Note that a group can reference other groups by name. To make a group
    reference, simple prefix its name with an at sign (@). Group
    references must reference groups previously defined in the file.

- GROUPS

    If the option's value doesn't start with any of the above prefixes, it
    must contain the group definitions itself.

## githooks.userenv STRING

When Git is performing its chores in the server to serve a push
request it's usually invoked via the SSH or a web service, which take
care of the authentication procedure. These services normally make the
authenticated user name available in an environment variable. You may
tell this hook which environment variable it is by setting this option
to the variable's name. If not set, the hook will try to get the
user's name from the `GERRIT_USER_EMAIL` or the `USER` environment
variable, in this order, and let it undefined if it can't figure it
out.

The Gerrit hooks unfortunately do not have access to the user's
id. But they get the user's full name and email instead. Git:Hooks
takes care so that two environment variables are defined in the hooks,
as follows:

- GERRIT\_USER\_NAME

    This contains the user's full name, such as "User Name".

- GERRIT\_USER\_EMAIL

    This contains the user's email, such as "user@example.net".

If the user name is not directly available in an environment variable
you may set this option to a code snippet by prefixing it with
`eval:`. The code will be evaluated and its value will be used as the
user name.

For example, if the Gerrit user email is not what you want to use as
the user id, you can set the `githooks.userenv` configuration option
to grok the user id from one of these environment variables. If the
user id is always identical to the part of the email before the at
sign, you can configure it like this:

    git config githooks.userenv \
      'eval:(exists $ENV{GERRIT_USER_EMAIL} && $ENV{GERRIT_USER_EMAIL} =~ /([^@]+)/) ? $1 : undef'

This variable is useful for any hook that need to authenticate the
user performing the git action.

## githooks.admin USERSPEC

There are several hooks that perform access control checks before
allowing a git action, such as the ones installed by the `CheckAcls`
and the `CheckJira` plugins. It's useful to allow some people (the
"administrators") to bypass those checks. These hooks usually allow
the users specified by this variable to do whatever they want to the
repository. You may want to set it to a group of "super users" in your
team so that they can "fix" things more easily.

The value of each option is interpreted in one of these ways:

- username

    A `username` specifying a single user. The username specification
    must match "/^\\w+$/i" and will be compared to the authenticated user's
    name case sensitively.

- @groupname

    A `groupname` specifying a single group.

- ^regex

    A `regex` which will be matched against the authenticated user's name
    case-insensitively. The caret is part of the regex, meaning that it's
    anchored at the start of the username.

## githooks.abort-commit \[01\]

This option is true (1) by default, meaning that the `pre-commit` and
the `commit-msg` hooks will abort the commit if they detect anything
wrong in it. This may not be the best way to handle errors, because
you must remember to retrieve your carefully worded commit message
from the `.git/COMMIT_EDITMSG` to try it again, and it is easy to
forget about it and lose it.

Setting this to false (0) makes these hooks simply warn the user via
STDERR but let the commit succeed. This way, the user can correct any
mistake with a simple `git commit --amend` and doesn't run the risk
of losing the commit message.

## githooks.gerrit.url URL
=head2 githooks.gerrit.username USERNAME
=head2 githooks.gerrit.password PASSWORD

These three options are required if you enable Gerrit hooks. They are
used to construct the `Gerrit::REST` object that is used to interact
with Gerrit.

## githooks.gerrit.review\_label LABEL

This option defines the
[label](http://gerrit-documentation.googlecode.com/svn/Documentation/2.6/config-labels.html)
that must be used in Gerrit's review process. If not specified, the
standard `Code-Review` label is used.

## githooks.gerrit.vote\_ok +N

This option defines the vote that must be used to approve a review. If
not specified, +1 is used.

## githooks.gerrit.vote\_nok -N

This option defines the vote that must be used to reject a review. If
not specified, -1 is used.

# MAIN FUNCTION

## run\_hook(NAME, ARGS...)

This is the main routine responsible to invoke the right hooks
depending on the context in which it was called.

Its first argument must be the name of the hook that was
called. Usually you just pass `$0` to it, since it knows to extract
the basename of the parameter.

The remaining arguments depend on the hook for which it's being
called. Usually you just pass `@ARGV` to it. And that's it. Mostly.

        run_hook($0, @ARGV);

# HOOK DIRECTIVES

Hook directives are routines you use to register routines as hooks.
Each one of the hook directives gets a routine-ref or a single block
(anonymous routine) as argument. The routine/block will be called by
`run_hook` with proper arguments, as indicated below. These arguments
are the ones gotten from @ARGV, with the exception of the ones
identified by 'GIT' which are `Git::More` objects that can be used to
grok detailed information about the repository and the current
transaction. (Please, refer to `Git::More` specific documentation to
know how to use them.)

Note that the hook directives resemble function definitions but they
aren't. They are function calls, and as such must end with a
semi-colon.

Some hooks are invoked before an action (e.g., `pre-commit`) so that
one can check some condition. If the condition holds, they must simply
end without returning anything. Otherwise, they should invoke the
`error` method on the GIT object passing a suitable error message. On
some hooks, this will prevent Git from finishing its operation.

Other hooks are invoked after the action (e.g., `post-commit`) so
that its outcome cannot affect the action. Those are usually used to
send notifications or to signal the completion of the action someway.

You may learn about every Git hook by invoking the command `git help
hooks`. Gerrit hooks are documented in the [project site](http://gerrit-documentation.googlecode.com/svn/Documentation/2.6/config-hooks.html).

Also note that each hook directive can be called more than once if you
need to implement more than one specific hook.

- APPLYPATCH\_MSG(GIT, commit-msg-file)
- PRE\_APPLYPATCH(GIT)
- POST\_APPLYPATCH(GIT)
- PRE\_COMMIT(GIT)
- PREPARE\_COMMIT\_MSG(GIT, commit-msg-file \[, msg-src \[, SHA1\]\])
- COMMIT\_MSG(GIT, commit-msg-file)
- POST\_COMMIT(GIT)
- PRE\_REBASE(GIT, upstream \[, branch\])
- POST\_CHECKOUT(GIT, prev-head-ref, new-head-ref, is-branch-checkout)
- POST\_MERGE(GIT, is-squash-merge)
- PRE\_PUSH(GIT, remote-name, remote-url)

    The `pre-push` hook was introduced in Git 1.8.2. The default hook
    gets two arguments: the name and the URL of the remote which is being
    pushed to. It also gets a variable number of arguments via STDIN with
    lines of the form:

        <local ref> SP <local sha1> SP <remote ref> SP <remote sha1> LF

    The information from these lines is read and can be fetched by the
    hooks using the `Git::Hooks::get_input_data` method.

- PRE\_RECEIVE(GIT)

    The `pre-receive` hook gets a variable number of arguments via STDIN
    with lines of the form:

        <old-value> SP <new-value> SP <ref-name> LF

    The information from these lines is read and can be fetched by the
    hooks using the `Git::Hooks::get_input_data` method or, perhaps more
    easily, by using the `Git::More::get_affected_refs` and the
    `Git::More::get_affected_ref_rage` methods.

- UPDATE(GIT, updated-ref-name, old-object-name, new-object-name)
- POST\_RECEIVE(GIT)
- POST\_UPDATE(GIT, updated-ref-name, ...)
- PRE\_AUTO\_GC(GIT)
- POST\_REWRITE(GIT, command)

    The `post-rewrite` hook gets a variable number of arguments via STDIN
    with lines of the form:

        <old sha1> SP <new sha1> SP <extra info> LF

    The `extra info` and the preceeding SP are optional.

    The information from these lines is read and can be fetched by the
    hooks using the `Git::Hooks::get_input_data` method.

- REF\_UPDATE(GIT, OPTS)
=item \* PATCHSET\_CREATED(GIT, OPTS)

    These are Gerrit-specific hooks. Gerrit invokes them passing a list of
    option/value pairs which are converted into a hash, which is passed by
    reference as the OPTS argument. In addition to the option/value pairs,
    a `Gerrit::REST` object is created and inserted in the OPTS hash with
    the key 'gerrit'. This object can be used to interact with the Gerrit
    server.  For more information, please, read the ["Gerrit Hooks"](#Gerrit Hooks)
    section.

# METHODS FOR PLUGIN DEVELOPERS

Plugins should start by importing the utility routines from
Git::Hooks:

    use Git::Hooks qw/:utils/;

Usually at the end, the plugin should use one or more of the hook
directives defined above to install its hook routines in the
appropriate hooks.

Every hook routine receives a Git::More object as its first
argument. You should use it to infer all needed information from the
Git repository.

Please, take a look at the code for the standard plugins under the
Git::Hooks:: namespace in order to get a better understanding about
this. Hopefully it's not that hard.

The utility routines implemented by Git::Hooks are the following:

## post\_hook SUB

Plugin developers may be interested in performing some action
depending on the overall result of every check made by every other
hook. As an example, Gerrit's `patchset-created` hook is invoked
asynchronously, meaning that the hook's exit code doesn't affect the
action that triggered the hook. The proper way to signal the hook
result for Gerrit is to invoke it's API to make a review. But we want
to perform the review once, at the end of the hook execution, based on
the overall result of all enabled checks.

To do that plugin developers can use this routine to register
callbacks that are invoked at the end of `run_hooks`. The callbacks
are called with the following arguments:

- HOOK\_NAME

    The basename of the invoked hook.

- GIT

    The Git::More object that was passed to the plugin hooks.

- ARGS...

    The remaining arguments that were passed to the plugin hooks.

The callbacks may see if there were any errors signalled by the plugin
hook by invoking the `get_errors` method on the GIT object. They may
be used to signal the hook result in any way they want, but they
should not die or they will prevent other post hooks to run.

## is\_ref\_enabled(REF, SPEC, ...)

This routine returns a boolean indicating if REF matches one of the
ref-specs in SPECS. REF is the complete name of a Git ref and SPECS is
a list of strings, each one specifying a rule for matching ref names.

As a special case, it returns true if REF is undef or if there is no
SPEC whatsoever, meaning that by default all refs/commits are enabled.

You may want to use it, for example, in an `update`, `pre-receive`,
or `post-receive` hook which may be enabled depending on the
particular refs being affected.

Each SPEC rule may indicate the matching refs as the complete ref
name (e.g. "refs/heads/master") or by a regular expression starting
with a caret (`^`), which is kept as part of the regexp.

## im\_memberof(GIT, USER, GROUPNAME)

This routine tells if USER belongs to GROUPNAME. The groupname is
looked for in the specification given by the `githooks.groups`
configuration variable.

## match\_user(GIT, SPEC)

This routine checks if the authenticated user (as returned by the
`Git::More::authenticated_user` method) matches the specification,
which may be given in one of the three different forms acceptable for
the `githooks.admin` configuration variable above, i.e., as a
username, as a @group, or as a ^regex.

## im\_admin(GIT)

This routine checks if the authenticated user (again, as returned by
the `Git::More::authenticated_user` method) matches the
specifications given by the `githooks.admin` configuration variable.

## eval\_gitconfig(VALUE)

This routine makes it easier to grok config values as Perl code. If
`VALUE` is a string beginning with `eval:`, the remaining of it is
evaluated as a Perl expression and the resulting value is returned. If
`VALUE` is a string beginning with `file:`, the remaining of it is
treated as a file name which contents are evaluated as Perl code and
the resulting value is returned. Otherwise, `VALUE` itself is
returned.

# SEE ALSO

- `Git::More`

    A Git extension with some goodies for hook developers.

- `Gerrit::REST`

    A thin wrapper around Gerrit's REST API.

# AUTHOR

Gustavo L. de M. Chaves <gnustavo@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by CPqD <www.cpqd.com.br>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
