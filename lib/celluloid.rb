require 'logger'
require 'thread'
require 'timeout'
require 'set'

module Celluloid
  VERSION = '0.16.0.pre'
  Error = Class.new StandardError

  # Warning message added to Celluloid objects accessed outside their actors
  BARE_OBJECT_WARNING_MESSAGE = "WARNING: BARE CELLULOID OBJECT "

  class << self
    attr_accessor :internal_pool    # Internal thread pool
    attr_accessor :logger           # Thread-safe logger class
    attr_accessor :task_class       # Default task type to use
    attr_accessor :shutdown_timeout # How long actors have to terminate

    def included(klass)
      klass.send :extend,  Properties
      klass.send :extend,  ClassMethods
      klass.send :extend,  Actor::ClassMethods
      klass.send :extend,  Cell::ClassMethods
      klass.send :include, Actor::SharedMethods
      klass.send :include, Cell::SharedMethods
      klass.send :include, Cell::InstanceMethods

      # TODO: split this API between Actor and Cell
      klass.send(:define_singleton_method, :exclusive) do |*args|
        if args.any?
          exclusive_methods(*exclusive_methods, *args)
        else
          exclusive_actor true
        end
      end
    end

    # Are we currently inside of an actor?
    def actor?
      !!Thread.current[:celluloid_actor]
    end

    # Retrieve the mailbox for the current thread or lazily initialize it
    def mailbox
      Thread.current[:celluloid_mailbox] ||= Celluloid::Mailbox.new
    end

    # Generate a Universally Unique Identifier
    def uuid
      UUID.generate
    end

    # Obtain the number of CPUs in the system
    def cores
     CPUCounter.cores
    end
    alias_method :cpus, :cores
    alias_method :ncpus, :cores

    # Perform a stack dump of all actors to the given output object
    def stack_dump(output = STDERR)
      Celluloid::StackDump.new.dump(output)
    end
    alias_method :dump, :stack_dump

    # Detect if a particular call is recursing through multiple actors
    def detect_recursion
      actor = Thread.current[:celluloid_actor]
      return unless actor

      task = Thread.current[:celluloid_task]
      return unless task

      chain_id = CallChain.current_id
      actor.tasks.to_a.any? { |t| t != task && t.chain_id == chain_id }
    end

    # Define an exception handler for actor crashes
    def exception_handler(&block)
      Logger.exception_handler(&block)
    end

    def suspend(status, waiter)
      task = Thread.current[:celluloid_task]
      if task && !Celluloid.exclusive?
        waiter.before_suspend(task) if waiter.respond_to?(:before_suspend)
        Task.suspend(status)
      else
        waiter.wait
      end
    end

    def boot
      init
      start
    end

    def init
      self.internal_pool = InternalPool.new
    end

    # Launch default services
    # FIXME: We should set up the supervision hierarchy here
    def start
      Celluloid::Notifications::Fanout.supervise_as :notifications_fanout
      Celluloid::IncidentReporter.supervise_as :default_incident_reporter, STDERR
    end

    def register_shutdown
      return if @shutdown_registered
      # Terminate all actors at exit
      at_exit do
        if defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby" && RUBY_VERSION >= "1.9"
          # workaround for MRI bug losing exit status in at_exit block
          # http://bugs.ruby-lang.org/issues/5218
          exit_status = $!.status if $!.is_a?(SystemExit)
          Celluloid.shutdown
          exit exit_status if exit_status
        else
          Celluloid.shutdown
        end
      end
      @shutdown_registered = true
    end

    # Shut down all running actors
    def shutdown
      actors = Actor.all

      Timeout.timeout(shutdown_timeout) do
        internal_pool.shutdown

        Logger.debug "Terminating #{actors.size} #{(actors.size > 1) ? 'actors' : 'actor'}..." if actors.size > 0

        # Attempt to shut down the supervision tree, if available
        Supervisor.root.terminate if Supervisor.root

        # Actors cannot self-terminate, you must do it for them
        actors.each do |actor|
          begin
            actor.terminate!
          rescue DeadActorError
          end
        end

        actors.each do |actor|
          begin
            Actor.join(actor)
          rescue DeadActorError
          end
        end
      end
    rescue Timeout::Error
      Logger.error("Couldn't cleanly terminate all actors in #{shutdown_timeout} seconds!")
      actors.each do |actor|
        begin
          Actor.kill(actor)
        rescue DeadActorError, MailboxDead
        end
      end
    ensure
      internal_pool.kill
    end

    def version
      VERSION
    end
  end

  # Class methods added to classes which include Celluloid
  module ClassMethods
    def ===(other)
      other.kind_of? self
    end
  end
end

if defined?(JRUBY_VERSION) && JRUBY_VERSION == "1.7.3"
  raise "Celluloid is broken on JRuby 1.7.3. Please upgrade to 1.7.4+"
end

require 'celluloid/calls'
require 'celluloid/call_chain'
require 'celluloid/condition'
require 'celluloid/thread'
require 'celluloid/core_ext'
require 'celluloid/cpu_counter'
require 'celluloid/fiber'
require 'celluloid/fsm'
require 'celluloid/internal_pool'
require 'celluloid/links'
require 'celluloid/logger'
require 'celluloid/mailbox'
require 'celluloid/evented_mailbox'
require 'celluloid/method'
require 'celluloid/properties'
require 'celluloid/handlers'
require 'celluloid/receivers'
require 'celluloid/registry'
require 'celluloid/responses'
require 'celluloid/signals'
require 'celluloid/stack_dump'
require 'celluloid/system_events'
require 'celluloid/tasks'
require 'celluloid/task_set'
require 'celluloid/thread_handle'
require 'celluloid/uuid'

require 'celluloid/proxies/abstract_proxy'
require 'celluloid/proxies/sync_proxy'
require 'celluloid/proxies/cell_proxy'
require 'celluloid/proxies/actor_proxy'
require 'celluloid/proxies/async_proxy'
require 'celluloid/proxies/future_proxy'
require 'celluloid/proxies/block_proxy'

require 'celluloid/actor'
require 'celluloid/cell'
require 'celluloid/dsl/actor'
require 'celluloid/dsl/cell'
require 'celluloid/future'
require 'celluloid/pool_manager'
require 'celluloid/supervision_group'
require 'celluloid/supervisor'
require 'celluloid/notifications'
require 'celluloid/logging'

require 'celluloid/legacy' unless defined?(CELLULOID_FUTURE)

$CELLULOID_MONITORING = false

# Configure default systemwide settings
Celluloid.task_class = Celluloid::TaskFiber
Celluloid.logger     = Logger.new(STDERR)
Celluloid.shutdown_timeout = 10
Celluloid.register_shutdown
Celluloid.init
