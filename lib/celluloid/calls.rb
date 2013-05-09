module Celluloid
  # Calls represent requests to an actor
  class Call
    attr_reader :method, :arguments, :block, :chain_id

    def initialize(responder, method, arguments, block, chain_id = Thread.current[:celluloid_chain_id])
      @responder = responder
      @method, @arguments = method, arguments
      if block
        if Celluloid.exclusive?
          # FIXME: nicer exception
          raise "Cannot execute blocks on sender in exclusive mode"
        end
        @block = BlockProxy.new(self, Celluloid.mailbox, block)
      else
        @block = nil
      end
      @chain_id = chain_id || Celluloid.uuid
    end

    def execute_block_on_receiver
      @block && @block.execution = :receiver
    end

    def dispatch(obj)
      Thread.current[:celluloid_chain_id] = @chain_id
      result = invoke(obj)
      respond SuccessResponse.new(self, result)
    rescue Exception => ex
      # Exceptions that occur during synchronous calls are reraised in the
      # context of the sender
      respond ErrorResponse.new(self, ex)

      # Aborting indicates a protocol error on the part of the sender
      # It should crash the sender, but the exception isn't reraised
      # Otherwise, it's a bug in this actor and should be reraised
      if ex.is_a?(AbortError)
        # TODO: only log for async
        Logger.debug("#{obj.class}: call `#@method` aborted!\n#{Logger.format_exception(ex.cause)}")
      else
        raise
      end
    ensure
      Thread.current[:celluloid_chain_id] = nil
    end

    def invoke(obj)
      _block = @block && @block.to_proc
      obj.public_send(@method, *@arguments, &_block)
    rescue NoMethodError => ex
      # Abort if the sender made a mistake
      raise AbortError.new(ex) unless obj.respond_to? @method

      # Otherwise something blew up. Crash this actor
      raise
    rescue ArgumentError => ex
      # Abort if the sender made a mistake
      begin
        arity = obj.method(@method).arity
      rescue NameError
        # In theory this shouldn't happen, but just in case
        raise AbortError.new(ex)
      end

      if arity >= 0
        raise AbortError.new(ex) if @arguments.size != arity
      elsif arity < -1
        mandatory_args = -arity - 1
        raise AbortError.new(ex) if arguments.size < mandatory_args
      end

      # Otherwise something blew up. Crash this actor
      raise
    end

    def respond(message)
      @responder.signal message if @responder
    end

    def resume(message)
      @responder.resume message if @responder
    end

    def cleanup
      exception = DeadActorError.new("attempted to call a dead actor")
      respond ErrorResponse.new(self, exception)
    end
  end

  # Synchronous calls wait for a response
  class ResumingResponder
    attr_reader :sender, :task

    def initialize(sender, task = Thread.current[:celluloid_task])
      @sender   = sender
      @task     = task
    end

    def signal(response)
      @sender << response
    end

    def resume(message)
      @task.resume message
    end

    def wait_for(call)
      @call = call
      Celluloid.suspend(:callwait, self).value
    end

    def wait
      loop do
        message = Celluloid.mailbox.receive do |msg|
          msg.respond_to?(:call) and msg.call == @call
        end

        if message.is_a?(SystemEvent)
          Thread.current[:celluloid_actor].handle_system_event(message)
        else
          # FIXME: add check for receiver block execution
          if message.respond_to?(:value)
            # FIXME: disable block execution if on :sender and (exclusive or outside of task)
            # probably now in Call
            break message
          else
            message.dispatch
          end
        end
      end
    end
  end

  class BlockCall
    def initialize(block_proxy, sender, arguments, task = Thread.current[:celluloid_task])
      @block_proxy = block_proxy
      @sender = sender
      @arguments = arguments
      @task = task
    end
    attr_reader :task

    def call
      @block_proxy.call
    end

    def dispatch
      response = @block_proxy.block.call(*@arguments)
      @sender << BlockResponse.new(self, response)
    end
  end

end
