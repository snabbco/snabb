## Git workflow

Snabb Switch is developed on Github using the distributed workflow
that was pioneered by the Linux kernel.

The latest Snabb Switch release can always be found on the `master`
branch of the Github `SnabbCo/snabbswitch` repository.

### Being a contributor

So you have decided to contribute an improvement to Snabb Switch. Great! This is what to do:

1. Create your own "fork" of Snabb Switch on Github. Do this by clicking the "Fork" button on the Github UI. (You only have to do this the first time you are making a change.)
2. Create a topic branch based on `master`. Example: `git branch -b my-feature master`.
3. Develop your feature and push your branch to your Github fork. Example: `emacs`, `git commit`, `git push`.
4. Open a Github Pull Request from your branch to the SnabbCo/snabbswitch master branch. Clicking the Pull Request button on Github should do the right thing.

Once your Pull Request is open you can wait a short while, usually a day or two, for a maintainer to engage with you and take responsibility for merging your change "upstream".

Tips for making your contribution smoothly:

- Explain why your change is a good idea using the text area of the Pull Request.
- Don't rebase your branch after the pull request is open; make corrections by pushing new commits.
- If your change is a work in progress then prefix the Pull Request name with `[wip]`.
- If your change is a rough draft for early feedback then prefix the Pull Request name with `[sketch]`.

### Being a maintainer

So you have decided to help with the upstream maintenance of Snabb
Switch. Fantastic! You can do this by creating and maintaining a
"subsystem branch" where you take responsibility for reviewing and
merging some of the Pull Requests submitted to Snabb Switch.

#### Registering a subsystem branch

The first step is to create and register your subsystem branch:

1. Pick your technical area of interest. What kind of changes will you be responsible for reviewing and merging? Try to pick an area that is easy to identify, for example "the packetblaster program", "the Intel I350 device driver", or "the Git Workflow chapter of the manual".
2. Create a branch with a suitable name on your Github fork, for example `packetblaster`, `i350`, or `git-workflow`. This is where you will merge relevant changes.
3. Describe this branch in the file `src/doc/branches.md` and open a Github Pull Request. This will kick off two discussions: how to clearly identify the changes that you are responsible for, and to which "next-hop" upstream branch you should send the changes that you have accepted by merging.

Once those details are worked out and your branch is registered then
you are a Snabb Switch maintainer. Congratulations!

#### Being "the upstream" for Pull Requests

Now as a maintainer your job is to watch for Pull Requests opened to
the Github repository and act as the responsible person (the
"upstream") when your branch most specifically matches a change.

Here is how to be the upstream for a change:

1. Set yourself as the *Assignee* of the Pull Request. This clearly signals to everybody that you are the one responsible for reviewing and merging the change.
2. Review the submitted changes:
    1. Does it all look good? If so then merge the changes onto your branch and add the label `merged` to the Pull Request.
    2. Do you see some serious problems? Tell the contributor exactly what they need to change in order for you to merge the changes.
    3. Do you see minor ways that the change could be improved? Suggest those and ask the contributor whether they want to do that before you merge the change.
    4. Is there somebody else who should also review the code? If so then ask them for help with a @mention.
    5. Do you see an obvious thing to fix that requires no discussion? You can simply do that yourself as part of your merge commit.
3. Manage the discussion. Everybody on Github is able to make comments on Pull Requests, often many people do, but as the upstream assignee you are the one who says what is necessary. Contributors can easily be overwhelmed by feedback from many sources so it is important for the upstream assignee to clearly explain what actions they have to take in order for their changes to be merged.

#### Sending collected changes upstream to your next-hop

So you merge some good changes onto your subsystem branch. What next?

The next step is to open a Pull Request from your specific subsystem
branch to the more general "next hop" upstream branch. This is your
way to say "hey, I have collected some good changes here, please merge
them!"

The upstreaming process is the same one described above, but now you
are the one submitting the changes and expecting clear feedback on
what actions you need to take for them to be accepted.

#### Putting it all together

Here is a complete example of how this can all fit together:

You decide that you want to be the maintainer of the Intel I350
ethernet driver. You create a branch called `i350` and open a Pull
Request to describe this branch in `src/doc/branches.md`. The other
maintainers are happy that you want to join in and gladly agree to
refer Pull Requests concerned the Intel I350 driver to you. You agree
that once you have good changes on your `i350` branch you will open a
Pull Request to the more general `drivers` branch as your "next hop"
upstream.

People in the community start contributing improvements to the I350
driver. You set yourself as the *Assignee* to these Pull Requests and
engage with the contributors to get the changes in good shape. You
merge the good changes onto your `i350` branch and periodically open a
Pull Request to the `drivers` branch to send this code upstream. The
`drivers` branch will in turn be merged to its next hop upstream and
step-by-step the changes will make their way towards release on the
`master` branch.

The time scales involved are not written in stone but it is important
to find a rhythm that is comfortable for everybody involved. You might
aim to set yourself as the *Assignee* for relevant Pull Requests
within one day, to provide a review within a few days, and to send
Pull Requests to your next-hop upstream once or twice per week when
you have changes.

#### Don't be shy!

Becoming a Snabb Switch maintainer is a great service to the community
and you can learn all the skills that you need "on the job." If you are
tempted to give it a try then please do!

The more subsystem maintainers we have the more capacity we have to
incorporate improvements into Snabb Switch. The Linux kernel has
more than one thousand registered subsystems. The sky is the limit!

