require "graphql/analysis/type_check/directive_location"
require "graphql/analysis/type_check/fragment_usage"
require "graphql/analysis/type_check/type_condition"
require "graphql/analysis/type_check/type_environment"

module GraphQL
  module Analysis
    # Check each node against the type environment.
    # Some checks will modify the environment if they're successful.
    #
    # After visiting those nodes, tear down the type environment
    class TypeCheck
      include GraphQL::Language

      # TODO: implement these to allow continuing validation,
      # then you won't have to skip child fields
      NO_TYPE  = nil
      NO_FIELD = nil

      def initialize(query, type_env)
        @errors = []
      end

      # A {GraphQL::Analysis.reduce_query}-compliant call method for adding to the type environment
      def call(memo, enter_or_leave, type_env, ast_node, prev_ast_node)
         enter_or_leave == :enter && enter_node(type_env, ast_node, prev_ast_node)
         type_env
      end

      def final_value(type_env)
        @errors + FragmentUsage.build_errors(type_env.fragment_usages, type_env.schema)
      end

      private

      def enter_node(type_env, ast_node, parent_ast_node)
        case ast_node
        when Nodes::InlineFragment
          object_type_defn = if ast_node.type
            type_env.schema.types.fetch(ast_node.type, nil)
          else
            type_env.type_definitions.last
          end
          if object_type_defn.nil?
            push_error("Inline fragment on undefined type: #{ast_node.type}", ast_node)
          else
            object_type_defn = object_type_defn.unwrap
            if !object_type_defn.kind.fields?
              push_error("Invalid inline fragment on #{object_type_defn.kind.name}: #{object_type_defn.name} (must be OBJECT, UNION, or INTERFACE)", ast_node)
            elsif !TypeCondition.possible_type_condition?(type_env.current_type_definition, object_type_defn, type_env.schema)
              push_error("Inline fragment on #{object_type_defn.name} can't be spread inside #{type_env.current_type_definition.name}", ast_node)
            end
          end
          type_env.type_definitions.push(object_type_defn)
        when Nodes::FragmentDefinition
          type_env.root_nodes.push(ast_node)
          # TODO: I'm guessing there are bugs with fragments on complex types, like ![Post!]
          object_type_defn = type_env.schema.types.fetch(ast_node.type, nil)

          # Push the definition even if the object type isn't found,
          # Otherwise you get a "cascading" error for a typo in the type name
          type_env.fragment_usages[ast_node.name].defined(as_type: object_type_defn, node: ast_node)

          if object_type_defn.nil?
            push_error("Fragment definition on undefined type: fragment #{ast_node.name} on #{ast_node.type}", ast_node)
            type_env.type_definitions.push(NO_TYPE)
            Visitor::SKIP
          else
            object_type_defn = object_type_defn.unwrap
            if !object_type_defn.kind.fields?
              push_error("Invalid fragment definition on #{object_type_defn.kind.name}: #{object_type_defn.name} (must be OBJECT, UNION, or INTERFACE)", ast_node)
              type_env.type_definitions.push(NO_TYPE)
              Visitor::SKIP
            else
              type_env.type_definitions.push(object_type_defn)
            end
          end
        when Nodes::FragmentSpread
          type_env.fragment_usages[ast_node.name].used_for(
            node: ast_node,
            on_type: type_env.current_type_definition,
            depth: 0,
            root_node: type_env.current_root_node,
          )
        when Nodes::OperationDefinition
          type_env.root_nodes.push(ast_node)
          object_type_defn = type_env.root_types[ast_node.operation_type.downcase]
          type_env.type_definitions.push(object_type_defn)
        when Nodes::Directive
          directive_defn = type_env.directives[ast_node.name]
          if directive_defn.nil?
            push_error("Undefined directive: @#{ast_node.name}", ast_node)
            Visitor::SKIP
          elsif DirectiveLocation.valid_location?(directive_defn, parent_ast_node)
            type_env.directive_definitions.push(directive_defn)
          else
            message = DirectiveLocation.invalid_location_message(directive_defn, parent_ast_node)
            push_error(message, ast_node)
            Visitor::SKIP
          end
        when Nodes::Field
          parent_type = type_env.type_definitions.last
          if parent_type && parent_type.kind.fields?
            field_defn = type_env.schema.get_field(parent_type, ast_node.name)
            if field_defn.nil?
              push_error("Undefined field on #{parent_type.name}: #{ast_node.name}", ast_node)
              type_env.field_definitions.push(NO_FIELD)
              type_env.type_definitions.push(NO_TYPE)
            else
              type_env.field_definitions.push(field_defn)
              next_object_type_defn = field_defn.type.unwrap
              type_env.type_definitions.push(next_object_type_defn)
            end
          else
            type_env.field_definitions.push(NO_FIELD)
            type_env.type_definitions.push(NO_TYPE)
          end
        when Nodes::Argument
          # Argument lookup depends on where we are, it might be:
          # - inside another argument (nested input objects)
          # - inside a directive
          # - inside a field
          argument_defn = if type_env.argument_definitions.last
            arg_type = type_env.argument_definitions.last.type.unwrap
            if arg_type.kind.input_object?
              arg_type.input_fields[ast_node.name]
            else
              # This is a query error, a non-input-object has argument fields
              nil
            end
          elsif type_env.directive_definitions.last
            type_env.directive_definitions.last.arguments[ast_node.name]
          elsif type_env.field_definitions.last
            type_env.field_definitions.last.arguments[ast_node.name]
          else
            nil
          end
          type_env.argument_definitions.push(argument_defn)
        else
          # This node doesn't add any information
          # to the the type environment
        end
      end

      def push_error(message, node)
        @errors << build_error(message, node)
      end

      def build_error(message, node)
        error = GraphQL::AnalysisError.new(message)
        error.ast_node = node
        error
      end

      # Clean up the type environment as you exit AST nodes
      # this is responsible for undoing the work of TypeCheck
      class TypeEnvCleanup
        include GraphQL::Language

        def call(memo, visit_kind, type_env, node, parent_node)
          visit_kind == :leave && leave_node(node, type_env)
        end

        private

        def leave_node(ast_node, type_env)
          case ast_node
          when Nodes::InlineFragment
            type_env.type_definitions.pop
          when Nodes::FragmentDefinition, Nodes::OperationDefinition
            type_env.type_definitions.pop
          when Nodes::Directive
            type_env.directive_definitions.pop
          when Nodes::Field
            type_env.field_definitions.pop
            type_env.type_definitions.pop
          when Nodes::Argument
            type_env.argument_definitions.pop
          else
            # This node didn't add anything to the stack(s),
            # so there's no need to remove anything
          end
        end
      end
    end
  end
end
