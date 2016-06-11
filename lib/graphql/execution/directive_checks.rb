module GraphQL
  module Execution
    # Boolean checks for how an AST node's directives should
    # influence its execution
    module DirectiveChecks
      SKIP = "skip"
      INCLUDE = "include"
      DEFER = "defer"
      STREAM = "stream"

      module_function

      # @return [Boolean] Should this AST node be deferred?
      def defer?(irep_node)
        irep_node.directives.any? { |dir| dir.parent.ast_node == irep_node.ast_node && dir.name == DEFER }
      end

      # @return [Boolean] Should this AST node be streamed?
      def stream?(irep_node)
        irep_node.directives.any? { |dir| dir.name == STREAM }
      end

      # This covers `@include(if:)` & `@skip(if:)`
      # @return [Boolean] Should this node be skipped altogether?
      def skip?(irep_node, query)
        irep_node.directives.each do |directive_node|
          if directive_node.name == SKIP || directive_node.name == INCLUDE
            directive_defn = directive_node.definitions.first
            args = query.arguments_for(directive_node, directive_defn)
            if !directive_defn.include?(args)
              return true
            end
          end
        end
        false
      end

      # @return [Boolean] Should this node be included in the query?
      def include?(irep_node, query)
        !skip?(irep_node, query)
      end
    end
  end
end
