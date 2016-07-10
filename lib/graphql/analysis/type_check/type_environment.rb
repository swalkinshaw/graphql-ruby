module GraphQL
  module Analysis
    class TypeCheck
      class TypeEnvironment
        attr_reader :type_definitions, :field_definitions, :directive_definitions, :argument_definitions

        attr_reader :root_nodes
        attr_reader :fragment_nesting, :fragment_usages

        attr_reader :directives, :root_types, :schema
        def initialize(schema)
          @schema = schema
          @directives = GraphQL::Schema::DIRECTIVES.each_with_object({}) { |dir, m| m[dir.name] = dir }
          @root_types = {
            "query" => schema.query,
            "mutation" => schema.mutation,
            "subscription" => schema.subscription,
          }
          # Stacks on stacks
          @type_definitions = []
          @field_definitions = []
          @directive_definitions = []
          @argument_definitions = []
          # Other bookkeeping
          @root_nodes = []
          @fragment_usages = Hash.new { |h, k| h[k] = GraphQL::Analysis::TypeCheck::FragmentUsage.new(k) }
        end

        # This field is where the next fields will be looked up (unless it's a scalar).
        # @return [GraphQL::BaseType] The type which was returned by the previous field
        def current_type_definition
          @type_definitions.last
        end

        # @return [GraphQL::Field] The definition of currently-entered field
        def current_field_definition
          @field_definitions.last
        end

        # @return [GraphQL::Directive] The definition of the currently-entered directive
        def current_directive_definition
          @directive_definitions.last
        end

        # @return [GraphQL::Argument] The definition of the currently-entered argument
        def current_argument_definition
          @argument_definitions.last
        end

        # @return [GraphQL::Language::Nodes::OperationDefinition, GraphQL::Language::Nodes::FragmentDefinition] The starting point of the current traversal
        def current_root_node
          root_nodes.last
        end
      end
    end
  end
end
