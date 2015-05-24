# Snabb Switch Git Workflow

This document explains the Git workflows that we use to develop and
release Snabb Switch.

## Overview

Snabb Switch development follows a few well-known patterns:

- We follow the distributed development model [described by Linus
  Torvald](https://www.youtube.com/watch?v=4XpnKHJAok8) and pioneered
  by the Linux kernel.
- We use a [merge based workflow](https://www.atlassian.com/git/articles/git-team-workflows-merge-or-rebase/).
- We use the [fork and pull](https://help.github.com/articles/using-pull-requests/#fork--pull)
  model of collaboration.
- We aim to support ad-hoc collaboration inspired by the
  [DMZ Flow](https://gist.github.com/djspiewak/9f2f91085607a4859a66).

## HOWTO

### Download and update the latest release

1. Clone the [SnabbCo/snabbswitch](https://github.com/SnabbCo/snabbswitch) repository.
2. Check out and build the `master` branch.
3. Pull when you want to update to the latest stable release.

### Develop and contribute an improvement

1. [Create your own fork](https://help.github.com/articles/fork-a-repo/) of Snabb Switch on Github.
2. Develop and debug your contribution on a new [topic branch](https://git-scm.com/book/en/v2/Git-Branching-Branching-Workflows#Topic-Branches) based on the latest `master`.
3. Make a final cleanup of your code before review. (Last chance to rebase.)
4. Submit a Github [Pull Request](https://help.github.com/articles/using-pull-requests/#initiating-the-pull-request)
   to the `master` branch.
5. Respond to feedback and correct problems by pushing additional commits.

There are two milestones in the process of accepting your change:

1. Your change is merged onto a branch that feeds `master`, for
   example `next`, `fixes`, `documentation-fixes`, or `nfv`. From this
   point the owner of that branch will push your work upstream
   together with other related changes. They might ask you for help
   but otherwise your work is done.
2. Your change is merged onto `master`. This could happen in a series
   of merge steps, for example `nfv->next->master`. Once this happens
   your code has been officially released as part of Snabb Switch.

### Develop and maintain a new program

Snabb Switch includes programs like `snabbnfv`, `packetblaster`, and
`snsh`. Here is how you can create a new program and take charge of
its development.

1. [Fork](https://help.github.com/articles/fork-a-repo/) your own
   repository on Github.
2. Create a [long-lived branch](branches.md) where new development of your program will be done.
3. Create a directory `src/program/myapplication/` and develop your program.
4. `git merge master` regularly to stay synchronized with the main line of development.
5. Optional: Send releases of your application to `master` with Pull Requests.

The code in your `src/program/myapplication/` directory is developed
according to your own rules and tastes. If there are parts of this
code that you especially want to have reviewed (or do not want to have
reviewed) then please explain this in your Pull Request. The only
necessary review is to make sure that programs do not negatively
impact each other or change shared code without enough review.

Pull Requests that make changes to your application will be referred
to you for merge onto your branch.

Use the *Develop and contribute an improvement* workflow to make
changes to the core Snabb Switch code. Please do not bundle
substantial changes to the core software with updates to your program.

If you do not want to include your program in the main Snabb Switch
release then this is no problem. You can simply pull from `master` to
receive updates and skip the step of pushing back.

### To help maintain Snabb Switch

Here are the best ways to help maintain Snabb Switch:

1. Review Pull Requests to help people quickly improve them.
2. Test the `next` branch and help fix problems before releases.
3. Contribute new `selftest` cases to make our CI more effective.
4. Maintain a [branch](branches.md) where you accept Pull Requests and push them upstream.

