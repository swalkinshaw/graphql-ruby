module GraphQL
  module Analysis
    class TypeCheck
      module TypeCondition

        module_function

        def possible_type_condition?(parent_type, child_type, schema)
          overlapping_types = possible_types(parent_type, schema) & possible_types(child_type, schema)
          overlapping_types.any?
        end

        private

        module_function

        def possible_types(type, schema)
          if type.kind.wraps?
            possible_types(type.of_type, schema)
          elsif type.kind.object?
            [type]
          elsif type.kind.resolves?
            schema.possible_types(type)
          else
            []
          end
        end
      end
    end
  end
end
