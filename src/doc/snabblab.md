Servers devoted to the Snabb project and usable by all known developers.

Want to be a known developer? Sure! Just edit the [user account list](https://github.com/snabblab/snabblab-nixos/blob/master/modules/users.nix) with your user and send a pull request. No fuss.

## Guidelines

- Feel at home. These servers are here for you to play with and enjoy.
- Please run Snabb processes like this: `sudo lock ./snabb ...`. The `lock` command will automatically wait if somebody else is running a Snabb process on the same machine and that helps us avoid conflicts for access to hardware resources.
- Tell `luke@snabb.co` your email address(es) to get an invitation to the [Lab Slack](http://snabb.slack.com/).
- Don't keep precious data on the servers. We might want to reinstall them at short notice.

## Servers

Name        | Purpose                                           | SSH                     | Xeon model   | NICs
------------|---------------------------------------------------|-------------------------| --------     | ------------------------------------------------
lugano-1    | General use                                       | lugano-1.snabb.co       | E3 1650v3    | 2 x 10G (82599), 4 x 10G (X710), 2 x 40G (XL710)
lugano-2    | General use                                       | lugano-2.snabb.co       | E3 1650v3    | 2 x 10G (82599), 4 x 10G (X710), 2 x 40G (XL710)
lugano-3    | General use                                       | lugano-3.snabb.co       | E3 1650v3    | 2 x 10G (82599), 2 x 100G (ConnectX-4)
lugano-4    | General use                                       | lugano-4.snabb.co       | E3 1650v3    | 2 x 10G (82599), 2 x 100G (ConnectX-4)
davos       | Continuous Integration tests & driver development | lab1.snabb.co port 2000 | 2x E5 2603   | Diverse 10G/40G: Intel, SolarFlare, Mellanox, Chelsio, Broadcom. Installed upon request.
grindelwald | Snabb NFV testing                                 | lab1.snabb.co port 2010 | 2x E5 2697v2 | 12 x 10G (Intel 82599)
interlaken  | Haswell/AVX2 testing                              | lab1.snabb.co port 2030 | 2x E5 2620v3 | 12 x 10G (Intel 82599)

## Get started

You are welcome to play, test, and develop on the `lugano-1` .. `lugano-4` servers. Once your account is added you can connect like this:

    $ ssh user@lugano-1.snabb.co

and check the PCI devices and their addresses with `lspci`.

Certain cards (82599 and ConnectX-4) are cabled to themselves. That is, dual-port cards have their ports connected to each other. Certain other cards (X710/XL710) are currently not cabled. If you have special cabling needs then please open an issue on the [snabblab-nixos](https://github.com/snabblab/snabblab-nixos).

## Using the lab

All servers run the latest stable version of [NixOS Linux distribution](http://nixos.org/nixos/about.html).

To quickly install a package:

    $ nox <search string>

For other operations such as uninstalling a package, refer to `man nix-env`.

## Questions

If you have any questions or trouble, ask on [the #lab channel](https://snabb.slack.com/messages/lab/) or [open an issue](https://github.com/snabblab/snabblab-nixos).

## Thanks

We are grateful to [Silicom](http://www.silicom-usa.com/) for their sponsorship in the form of discounted network cards for `chur` and to [Netgate](http://www.netgate.com/) for giving us `jura`. Thanks gang!
