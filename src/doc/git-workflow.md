## Git workflow

How do you engage with the Snabb Switch developer community? The answer depends on what you want to do:

- Use the software, ask questions, report bugs.
- Contribute fixes and improvements.
- Maintain Snabb Switch by reviewing and merging pull requests.
- Create a new application to develop together with the community.

### Using the software

The recommended way to download Snabb Switch is with `git` directly
from from the `master` branch of the `snabbco` repository. This branch
always contains the latest release.

```
$ git checkout https://github.com/snabbco/snabbswitch
$ cd snabbswitch
$ make -j
```

The `master` branch is updated with a new release each month. You can
upgrade by pulling in the latest changes to your local copy:

```
$ git pull
$ make -j
```

This is safe to do at any time because the `master` branch is only
used for publishing the latest release to users. (The active software
development is done on different branches and only merged onto
`master` once it is ready for release.)

You can also switch back and forth between different versions based on
their release tags:

```
$ git checkout v2016.01  # switch to a specific version
$ make -j
...
$ git checkout master    # switch back to latest
$ make -j
```

### Contributing fixes and improvements

The recommended way to contribute improvements to Snabb Switch is with Github Pull Requests. You can do this by following the Github [Using pull requests](https://help.github.com/articles/using-pull-requests/) instructions. Here is a brief summary.

1. "Fork" your own copy of the [`snabbco/snabbswitch`](https://github.com/snabbco/snabbswitch) repository.
2. Push your proposed change to a branch on your repository.
3. Open a Pull Request from your branch. Choose the `master` branch of the `snabbco/snabbswitch` repository as the target branch (this should be the default choice.)
4. Expect that within a few days a qualified maintainer will become the *Assignee* of your Pull Request and work with you to get the change merged. The maintainer may ask you some questions and even require some changes. Once they are satisfied they will merge the change onto their own branch and apply the label `merged` on the Pull Request. Then your work is done and the change is in the pipeline leading to release on the master branch.

Here are some tips for making your contribution smoothly:

- Use a dedicated "topic branch" for each feature or fix.
- Use the Pull Request text to explain why you are proposing the change.
- If the change is a work in progress then prefix the Pull Request title with `[wip]`. This signals that you intened to push more commits before the change is complete.
- If the change is a rough draft that you want early feedback on then prefix the Pull Request name with `[sketch]`. This signals that you may throw the branch away and start over on a new one.

### Becoming a maintainer

Snabb Switch maintainers are the people who review and merge the Pull
Requests on Github. Each maintainer takes care of one or more specific
aspects of Snabb Switch. These aspects are called *subsystems*.

Each subsystem has a dedicated branch and these branches are organized
as a network:

    DIAGRAM: Branches
                                       +--lisper
                       +--max next<----+--documentation<--pdf manual
                       |
           fixes       |
             |         |
    master<--+--next<--+--kbara next<--+--nix
                       |               +--mellanox
                       |
                       |
                       +--wingo next<--+--lwaftr
                                       +--multiproc

Pull Requests are first merged onto the subsystem branch that most
specifically matches their subject matter. For example, a change to
the PDF formatting of the manual would first be reviewed and accepted
by the maintainer of the `pdf-manual` branch. Later, that whole
subsystem branch is merged onto its "next-hop upstream" branch. For
example, the maintainer of the `documentation` branch would merge the
entire `pdf-manual` branch at regular intervals.

#### Registering a subsystem branch

XXX rewrite.

#### Being "the upstream" for Pull Requests

XXX rewrite.

#### Sending collected changes upstream to your next-hop

XXX rewrite.

#### Putting it all together

XXX rewrite.

