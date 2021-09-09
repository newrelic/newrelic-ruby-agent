require 'hometown'

class Disposable
  def dispose
    # always be disposing
  end
end

# Watch Disposable and track calls to dispose
Hometown.watch_for_disposal(Disposable, :dispose)
Hometown.undisposed_report_at_exit

# Creating initial object
disposable = Disposable.new
Disposable.new
puts "Still there!"
puts "*" * 30
puts Hometown.undisposed_report
puts

# Dispose of one, and at_exit hook will show the results!
disposable.dispose
puts "Final undisposed report!"
puts "*" * 30
