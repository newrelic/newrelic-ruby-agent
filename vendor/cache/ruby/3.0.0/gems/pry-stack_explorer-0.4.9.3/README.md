pry-stack_explorer
===========

(C) John Mair (banisterfiend) 2011

_Walk the stack in a Pry session_

pry-stack_explorer is a plugin for the [Pry](http://pry.github.com)
REPL that enables the user to navigate the call-stack.

From the point a Pry session is started, the user can move up the stack
through parent frames, examine state, and even evaluate code.

Unlike `ruby-debug`, pry-stack_explorer incurs no runtime cost and
enables navigation right up the call-stack to the birth of the
program.

pry-stack_explorer is currently designed to work on **Rubinius and MRI
Ruby 1.9.2+ (including 1.9.3)**. Support for other Ruby versions and
implementations is planned for the future.

The `up`, `down`, `frame` and `show-stack` commands are provided. See
Pry's in-session help for more information on any of these commands.

**How to use:**

After installing `pry-stack_explorer`, just start Pry as normal (typically via a `binding.pry`), the stack_explorer plugin will be detected and used automatically.

* Install the [gem](https://rubygems.org/gems/pry-stack_explorer): `gem install pry-stack_explorer`
* Read the [documentation](http://rdoc.info/github/banister/pry-stack_explorer/master/file/README.md)
* See the [source code](http://github.com/pry/pry-stack_explorer)
* See the [wiki](https://github.com/pry/pry-stack_explorer/wiki) for in-depth usage information.

Example: Moving around between frames
--------

[![asciicast](https://asciinema.org/a/eJnrZNaUhTl12AVtnCG304d0V.png)](https://asciinema.org/a/eJnrZNaUhTl12AVtnCG304d0V)

Example: Modifying state in a caller
-------

[![asciicast](https://asciinema.org/a/0KtCL9HB1bP08wNHLfIeOMa8K.png)](https://asciinema.org/a/0KtCL9HB1bP08wNHLfIeOMa8K)

Output from above is `goodbye` as we changed the `x` local inside the `alpha` (caller) stack frame.

Limitations
-------------------------

* First release, so may have teething problems.
* Limited to Rubinius, and MRI 1.9.2+ at this stage.

Contact
-------

Problems or questions contact me at [github](http://github.com/banister)


License
-------

(The MIT License)

Copyright (c) 2011 John Mair (banisterfiend)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
