How to build snabb-lwaftr:

Step 1: Fetch the sources
$ git clone https://github.com/Igalia/snabbswitch.githttps://github.com/Igalia/snabbswitch.git

Step 2: Check out the lwaftr development branch:
$ cd snabbswitch && git checkout lwaftr_nutmeg

Step 3: Buid
$ make
Note that this requires internet access to fetch the submodules.

This is all that is needed to build snabb-lwaftr. See bin/ for snabb-lwaftr, and
see README.first.md for instructions on how to use it.
