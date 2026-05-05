# frozen_string_literal: true

module Relaton
  # Workers poll.
  class WorkersPool
    def initialize(workers = 2, &)
      # num_workers = workers < 2 ? 2 : workers
      @queue = SizedQueue.new(workers * 2)
      @threads = Array.new workers do
        Thread.new do
          while item = @queue.pop; yield(item) end
        end
      end
    end

    def <<(item)
      @queue << item
      self
    end
  end
end
