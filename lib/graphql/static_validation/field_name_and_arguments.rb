# frozen_string_literal: true
module GraphQL
  module StaticValidation
    class FieldNameAndArguments
      attr_reader :name, :arguments

      def initialize(node)
        @printer = GraphQL::Language::Printer.new
        @name = node.name
        @arguments = node.arguments.map { |arg| @printer.print(arg.value) }.sort.to_set
      end

      def ==(other)
        return false unless other.class == self.class
        name == other.name && arguments == other.arguments
      end
    end
  end
end
