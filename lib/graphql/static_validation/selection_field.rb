# frozen_string_literal: true
module GraphQL
  module StaticValidation
    class SelectionField
      include Comparable

      class << self
        attr_accessor :id

        def build(node, type, parent_type_definition)
          @id += 1
          new(@id, node, type, parent_type_definition)
        end

        def children(fields)
          SelectionContainer.children(fields)
        end
      end

      @id = 0

      attr_reader :id, :parent_type_definition, :selection_container, :node, :type

      def initialize(id, node, type, parent_type_definition)
        @id = id
        @node = node
        @parent_type_definition = parent_type_definition
        @type = type
        @selection_container = SelectionContainer.new(node.selections)
      end

      def <=>(other)
        id <=> other.id
      end

      def name_and_arguments
        @name_and_arguments ||= FieldNameAndArguments.new(@node)
      end

      def output_name
        @node.alias || @node.name
      end

      def parent_type_abstract?
        parent_type_definition.kind.abstract?
      end

      def type_shape
        @type_shape ||= Shape.apply(type)
      end
    end
  end
end
