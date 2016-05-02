## Git workflow

How do you engage with the Snabb developer community? The answer depends on what you want to do:

- Use the software, ask questions, report bugs.
- Contribute fixes and improvements.
- Maintain a part of Snabb by reviewing and merging pull requests.
- Create a new application to develop together with the community.

### Using the software

The recommended way to download Snabb is with `git` directly
from from the `master` branch of the `snabbco` repository. This branch
always contains the latest release.

```
$ git checkout https://github.com/snabbco/snabb
$ cd snabb
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

The recommended way to contribute improvements to Snabb is with Github *pull requests*. You can do this by following the Github [Using pull requests](https://help.github.com/articles/using-pull-requests/) instructions. Here is a brief summary.

1. "Fork" your own copy of the [`snabbco/snabb`](https://github.com/snabbco/snabb) repository.
2. Push your proposed change to a branch on your repository.
3. Open a pull request from your branch. Choose the `master` branch of the `snabbco/snabb` repository as the target branch (this should be the default choice.)
4. Expect that within a few days a qualified maintainer will become the *Assignee* of your pull request and work with you to get the change merged. The maintainer may ask you some questions and even require some changes. Once they are satisfied they will merge the change onto their own branch and apply the label `merged` on the pull request. Then your work is done and the change is in the pipeline leading to release on the master branch.

Here are some tips for making your contribution smoothly:

- Use a dedicated "topic branch" for each feature or fix.
- Use the pull request text to explain why you are proposing the change.
- If the change is a work in progress then prefix the pull request title with `[wip]`. This signals that you intened to push more commits before the change is complete.
- If the change is a rough draft that you want early feedback on then prefix the pull request name with `[sketch]`. This signals that you may throw the branch away and start over on a new one.

### Becoming a maintainer

Snabb maintainers are the people who review and merge the pull
requests on Github. Each maintainer takes care of one or more specific
part of Snabb. These parts are called *subsystems*.

Each subsystem has a dedicated branch and these branches are organized
as a tree:

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

Pull requests are merged onto the most specifically relevant branch to
begin with. Later, whole child branches are merged "upstream" onto
their parent branches. This way once a change has been merged onto any
branch in the tree it will naturally flow upstream to the `master`
branch for release.

For example, a change to the LaTeX template for the PDF edition of the
manual would first be reviewed and merged by the maintainer of the
`pdf-manual` branch. The change would then be included in successive
merges upstream to branches `documentation`, `max-next`, `next`, and
finally `master`. Each of these steps provides the opportunity for a
maintainer to improve some aspect of the change before release.

#### Registering a subsystem branch

So you are interested in becoming a Snabb maintainer. Great!
The other maintainers are looking forward to working with you and will
be more than happy to help you learn the ropes. You can learn
everything you need to know on the job: no special qualifications are
required.

The first step to becoming a maintainer is to decide which kind of
pull requests you want to be responsible for. For example you could be
responsible for changes to the Makefiles, or the Intel 10G device
driver, or the `packetblaster` load generator program, or any other
part of the software that is easy to identify when assigning pull
requests. You do not have to be an expert in this area already: it is
enough that you are committed to learning about it and being
responsive to contributors.

Once you have worked out which part you want to maintain then you can
propose this to the community by sending a pull request that registers
your new branch in the file `src/doc/branches.md`. This pull request
will be the vehicle for talking with the other maintainers about where
to fit your new branch into the tree.

The moment this pull request is merged onto the `next` branch then you
are officially a Snabb maintainer. (Congratulations in advance!)

#### Being the assigned maintainer for pull requests

Now that you are a registered maintainer you will watch Github for new
pull requests and mark yourself as the *Assignee* for changes that
match your area of responsibility. You are the reviewer for these
changes and you decide when to accept them from the contributor.

Here is the basic criteria for merging a pull request:

- Does the change improve Snabb? It does not have to be perfect
  but it should clearly have a net-positive impact.
- Will the next-hop upstream maintainer agree? If not then getting
  your branch merged upstream may require you to make some
  improvements or even revert the change.

Beyond this the most important thing is to communicate with the
contributor to make sure they understand exactly what they have to do
in order for their change to be merged. Contributors can easily be
overwhelmed by comments on pull requests, often from many different
people, so the assigned maintainer needs to explain very clearly what
the requirements are for merge. (Contributors will be frustrated if
they do not know what feedback they are required to act on, especially
when receiving conflicting ideas from different people, so you need to
decide for yourself what is required and clearly explain this.)

#### Sending your accepted changes upstream

Once you have merged one or more changes onto your branch the next
step is to open a pull request asking the next upstream maintainer to
merge your whole branch. This way all of the changes you merged will
make their way upstream step-by-step and ultimately be released by
being merged onto the `master` branch.

This is where it comes in handy that the branches are organized in the
tree structure shown above. When your subsystem branch contains
changes that are ready to merge further upstream then you would open a
pull request to the parent branch in the tree. For example, if you are
the maintainer of the `pdf-manual` branch and you have changes ready
for integration then you would open a pull request to the
`documentation` parent branch.

How do you decide when to open this pull request? This is a latency
verses throughput trade-off that you need to agree on with the
upstream maintainer. On the one hand it is important for changes to
move upstream quickly when they are beneficial to users or likely to
conflict with other work, on the other hand you may overwhelm the
upstream maintainer if you open pull requests too often. One
suggestion to use as a starting point would be to open a pull request
once or twice per week whenever your branch contains new changes.

The upstream branch maintainer will be responsible for considering the
broader impact of the changes on your branch. They may need to resolve
conflicts with other changes that they have merged, or want to ask for
input from people who will be affected by the changes, or they may
want to refactor the changes together with some other related code.
They will tell you if they need your help with this and if they have
ideas for how you can make their merging work easier in the future.

