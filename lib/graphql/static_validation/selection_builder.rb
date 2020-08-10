# frozen_string_literal: true
module GraphQL
  module StaticValidation
    class SelectionBuilder
      attr_reader :roots

      def initialize
        @fragments = {}
        @roots = Set.new
        @stack = []
      end

      def enter_field(node, type_definition, parent_type_definition)
        field = SelectionField.build(node, type_definition, parent_type_definition)

        if @stack.any?
          @stack.first.add_field(field)
        end

        if node.selections.any?
          @stack.push(field.selection_container)
        end
      end

      def spread_fragment(node)
        if @stack.any?
          @stack.first.add_spread(fetch_fragment(node.name, nil))
        end
      end

      def enter_fragment_definition(node)
        container = fetch_fragment(node.name, node.selections)

        if @stack.empty?
          @roots.add(container)
        end

        @stack.push(container)
      end

      def enter_generic_selection_container(selection_set)
        container = SelectionContainer.new(selection_set)

        if @stack.empty?
          @roots.add(container)
        else
          @stack.first.add_spread(container)
        end

        @stack.push(container)
      end

      def leave_selection_container
        @stack.pop
      end

      private

      def fetch_fragment(name, selection_set)
        @fragments.fetch(name) do |name|
          @fragments[name] = SelectionContainer.new(selection_set)
        end
      end
    end
  end
end
