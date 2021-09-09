require 'hometown'

# Start watching Array instantiations
Hometown.watch(Array)

# Output the trace for a specific Array's creation
p Hometown.for(Array.new)
