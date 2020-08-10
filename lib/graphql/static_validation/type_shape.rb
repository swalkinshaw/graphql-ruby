# frozen_string_literal: true
module GraphQL
  module StaticValidation
    class Shape
      attr_reader :type

      def initialize(type)
        @type = type
      end

      class << self
        def apply(type)
          case type.kind
          when GraphQL::TypeKinds::NON_NULL
            NonNullShape.new(apply(type.of_type))
          when GraphQL::TypeKinds::LIST
            ListShape.new(apply(type.of_type))
          when GraphQL::TypeKinds::SCALAR, GraphQL::TypeKinds::ENUM
            LeafShape.new(type.graphql_name)
          when GraphQL::TypeKinds::OBJECT, GraphQL::TypeKinds::INTERFACE, GraphQL::TypeKinds::UNION
            CompositeShape::INSTANCE
          else
            raise "invalid type: #{type.name}"
          end
        end
      end
    end

    module ShapeEquality
      def ==(other)
        return false if self.class != other.class
        type == other.type
      end

      def eql?(other)
        self == other
      end

      def hash
        [type].hash
      end
    end

    class ListShape < Shape
      include ShapeEquality
    end

    class NonNullShape < Shape
      include ShapeEquality
    end

    class LeafShape < Shape
      include ShapeEquality
    end

    class CompositeShape < Shape
      INSTANCE = self.class.new
    end
  end
end
