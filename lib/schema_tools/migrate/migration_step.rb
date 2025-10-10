module SchemaTools
  class MigrationStep
    attr_reader :name, :before_actions, :run_actions, :after_actions

    def initialize(name:, run:)
      @name = name
      @before_actions = []
      @run_actions = [run]
      @after_actions = []
      add_default_logging
    end

    def add_before(action)
      @before_actions << action
      self
    end

    def add_after(action)
      @after_actions << action
      self
    end

    def execute(logger)
      @before_actions.each { |action| action.call(logger) }
      @run_actions.each { |action| action.call(logger) }
      @after_actions.each { |action| action.call(logger) }
    end

    private

    def add_default_logging
      @before_actions << ->(logger) { logger.log("#{@name} (starting)") }
      @after_actions << ->(logger) { logger.log("#{@name} (completed)") }
    end
  end
end