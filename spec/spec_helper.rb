require 'coveralls'
Coveralls.wear!

require 'rubygems'
require 'bundler/setup'
require 'celluloid/rspec'
require 'celluloid/probe'

logfile = File.open(File.expand_path("../../log/test.log", __FILE__), 'a')
logfile.sync = true

logger = Celluloid.logger = Logger.new(logfile)

Celluloid.shutdown_timeout = 1

Dir['./spec/support/*.rb'].map {|f| require f }

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

  config.before do
    Celluloid.logger = logger
    Thread.list.each do |thread|
      next if thread == Thread.current
      thread.kill
    end

    sleep 0.01
  end

  config.before actor_system: :global do
    Celluloid.boot
  end
end
