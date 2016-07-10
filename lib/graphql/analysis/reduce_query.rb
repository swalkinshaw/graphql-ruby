module GraphQL
  module Analysis
    module_function
    # @param query [GraphQL::Query]
    # @param extra_reducers [Array<[#call]>]
    # @return [Array<Any>]
    def reduce_query(query, extra_reducers)
      visitor = GraphQL::Language::Visitor.new(query.document)
      type_env = GraphQL::Analysis::TypeCheck::TypeEnvironment.new(query.schema)
      type_check = GraphQL::Analysis::TypeCheck.new(query, type_env)

      reducers = []
      reducers << type_check
      reducers.push(*extra_reducers)
      reducers << GraphQL::Analysis::TypeCheck::TypeEnvCleanup.new

      reducers_and_values = reducers.map { |r| initialize_reducer(r, query) }
      # Set up reducers:
      visitor.enter << pass_nodes_to_reducers(:enter, type_env, reducers_and_values)
      visitor.leave << pass_nodes_to_reducers(:leave, type_env, reducers_and_values)

      fragments = []
      operations = []
      query.document.definitions.each { |defn| defn.is_a?(GraphQL::Language::Nodes::FragmentDefinition) ? fragments.push(defn) : operations.push(defn) }
      # Actually run the reducers:
      fragments.each do |ast_frag_defn|
        visitor.visit(ast_frag_defn)
      end

      operations.each do |ast_op_defn|
        visitor.visit(ast_op_defn)
      end

      reducers_and_values.map { |(r, value)| finalize_reducer(r, value) }
    end

    private

    module_function

    # @param visit_type [Symbol] `:enter` or `:exit`
    # @param type_env [GraphQL::Analysis::TypeEnvironment]
    # @param reducers [Array<[#call]>] things to `.call` on each AST node
    # @return [Proc] A proc that calls each of `reducers` with `visit_type, node, parent_node`
    def pass_nodes_to_reducers(visit_type, type_env, reducers_and_values)
      -> (ast_node, parent_ast_node) do
        skipped = false

        reducers_and_values.each do |reducer_and_value|
          reducer = reducer_and_value[0]
          memo = reducer_and_value[1]
          next_memo = reducer.call(memo, visit_type, type_env, ast_node, parent_ast_node)
          reducer_and_value[1] = next_memo
          if next_memo == GraphQL::Language::Visitor::SKIP
            skipped = true
            break
          end
        end

        if skipped
          GraphQL::Language::Visitor::SKIP
        else
          nil
        end
      end
    end

    def initialize_reducer(reducer, query)
      if reducer.respond_to?(:initial_value)
        [reducer, reducer.initial_value(query)]
      else
        [reducer, nil]
      end
    end

    def finalize_reducer(reducer, reduced_value)
      if reducer.respond_to?(:final_value)
        reducer.final_value(reduced_value)
      else
        reduced_value
      end
    end
  end
end
