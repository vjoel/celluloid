require 'rubygems'
require 'bundler/setup'
require 'celluloid/autostart'
require 'celluloid/rspec'
require 'coveralls'
Coveralls.wear!

logfile = File.open(File.expand_path("../../log/test.log", __FILE__), 'a')
logfile.sync = true
Celluloid.logger = Logger.new(logfile)
Celluloid.shutdown_timeout = 1

Dir['./spec/support/*.rb'].map {|f| require f }

require 'pry'

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

  config.around(:each) do |example|
    full_description = example.metadata[:full_description]
    Celluloid.logger.info "example: #{full_description.inspect}"
    ignored = [
    ]
    case full_description
    when *ignored
      Celluloid.logger.info "ignoring"
    else
      Celluloid.logger.info "cleaning up"
      Celluloid.shutdown
      Celluloid.boot
      Celluloid.logger.info "running"
      example.run
    end
  end
end

r, w = IO.pipe

Thread.new {
  thread = nil
  while r.read(1)
    if thread && thread.alive?
      $stderr.print "killing existing INFO thread\n"
      thread.kill
    end
    thread = Thread.new {
      Celluloid.dump
      binding.pry
    }
  end
}

trap("INFO") {
  $stderr.print "got INFO signal\n"
  w.write "."
}
