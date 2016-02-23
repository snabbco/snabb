# Contributing Documentation in SnabbSwitch

## README.md, README.md.src and README(.inc)

The SnabbSwitch documentation is organized in README's spread across the
code base. If you commit changes you should look for the "nearest" README
file related to the modules you changed and update these. There are three
different kinds of README files:

* `README.md` — A portion of the SnabbSwitch manual, embedded by GitHub
  too. These are often (but not always) artifacts built from a `.src`
  file. Edit these if no `.src` is available (see below).
* `README.md.src` — A build recipe. If available, this is the one you
  must edit. These are formatted in [GitHub Flavored
  Markdown](https://help.github.com/articles/github-flavored-markdown/).
* `README(.inc)` — Plain text files included as the `--help` message of
  SnabbSwitch programs. These should be using only the ASCII character
  set to ensure compatibility with older terminals.

For instance if you had changed the API of `lib.protocol.ethernet` you'd
need to update the documentation in `lib/protocol/README.md.src`. It is
important that you use the correct header level (e.g. `##`, `###`,
...). Which level you are at can be seen in `doc/genbook.sh` (see
*Building A Standalone Documentation*).

Be sure to know who your target audience is. We recognize three different
groups:

* **Casual users:** Some programs are targeting *anyone* using Snabb
  Switch, make sure that their `--help` message (`README.inc`) does not
  require prior knowledge.
* **Power users:** Public APIs like `core.packet` or
  `lib.protocol.ethernet` are there for app designers to use. These
  should be well documented but may require knowledge of Lua and other
  parts of the Snabb Switch system.
* **Contributors:** Some documents (like the one you are reading now) are
  facing towards Snabb Switch contributors. They can be frequently
  updating and even contain open questions. We should ensure that these
  always reflect the current state of affairs.

### Building README.md Files

In order to recreate a `README.md` file from its `.src` you need to
`make` it. E.g. in case of our example above you would run:

```
make lib/protocol/README.md
```

You need to commit the resulting `README.md` (and possibly generated
diagram images, see *Including Diagrams*) alongside the updated
`README.md.src`.

### Including Diagrams

The main reason for the `README.md.src` to `README.md` step is that we
use a custom Markdown pre-processor to be able to embed ASCII diagrams in
our documentation. These ASCII diagrams will be rendered to pretty images
by [ditaa](http://ditaa.sourceforge.net/). In order to build `README.md`
files containing diagrams you will need a local installation of ditaa.

In order to use the diagram pre-processor you need to embed a ditaa
diagram in a block *indented with four space characters* lead by a
`DIAGRAM: <title>` header:

```
Normal paragraph...

    DIAGRAM: My Diagram
    +------+
    |A Box |<--With an arrow
    +------+
```

## Building A Standalone Documentation

In order to build a complete SnabbSwitch reference manual you can use
`make doc/snabbswitch.html`, `make doc/snabbswitch.epub` and `make
doc/snabbswitch.pdf` to build the HTML, ePUB and PDF versions
respectively. Alternatively, `make book` can be used to build all three
at once. For these tasks to work you will need a local installation of
[Pandoc](http://johnmacfarlane.net/pandoc/).

On Ubuntu you can install everything required to produce HTML, PDF and
epub versions with the following `apt-get` command:

```
sudo apt-get install pandoc pandoc-citeproc texlive-latex-recommended texlive-xetex texlive-luatex texlive-fonts-recommended texlive-latex-extra texlive-fonts-extra
```

You can change the organization and contents of the resulting file by
editing `doc/genbook.sh`, which is really just a primitive shell script
that concatenates the various `README.md` files we have.

# Stylistic Conventions

## Anatomy Of A Module Section

Every module has its own subsection in the SnabbSwitch manual, and all
these sections start off the same way:

```
### Protocol Header (lib.protocol.header)

The `lib.protocol.header` module contains stuff...
```

That is: The header contains the title of the module as well as its
*module path* in parentheses. The header is followed by a paragraph that
again names the module path and summarizes the module's purpose. This
introduction can be as detailed as the module required. Some modules are
obvious, some deserve along-form high-level introduction with examples.

If the module in question is an App, the introduction must be followed by
a diagram visually describing its inputs and outputs. E.g.:

```
    DIAGRAM: MyApp
              +------------+
              |            |
      in ---->*    MyApp   *----> out
              |            |
              +------------+
```

After the introduction follows a complete description of every *external*
symbol of the module. External means symbols that are part of the modules
public API. Every symbol gets its own special mention of the form:

```
— <Type> **<qualified.name>** <type-specific>

Paragraphs describing the symbol...
```

The `—` character is an *em dash*. Currently we use the following types:
Variable, Function, Method and Key. Variable and function names are
prefixed with their module name (separated from the symbol name by a
`.`). Methods are prefixed with their class name (separated from the
symbol name by a `:`). Functions and methods are followed by their
parameter lists. E.g.:

```
— Variable **module.some_constant**

— Function **module.some_function** *arg1*, *arg2*

— Method **class:some_method** *arg1*, *arg2*
```

If the module in question is an App, the symbol definitions must be
followed by a sub-section "Configuration" that elaborates on the App's
configuration parameter. E.g.

```
### Configuration

The `nd_light` app accepts a table as its configuration argument. The
following keys are defined:

— Key **local_mac**

*Required*. Local MAC address as a string or in binary representation.

— Key **retrans**

*Optional*. Number of neighbor solicitation retransmissions. Default is
unlimited retransmissions.
```

Each key's description must be preceded by either `*Required*` or
`*Optional*` to signify if its a required or an optional parameter. Each
key's description must also declare the expected type of the argument
value. Each optional key's description must end in a sentence defining
its default value.


## Markup Conventions

We markup source code literals in `code` font. E.g.: "The `foobar` module
is nice" and "`mod.fun(bla)` will make your dreams come true". Parameter
identifiers are marked up in *italic* font. E.g.: "`mod.foo` takes an
argument *bar*".

UNIX system calls should be mentioned like so: `usleep(3)`.

We markup specific *concepts* we introduce in italic font the first time
they are mentioned in order to signify to the reader that a specific
concept has a well defined meaning.

## Terminology And Normalized Language

The parameter names used in method and function description do not need
to reflect the names used in the source code. Instead use long,
descriptive names made out of full words when sensible.

Symbol definition are written in third person, e.g.: "Returns a number"
instead of "Return a number". When describing default behavior we say
"The default is..." instead of "Defaults to..." etc.

When in doubt, turn to the [Lua Reference Manual](http://www.lua.org/manual/5.1/)
for linguistic and stylistic reference.