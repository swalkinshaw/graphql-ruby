require "spec_helper"

describe GraphQL::Analysis::TypeCheck do
  let(:reduce_result) { GraphQL::Analysis.reduce_query(query, []) }
  let(:query) { GraphQL::Query.new(DummySchema, query_string) }

  def assert_error_messages(reduce_result, *messages)
    type_errors, *rest = reduce_result
    assert_equal messages, type_errors.map(&:message)
  end

  describe "directive validation" do
    describe "undefined directives" do
      let(:query_string) {%|
        {
          cheese(id: 1) {
            id @bogus
          }
        }
      |}

      it "adds an error" do
        assert_error_messages(reduce_result, "Undefined directive: @bogus")
      end
    end

    describe "directives in the wrong place" do
      let(:query_string) {%|
        query @skip(if: false) {
          cheese(id: 1) {
            id
          }
        }
      |}

      it "adds an error" do
        assert_error_messages(reduce_result, "Invalid directive location: @skip is not allowed on queries, only: fields, fragment spreads, inline fragments.")
      end
    end
  end

  describe "fragments" do
    describe "infinite fragments" do
      let(:query_string) {%|
        query {
          cheese(id: 1) {
            ... cheeseFields
            ... cheeseFields3
          }
        }

        fragment cheeseFields on Cheese {
          similarCheese(source: COW) {
            ... cheeseFields2
          }
        }

        fragment cheeseFields2 on Cheese {
          ... cheeseFields
        }

        fragment cheeseFields3 on Cheese {
          ... cheeseFields3
        }
      |}

      it "adds an error" do
        assert_error_messages(reduce_result,
          "Fragments are infinite: query => ...cheeseFields => ...cheeseFields2 => ...cheeseFields",
          "Fragments are infinite: fragment cheeseFields on Cheese => ...cheeseFields2 => ...cheeseFields",
          "Fragments are infinite: fragment cheeseFields2 on Cheese => ...cheeseFields => ...cheeseFields2" ,
        )
      end
    end

    describe "fragments on non-existent types" do
      let(:query_string) {%|
      query {
        cheese(id: 1) {
          ...cheeseFields
          ...greaseFields
          ... on Lipid { id }
          ... on Cheese { id }
        }
      }

      fragment cheeseFields on Cheese { id }
      fragment greaseFields on Grease { id }
      |}
      it "adds an error" do
        assert_error_messages(reduce_result,
          "Fragment definition on undefined type: fragment greaseFields on Grease",
          "Inline fragment on undefined type: Lipid",
        )
      end
    end

    describe "unused fragments, undefined fragments, duplicate fragment definitions" do
      let(:query_string) {%|
      query {
        cheese(id: 1) {
          ... cheeseFields
          ... cheeseFields2
          # undefined
          ... jishiFields
        }
      }
      fragment cheeseFields on Cheese { id }
      fragment cheeseFields2 on Cheese { id }
      fragment cheeseFields2 on Cheese { id }
      # unused
      fragment fromageFields on Cheese { id }
      |}

      it "adds errors" do
        assert_error_messages(reduce_result,
          "Duplicate fragment name: cheeseFields2",
          "Unused fragment definition: fromageFields",
          "Undefined fragment spread: ...jishiFields",
        )
      end
    end

    describe "fragments on scalar types" do
      let(:query_string) {%|
        {
          cheese(id: 1) {
            ... on Boolean {
              truthiness
            }
            ... on DairyProductInput {
              stuff
            }

            ... intFields
            ... on Cheese {
              id
            }
          }
        }

        fragment intFields on Int {
          number
        }
      |}
      it "adds an error" do
        assert_error_messages(reduce_result,
          "Invalid fragment definition on SCALAR: Int (must be OBJECT, UNION, or INTERFACE)",
          "Invalid inline fragment on SCALAR: Boolean (must be OBJECT, UNION, or INTERFACE)",
          "Invalid inline fragment on INPUT_OBJECT: DairyProductInput (must be OBJECT, UNION, or INTERFACE)",
          "Impossible fragment spread: ...intFields can't apply to Cheese",
        )
      end
    end

    describe "fragment spreads on impossible types" do
      let(:query_string) {%|
        {
          cheese(id: 1) {
            ... on Edible {
              fatContent
            }
            ... on Milk { id }
            ... sweetenerFields
            ... on Cheese { id }
          }
        }

        fragment sweetenerFields on Sweetener {
          sweetness
        }
      |}

      it "adds errors" do
        assert_error_messages(reduce_result,
          "Inline fragment on Milk can't be spread inside Cheese",
          "Impossible fragment spread: ...sweetenerFields can't apply to Cheese",
        )
      end
    end
  end

  describe "fields" do
    describe "undefined fields on type" do
      let(:query_string) {%|
        {
          cheese(id: 1) {
            id
            nonsense
            ... cheeseFields
            ... on Edible {
              fatContent
              flavor
            }
          }
        }

        fragment cheeseFields on Cheese {
          bogus
        }
      |}

      it "adds errors" do
        assert_error_messages(reduce_result,
          "Undefined field on Cheese: bogus",
          "Undefined field on Cheese: nonsense",
          "Undefined field on Edible: flavor",
        )
      end
    end

    describe "merge conflicts" do
      let(:query_string) {%|
        query getCheese($sourceVar: DairyAnimal!) {
          cheese(id: 1) {
            id,
            nickname: name,
            nickname: fatContent,
            fatContent
            differentLevel: fatContent
            similarCheese(source: $sourceVar)

            similarCow: similarCheese(source: COW) {
              similarCowSource: source,
              differentLevel: fatContent
            }
            ...cheeseFields
            ... on Cheese {
              fatContent: name
              similarCheese(source: SHEEP)
            }
          }
        }
        fragment cheeseFields on Cheese {
          fatContent,
          similarCow: similarCheese(source: COW) { similarCowSource: id, id }
          id @someFlag
        }
      |}

      it "adds errors"
    end
  end
end
