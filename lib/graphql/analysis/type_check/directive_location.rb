module GraphQL
  module Analysis
    class TypeCheck
      module DirectiveLocation
        include GraphQL::Language

        module_function

        def valid_location?(directive_defn, parent_ast_node)
          usage_location = location_for_node(parent_ast_node)
          directive_defn.locations.include?(usage_location)
        end

        def invalid_location_message(directive_defn, parent_ast_node)
          invalid_node_message = LOCATION_MESSAGE_NAMES[location_for_node(parent_ast_node)]
          valid_nodes_message = directive_defn.locations.map { |l| LOCATION_MESSAGE_NAMES[l] }.join(", ")
          "Invalid directive location: @#{directive_defn.name} is not allowed on #{invalid_node_message}, only: #{valid_nodes_message}."
        end

        private

        module_function

        def location_for_node(ast_node)
          if ast_node.is_a?(Nodes::OperationDefinition)
            NODE_TO_LOCATION[ast_node.operation_type.downcase]
          else
            NODE_TO_LOCATION[ast_node.class]
          end
        end


        LOCATION_MESSAGE_NAMES = {
          GraphQL::Directive::QUERY =>               "queries",
          GraphQL::Directive::MUTATION =>            "mutations",
          GraphQL::Directive::SUBSCRIPTION =>        "subscriptions",
          GraphQL::Directive::FIELD =>               "fields",
          GraphQL::Directive::FRAGMENT_DEFINITION => "fragment definitions",
          GraphQL::Directive::FRAGMENT_SPREAD =>     "fragment spreads",
          GraphQL::Directive::INLINE_FRAGMENT =>     "inline fragments",
        }

        NODE_TO_LOCATION = {
          "query" =>                    GraphQL::Directive::QUERY,
          "mutation" =>                 GraphQL::Directive::MUTATION,
          "subscription" =>             GraphQL::Directive::SUBSCRIPTION,
          Nodes::Field =>               GraphQL::Directive::FIELD,
          Nodes::InlineFragment =>      GraphQL::Directive::INLINE_FRAGMENT,
          Nodes::FragmentSpread =>      GraphQL::Directive::FRAGMENT_SPREAD,
          Nodes::FragmentDefinition =>  GraphQL::Directive::FRAGMENT_DEFINITION,
        }
      end
    end
  end
end
