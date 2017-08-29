# frozen_string_literal: true

module GraphQL
  module ResolveDecorators
    def self.extended(klass)
      class << klass
        attr_accessor :decorated_resolvers
      end
    end

    def method_added(name)
      return unless @decorators

      decorators = @decorators.dup
      @decorators = nil
      @decorated_resolvers ||= Hash.new { |h,k| h[k] = [] }

      class << self; attr_accessor :decorated_resolvers; end

      decorators.each do |klass, args|
        # TODO: if `GraphQL::Object` had type information, we could pass it in here
        decorator = klass.respond_to?(:new) ? klass.new(*args) : klass
        @decorated_resolvers[name] << decorator
      end
    end

    def decorate(klass, *args)
      @decorators ||= []
      @decorators << [klass, args]
    end
  end
end
