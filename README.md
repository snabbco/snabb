# Snabb Switch

[![Build Status](https://travis-ci.org/SnabbCo/snabbswitch.svg?branch=master)](https://travis-ci.org/SnabbCo/snabbswitch)

Check out the [Snabb Switch
wiki](https://github.com/SnabbCo/snabbswitch/wiki) to learn about the
project.

The information below is for making technical contributions.

## Goal

> *If a system is to serve the creative spirit, it must be entirely
> comprehensible to a single individual.* -- [Dan
> Ingalls](http://ftp.squeak.org/docs/OOPSLA.Squeak.html)

Snabb Switch lowers the barrier of entry to create new
production-ready network functions. This used to be the realm of
professional system programmers, but now network engineers can do it
for themselves too.

To become a success the software needs to be quick to comprehend.
Imagine the typical Snabb Switch hacker is someone with a networking
problem to solve, a rusty understanding of C, and a copy of
[Programming in Lua](http://www.lua.org/pil/) open on their
desk. Our mission is to help this person solve their problem by
scripting Snabb Switch.

The code needs to be surprisingly simple. The first reaction should
be: "Is that really all there is to it?"

### Tactics

> *A well-written program is its own heaven; a poorly-written program
> is its own hell.* -- [Tao of Programming](http://www.canonical.org/~kragen/tao-of-programming.html)

1. Keep it short. Make every line count.
2. Do the simplest thing that could possibly work.
3. You aren't gonna need it.
4. Kill your darlings.
5. Start with slow code. Later, profile and optimize it.

### Budget

> *If I look back at my own life and try to pick out the parts that
> were most creative, I can't help but notice that they occurred when
> I was forced to work under the toughest constraints.* -- Donald Knuth

Snabb Switch has adopted these limits:

* 10,000 lines of source.
* 1 MB executable size.
* 1 second to compile snabbswitch.
* 1 minute to compile with dependencies (LuaJIT, etc).
* 0.1% of source lines wider than 80 columns.

### Rules

Be conservative and follow the rules below when you are working on the
core modules, but feel welcome to indulge your creativity when you are
writing new apps.

Imitate the style of [Programming in Lua (5.1
Edition)](http://www.lua.org/pil/) and of the code we already have.

Indent code the same way that Emacs would with default settings.
(That's three spaces for Lua and four spaces for C.) Use spaces
instead of tabs.

Thoughtfully rewrite code when you can achieve the same goal in a
simpler way. Simpler means less code and/or fewer concepts. (Make sure
you understand code before you rewrite it.)

Appreciate it when someone makes the effort to understand and improve
code you have written. This is a fine compliment between programmers.
Everybody's code can be improved. (So can everybody's improvements.)

Use `module()`.

### Github workflow

Create a topic branch for each change you make: a new feature, a bug
fix, an experimental idea.

Send a Github "pull request" as soon as you are ready for feedback on
your code. Iterate by considering the feedback, making any changes
that you feel are justified, and resubmitting the pull request.

Learn to love [Git interactive
rebase](https://help.github.com/articles/interactive-rebase) for
managing the commits on your topic branch. Rebase to clean up your
commits before sending a pull request. (The easy way to do this is to
squash them into one commit.)

Refer to the [OpenShift Github
Workflow](https://www.openshift.com/wiki/github-workflow-for-submitting-pull-requests)
when in doubt.

### Communication

Use the
[snabb-devel](https://groups.google.com/forum/#!forum/snabb-devel)
mailing list for general technical discussions. Submit code with
Github pull requests. Report bugs with Github issues.


### Benchmark Results

[![Benchmark Results](http://lab1.snabb.co:2008/~max/benchmarks.png)](https://travis-ci.org/SnabbCo/snabbswitch.svg?branch=master)