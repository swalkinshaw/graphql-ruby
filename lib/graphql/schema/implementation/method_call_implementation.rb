# frozen_string_literal: true
module GraphQL
  class Schema
    class Implementation
      # Turn the GraphQL field resolution into a Ruby method call
      class MethodCallImplementation
        def initialize(method:, graphql_arguments:, special_arguments:)
          @method_name = method
          @graphql_arguments = graphql_arguments
          @special_arguments = special_arguments
          @no_arguments = graphql_arguments.length == 0 && special_arguments.length == 0
        end

        def call(proxy, args, ctx)
          method_args = {}
          @graphql_arguments.each { |a| method_args[a] = args[a] }
          @special_arguments.each do |arg|
            case arg
            when :context
              method_args[:context] = ctx
            when :irep_node
              method_args[:irep_node] = ctx.irep_node
            when :ast_node
              method_args[:ast_node] = ctx.ast_node
            end
          end

          if proxy.class.respond_to?(:decorated_resolvers)
            if decorators = proxy.class.decorated_resolvers.to_h[@method_name.to_sym]
              decorators.each do |decorator|
                if @no_arguments
                  decorator.call(proxy.object, proxy.context)
                else
                  decorator.call(proxy.object, proxy.context, **method_args)
                end
              end
            end
          end

          if @no_arguments
            proxy.public_send(@method_name)
          else
            proxy.public_send(@method_name, **method_args)
          end
        end
      end
    end
  end
end
