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

#### kbara-next

    BRANCH: kbara-next git://github.com/kbara/snabbswitch
    Test and integration branch for maintenance & development.

    - Contains changes proposed to be merged into next.
    - Merges Pull Requests that pass code review on GitHub.
    - Integration branch for code vetted by Kat

    Maintainer: Katerina Barone-Adesi <kbarone@igalia.com>

#### max-next

    BRANCH: max-next git://github.com/eugeneia/snabbswitch
    Test and integration branch for maintenance & development.

    - Contains changes proposed to be merged into next.
    - Merges Pull Requests that pass code review on GitHub.
    - Integration branch for code vetted by Max

    Maintainer: Max Rottenkolber <max@mr.gy>

#### wingo-next

    BRANCH: wingo-next git://github.com/wingo/snabbswitch
    Test and integration branch for maintenance & development.

    - Contains changes proposed to be merged into next.
    - Merges Pull Requests that pass code review on GitHub.
    - Integration branch for code vetted by Andy

    Maintainer: Andy Wingo <wingo@igalia.com>

#### kbara-next

    BRANCH: kbara-next git://github.com/kbara/snabbswitch
    Test and integration branch for maintenance & development.

    - Contains changes proposed to be merged into next.
    - Merges Pull Requests that pass code review on GitHub.
    - Integration branch for code vetted by Katerina

    Maintainer: Katerina Barone-Adesi <kbarone@igalia.com>

#### documenation-fixups

    BRANCH: documentation-fixups git://github.com/eugeneia/snabbswitch
    Documentation fixes and improvements.

    Maintainer: Max Rottenkolber <max@mr.gy>

#### vpn

    BRANCH: vpn git://github.com/alexandergall/snabbswitch
    VPN application development branch.

    Maintainer: Alexander Gall <gall@switch.ch>

#### lwaftr

    BRANCH: lwaftr git://github.com/Igalia/snabbswitch
    Lightweight 4-over-6 AFTR application development branch.

    Maintainer: Collectively maintained by lwAFTR application developers.
    Next hop: kbara-next

#### mellanox

    BRANCH: mellanox git://github.com/lukego/snabbswitch
    Mellanox ConnectX device driver development.

    Maintainer: Luke Gorrie <luke@snabb.co>

#### multiproc

    BRANCH: multiproc git://github.com/lukego/snabbswitch
    Multiple process parallel processing development branch.

    Maintainer: Luke Gorrie <luke@snabb.co>

#### lisper

    BRANCH: lisper git://github.com/capr/snabbswitch
    LISPER program for creating L2 networks over IPv6 networks.

    Maintainer: Cosmin Apreutesei <cosmin.apreutesei@gmail.com>
