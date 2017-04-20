## Snabb development branches

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

#### documenation

    BRANCH: documentation git://github.com/eugeneia/snabbswitch
    Editing and integration branch for documentation changes.

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

#### luajit

    BRANCH: luajit git://github.com/snabbco/luajit
    LuaJIT v2.1 updates branch.

    - Pulls changes from LuaJIT v2.1 upstream.
    - Pulls special features & fixes needed by Snabb.
    - Resolves conflicts due to upstream rebases of PRs.

    Maintainer: Luke Gorrie <luke@snabb.co>
    Next hop: next

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

#### pdf-manual

    BRANCH: pdf-manual git://github.com/lukego/snabbswitch
    Maintenance branch for the PDF edition of the Snabb manual.

    - Ensures that the PDF manual builds and looks good.
    - Supports documentation revision and integration efforts.
    - Feeds upstream to documentation-fixes.

    Maintainer: Luke Gorrie <luke@snabb.co>

#### ipsec

    BRANCH: ipsec git://github.com/eugeneia/snabbswitch
    IPsec library development branch.

    Maintainer: Max Rottenkolber <max@mr.gy>

### nix

    BRANCH: nix git://github.com/domenkozar/snabbswitch
    Nix expressions for building/testing Snabb.

    - Contains changes proposed to be merged into next
    - Contains infrastructure changes built by https://hydra.snabb.co
    - Feeds upstream to kbara-next.

    Maintainer: Domen Kožar <domen@dev.si>

#### snabbwall

    BRANCH: snabbwall git://github.com/Igalia/snabb
    Snabbwall (layer 7 firewall) application development branch.

    - See snabbwall.org for more info

    Maintainer: Collectively maintained by Snabbwall application developers.
    Next hop: kbara-next

#### aarch64

    BRANCH: aarch64 git://github.com/jialiu02/snabb
    Development branch for ARM aarch64 platform.

    Maintainer: Jianbo Liu <jianbo.liu@linaro.org>

