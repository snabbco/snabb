This directory contains scripts that impelement *SnabbBot*. The
`snabb_bot.sh` script will fetch the *pull requests* of a repository,
and--unless done before--execute *tasks* in their *cloned trees* with
their respective *head* checked out. Each *task* will be executed with
two arguments--the base and head commit hashes of the pull request. The
output of *tasks* is posted to GitHub in form of a GitHub *commit
status* for the commit in question.

See `bot_conf.sh.example` for environment variables required by
`snabb_bot.sh`.

`snabb_bot.sh` depends on [jq](http://stedolan.github.io/jq/).
