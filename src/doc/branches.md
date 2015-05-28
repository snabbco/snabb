## Snabb Switch development branches

The branches listed below are automatically synchronized with the
SnabbCo account on Github. Users typically get all of these branches
together by pulling from the main repository.

The current state of each branch with respect to master is visible here:

- https://github.com/SnabbCo/snabbswitch/branches/all

#### master

    BRANCH: master git://github.com/lukego/snabbswitch
    Stable branch suitable for development and deployment.
    
    - Always contains a stable release that is safe to pull from.
    - Updated monthly with new features and weekly with new bug fixes.
    - Changes are gated by the SnabbBot CI.
    
    Maintainer: Luke Gorrie <luke@snabb.co> and Max Rottenkolber <max@mr.gy>

#### next

    BRANCH: next git://github.com/lukego/snabbswitch
    Test and integration branch for new development.
    
    - Contains the changes for the next monthly feature release.
    - Merges Pull Requests that pass code review on Github.
    - Cycles between unstable and stable with the release schedule.

    Maintainer: Luke Gorrie <luke@snabb.co>

#### fixes

    BRANCH: fixes git://github.com/lukego/snabbswitch
    Test and integration branch for bug fixes.

    - Contains the changes for the next weekly maintenance release.
    - Merges Pull Requests that fix bugs in the latest release.
    - Generally stable.

    Maintainer: Luke Gorrie <luke@snabb.co>

#### documenation-fixups

    BRANCH: documentation-fixups git://github.com/eugeneia/snabbswitch
    Documentation fixes and improvements.
    
    Maintainer: Max Rottenkolber <max@mr.gy>

#### nfv
    
    BRANCH: nfv git://github.com/lukego/snabbswitch
    snabbnfv application development branch.
    
    Maintainer: Luke Gorrie <luke@snabb.co>

#### vpn
    
    BRANCH: vpn git://github.com/alexandergall/snabbswitch
    VPN application development branch.
    
    Maintainer: Alexander Gall <gall@switch.ch>

