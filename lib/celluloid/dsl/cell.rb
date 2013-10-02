module Celluloid
  class Cell
    module ClassMethods
      def self.extended(klass)
        klass.property :proxy_class,   :default => Celluloid::CellProxy

        klass.property :exclusive_methods, :multi => true
        klass.property :execute_block_on_receiver,
          :default => [:after, :every, :receive],
          :multi   => true

        klass.property :finalizer
        klass.property :exit_handler_name

        klass.send(:define_singleton_method, :trap_exit) do |*args|
          exit_handler_name(*args)
        end
      end

      # Create a new actor
      def new(*args, &block)
        proxy = Cell.new(allocate, behavior_options, actor_options).proxy
        proxy._send_(:initialize, *args, &block)
        proxy
      end
      alias_method :spawn, :new

      # Create a new actor and link to the current one
      def new_link(*args, &block)
        raise NotActorError, "can't link outside actor context" unless Celluloid.actor?

        proxy = Cell.new(allocate, behavior_options, actor_options).proxy
        Actor.link(proxy)
        proxy._send_(:initialize, *args, &block)
        proxy
      end
      alias_method :spawn_link, :new_link

      # Create a supervisor which ensures an instance of an actor will restart
      # an actor if it fails
      def supervise(*args, &block)
        Supervisor.supervise(self, *args, &block)
      end

      # Create a supervisor which ensures an instance of an actor will restart
      # an actor if it fails, and keep the actor registered under a given name
      def supervise_as(name, *args, &block)
        Supervisor.supervise_as(name, self, *args, &block)
      end

      # Create a new pool of workers. Accepts the following options:
      #
      # * size: how many workers to create. Default is worker per CPU core
      # * args: array of arguments to pass when creating a worker
      #
      def pool(options = {})
        PoolManager.new(self, options)
      end

      # Same as pool, but links to the pool manager
      def pool_link(options = {})
        PoolManager.new_link(self, options)
      end

      # Run an actor in the foreground
      def run(*args, &block)
        Actor.join(new(*args, &block))
      end

      # Configuration options for Cell#new
      def behavior_options
        {
          :proxy_class               => proxy_class,
          :exclusive_methods         => exclusive_methods,
          :exit_handler_name         => exit_handler_name,
          :finalizer                 => finalizer,
          :receiver_block_executions => execute_block_on_receiver,
        }
      end
    end

    # The following methods are available on both the Celluloid singleton and
    # directly inside of all classes that include Celluloid
    module SharedMethods
      # Raise an exception in sender context, but stay running
      def abort(cause)
        cause = case cause
                when String then RuntimeError.new(cause)
                when Exception then cause
                else raise TypeError, "Exception object/String expected, but #{cause.class} received"
                end
        raise AbortError.new(cause)
      end

      # Obtain the UUID of the current call chain
      def call_chain_id
        CallChain.current_id
      end

      # Handle async calls within an actor itself
      def async(meth = nil, *args, &block)
        Thread.current[:celluloid_actor].behavior_proxy.async meth, *args, &block
      end

      # Handle calls to future within an actor itself
      def future(meth = nil, *args, &block)
        Thread.current[:celluloid_actor].behavior_proxy.future meth, *args, &block
      end
    end

    # These are methods we don't want added to the Celluloid singleton but to be
    # defined on all classes that use Celluloid
    module InstanceMethods
      # Obtain the bare Ruby object the actor is wrapping. This is useful for
      # only a limited set of use cases like runtime metaprogramming. Interacting
      # directly with the bare object foregoes any kind of thread safety that
      # Celluloid would ordinarily provide you, and the object is guaranteed to
      # be shared with at least the actor thread. Tread carefully.
      #
      # Bare objects can be identified via #inspect output:
      #
      #     >> actor
      #      => #<Celluloid::Actor(Foo:0x3fefcb77c194)>
      #     >> actor.bare_object
      #      => #<WARNING: BARE CELLULOID OBJECT (Foo:0x3fefcb77c194)>
      #
      def bare_object; self; end
      alias_method :wrapped_object, :bare_object

      # Are we being invoked in a different thread from our owner?
      def leaked?
        @celluloid_owner != Thread.current[:celluloid_actor]
      end

      def tap
        yield current_actor
        current_actor
      end

      # Obtain the name of the current actor
      def name
        Actor.name
      end

      def inspect
        return "..." if Celluloid.detect_recursion

        str = "#<"

        if leaked?
          str << Celluloid::BARE_OBJECT_WARNING_MESSAGE
        else
          str << "Celluloid::CellProxy"
        end

        str << "(#{self.class}:0x#{object_id.to_s(16)})"
        str << " " unless instance_variables.empty?

        instance_variables.each do |ivar|
          next if ivar == Celluloid::OWNER_IVAR
          str << "#{ivar}=#{instance_variable_get(ivar).inspect} "
        end

        str.sub!(/\s$/, '>')
      end
    end
  end

  extend Cell::SharedMethods
end
