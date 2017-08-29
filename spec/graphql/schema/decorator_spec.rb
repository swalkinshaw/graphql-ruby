# frozen_string_literal: true
require "spec_helper"

describe GraphQL::Schema::Implementation do
  def build_schema(graphql_str, namespace:)
    GraphQL::Schema.from_definition(graphql_str, implementation: namespace)
  end

  module TestImplementation
    class LoggerDecorator
      def call(object, context, **args)
        puts "object: #{object}"
        puts "args: #{args}"
      end
    end

    module AuthorizationDecorator
      class Policy
        def initialize(role)
          @role = role
        end

        def call(object, context, **args)
          unless context[:roles].include?(@role)
            raise GraphQL::ExecutionError, "access denied"
          end
        end
      end

      def authorize(role)
        decorate Policy, role
      end
    end

    class Query < GraphQL::Object
      extend GraphQL::ResolveDecorators
      extend AuthorizationDecorator

      def cards
        [
          CardObject.new("H", 5),
          CardObject.new("S", 6),
          CardObject.new("C", 11),
        ]
      end

      decorate LoggerDecorator
      authorize :owner
      def suit(letter:)
        letter
      end
    end

    class Card < GraphQL::Object
      extend GraphQL::ResolveDecorators

      decorate LoggerDecorator
      def is_facecard
        object.number > 10 || object.number == 1
      end
    end

    class Suit < GraphQL::Object
      alias :letter :object

      NAMES = { "H" => "Hearts", "C" => "Clubs", "S" => "Spades", "D" => "Diamonds"}

      def name
        NAMES[letter]
      end

      def cards
        1.upto(12) do |i|
          CardObject.new(letter, i)
        end
      end

      def color
        if letter == "H" || letter == "D"
          "RED"
        else
          "BLACK"
        end
      end
    end

    CardObject = Struct.new(:suit, :number)
    SuitObject = Struct.new(:letter)
  end

  describe "building a schema" do
    let(:schema_graphql) { <<~GRAPHQL
      type Query {
        int: Int
        cards: [Card]
        suit(letter: String!): Suit
      }

      type Card {
        suit: Suit
        number: Int
        isFacecard: Boolean
      }

      type Suit {
        letter: String
        name: String
        cards: [Card]
        color: Color
      }

      enum Color {
        RED
        BLACK
      }
    GRAPHQL
    }

    it "builds a working schema with decorators" do
      schema = build_schema(schema_graphql, namespace: TestImplementation)
      query = <<~GRAPHQL
        {
          cards {
            suit {
              name
              color
            }
            number
            isFacecard
          }
          suit(letter: "D") {
            name
          }
        }
      GRAPHQL

      res = schema.execute query, context: { roles: %i(owner) }

      expected_data = {
        "cards" => [
          {"suit"=>{"name"=>"Hearts", "color"=>"RED"},  "number"=>5,  "isFacecard"=>false},
          {"suit"=>{"name"=>"Spades", "color"=>"BLACK"},"number"=>6,  "isFacecard"=>false},
          {"suit"=>{"name"=>"Clubs",  "color"=>"BLACK"},"number"=>11, "isFacecard"=>true}
        ],
        "suit"=> {
          "name"=>"Diamonds"
        }
      }

      assert_equal expected_data, res["data"]
    end
  end
end
