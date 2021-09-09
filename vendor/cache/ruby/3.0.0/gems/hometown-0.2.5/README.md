# Hometown
[![Gem Version](https://badge.fury.io/rb/hometown.png)](http://badge.fury.io/rb/hometown)
[![Build Status](https://api.travis-ci.org/jasonrclark/hometown.png)](https://travis-ci.org/jasonrclark/hometown)
[![Code Climate](https://codeclimate.com/github/jasonrclark/hometown.png)](https://codeclimate.com/github/jasonrclark/hometown)
[![Coverage Status](https://coveralls.io/repos/jasonrclark/hometown/badge.png?branch=master)](https://coveralls.io/r/jasonrclark/hometown)

Track object creation to stamp out pesky leaks.

## Requirements
Tests are run against MRI 1.9.3 through 2.1.2, JRuby 1.7 (latest) and head, and
Rubinius 2.x (latest).

Ruby 1.8.7 and REE are not supported. Sorry retro-Ruby fans!

## Installation

    $ gem install hometown

## Usage

### Object Creation
Hometown's primary use is finding where objects were instantiated.  In
sufficiently complicated applications, this can be a real help debugging issues
like testing side-effects (i.e. where did that thread get started from?)

To find where an object was created, `Hometown.watch` its class, and then ask
`Hometown.for` on an instance of that class to see where it started out.

```
# examples/example.rb
require 'hometown'

# Start watching Array instantiations
Hometown.watch(Array)

# Output the trace for a specific Array's creation
p Hometown.for(Array.new)


$ ruby examples/example.rb

#<Hometown::Trace:0x007fcd9c95ca10
  @traced_class=Array,
  @backtrace=["script:4:in `<main>'"]>
```


### Resource Disposal
Though not hugely common in the Ruby world, some libraries (such as [swt]
(https://github.com/danlucraft/swt)) require you to explicitly dispose of
objects you create. Most often this happens when it's an interface library to
some other system that holds OS resources until you release them back. Leaking
is a bad idea.

Hometown can help track down these leaks. To watch a class of objects to ensure
created instances are disposed, call `Hometown.watch_for_disposal` on the
class. `Hometown.undisposed` returns you objects indicating--with stack traces
--all the locations where an object was created but not released.
`Hometown.undisposed_report` will give a formatted output of the undisposed
objects.

```
# dispose.rb
require 'hometown'

class Disposable
  def dispose
    # always be disposing
  end
end

# Watch Disposable and track calls to dispose
Hometown.watch_for_disposal(Disposable, :dispose)

# Creating initial object
disposable = Disposable.new
puts "Still there!"
p Hometown.undisposed
puts

# All done!
disposable.dispose
puts "Properly disposed"
puts Hometown.undisposed_report


$ ruby examples/dispose.rb

Still there!
{ #<Hometown::Trace:0x007f9aa516ec88 ...> => 1 }

Properly disposed!
Undisposed Resources:
[Disposable] => 0
	examples/dispose.rb:13:in `<main>'

Undiposed Totals:
[Disposable] => 0
```

## Contributing

1. Fork it ( https://github.com/jasonrclark/hometown/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
