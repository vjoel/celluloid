module Celluloid
  class Actor
    # Class methods added to classes which include Celluloid
    module ClassMethods
      def self.extended(klass)
        klass.property :mailbox_class, :default => Celluloid::Mailbox
        klass.property :task_class,    :default => Celluloid.task_class
        klass.property :mailbox_size

        klass.property :exclusive_actor, :default => false
      end

      # Configuration options for Actor#new
      def actor_options
        {
          :mailbox_class     => mailbox_class,
          :mailbox_size      => mailbox_size,
          :task_class        => task_class,
          :exclusive         => exclusive_actor,
        }
      end
    end

    module SharedMethods
      # Terminate this actor
      def terminate
        Thread.current[:celluloid_actor].behavior_proxy.terminate!
      end

      # Send a signal with the given name to all waiting methods
      def signal(name, value = nil)
        Thread.current[:celluloid_actor].signal name, value
      end

      # Wait for the given signal
      def wait(name)
        Thread.current[:celluloid_actor].wait name
      end

      # Obtain the current_actor
      def current_actor
        Actor.current
      end

      # Obtain the running tasks for this actor
      def tasks
        Thread.current[:celluloid_actor].tasks.to_a
      end

      # Obtain the Celluloid::Links for this actor
      def links
        Thread.current[:celluloid_actor].links
      end

      # Watch for exit events from another actor
      def monitor(actor)
        Actor.monitor(actor)
      end

      # Stop waiting for exit events from another actor
      def unmonitor(actor)
        Actor.unmonitor(actor)
      end

      # Link this actor to another, allowing it to crash or react to errors
      def link(actor)
        Actor.link(actor)
      end

      # Remove links to another actor
      def unlink(actor)
        Actor.unlink(actor)
      end

      # Are we monitoring another actor?
      def monitoring?(actor)
        Actor.monitoring?(actor)
      end

      # Is this actor linked to another?
      def linked_to?(actor)
        Actor.linked_to?(actor)
      end

      # Receive an asynchronous message via the actor protocol
      def receive(timeout = nil, &block)
        actor = Thread.current[:celluloid_actor]
        if actor
          actor.receive(timeout, &block)
        else
          Celluloid.mailbox.receive(timeout, &block)
        end
      end

      # Sleep letting the actor continue processing messages
      def sleep(interval)
        actor = Thread.current[:celluloid_actor]
        if actor
          actor.sleep(interval)
        else
          Kernel.sleep interval
        end
      end

      # Timeout on task suspension (eg Sync calls to other actors)
      def timeout(duration)
        Thread.current[:celluloid_actor].timeout(duration) do
          yield
        end
      end

      # Run given block in an exclusive mode: all synchronous calls block the whole
      # actor, not only current message processing.
      def exclusive(&block)
        Thread.current[:celluloid_task].exclusive(&block)
      end

      # Are we currently exclusive
      def exclusive?
        task = Thread.current[:celluloid_task]
        task && task.exclusive?
      end

      # Call a block after a given interval, returning a Celluloid::Timer object
      def after(interval, &block)
        Thread.current[:celluloid_actor].after(interval, &block)
      end

      # Call a block every given interval, returning a Celluloid::Timer object
      def every(interval, &block)
        Thread.current[:celluloid_actor].every(interval, &block)
      end

      # Perform a blocking or computationally intensive action inside an
      # asynchronous thread pool, allowing the sender to continue processing other
      # messages in its mailbox in the meantime
      def defer(&block)
        # This implementation relies on the present implementation of
        # Celluloid::Future, which uses a thread from InternalPool to run the block
        Future.new(&block).value
      end
    end
  end

  extend Actor::SharedMethods
end
