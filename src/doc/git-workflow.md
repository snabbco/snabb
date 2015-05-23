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

### For users

1. Clone the [SnabbCo/snabbswitch](https://github.com/SnabbCo/snabbswitch) repository.
2. Check out and build the `master` branch.
3. Pull when you want to update to the latest stable release.

### For contributors

1. [Create your own fork](https://help.github.com/articles/fork-a-repo/) of Snabb Switch on Github.
2. Develop and debug your contribution on a new [topic branch](https://git-scm.com/book/en/v2/Git-Branching-Branching-Workflows#Topic-Branches).
3. Make a final cleanup of your code before review. (Last chance to rebase.)
4. Submit a Github [Pull Request](https://help.github.com/articles/using-pull-requests/#initiating-the-pull-request)
   to the master branch.
5. Respond to feedback and correct problems by pushing additional commits.

There are two milestones in the process of your accepting your contribution:

1. Your work is merged onto `next` to be tested for inclusion in the next release.
2. Your work is released by merge onto `master`.

Your Pull Request will automatically close when the contribution has
been released. The whole process should take about one month from
initial contribution to inclusion in an official release.

### For application developers

1. [Fork](https://help.github.com/articles/fork-a-repo/) your own
   repository on Github.
2. Create a [long-lived branch](branches.md) where new development of your application will be done.
3. Create a directory `src/program/myapplication/` and develop your application.
4. `git merge master` regularly to stay synchronized with the main line of development.
5. Optional: Send releases of your application to master with Pull Requests.

The code in your `src/program/myapplication/` directory is developed
according to your own rules and tastes. If there are parts of this
code that you especially want to have reviewed (or do not want to have
reviewed) then please explain this in your Pull Request. The only
necessary review is to make sure that applications do not negatively
impact each other or change shared code without enough review.

Common Snabb Switch code should be updated with individual changes
according to the *For contributors* workflow. Please do not bundle
substantial changes to the core software with updates to the
application.

If you do not want to include your application in the main Snabb
Switch release then this is no problem. You can simply pull from the
master branch to receive updates and skip the step of pushing back.

### For maintainers

Goals:

1. Quickly merge good features onto the `next` branch.
2. Quickly merge good bug fixes onto the `fixes` branch.
3. Make sure `next` is stable when it is time to make a release.
4. Merge `next` and `fixes` merge to master according to the release schedule.

More verbiage to follow...

