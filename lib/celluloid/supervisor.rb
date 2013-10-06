module Celluloid
  # Supervisors are actors that watch over other actors and restart them if
  # they crash
  class Supervisor
    class << self
      def supervise(klass, *args, &block)
        Celluloid.actor_system.supervise klass, *args, &block
      end

      def supervise_as(name, klass, *args, &block)
        Celluloid.actor_system.supervise_as name, klass, *args, &block
      end
    end
  end
end
