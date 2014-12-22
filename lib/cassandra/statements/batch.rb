# encoding: utf-8

#--
# Copyright 2013-2014 DataStax, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

module Cassandra
  module Statements
    # Batch statement groups several {Cassandra::Statement}. There are several types of Batch statements available:
    # @see Cassandra::Session#batch
    # @see Cassandra::Session#logged_batch
    # @see Cassandra::Session#unlogged_batch
    # @see Cassandra::Session#counter_batch
    class Batch
      # @private
      class Logged < Batch
        def type
          :logged
        end
      end

      # @private
      class Unlogged < Batch
        def type
          :unlogged
        end
      end

      # @private
      class Counter < Batch
        def type
          :counter
        end
      end

      include Statement

      # @private
      attr_reader :statements

      # @private
      def initialize
        @statements = []
      end

      # @!method add(statement, args)
      # Adds a statement to this batch.
      #
      # @param statement [String, Cassandra::Statements::Simple,
      #   Cassandra::Statements::Prepared, Cassandra::Statements::Bound]
      #   statement to add.
      # @param args [Hash, Array] named or positional arguments to bind, must
      #   contain the same number of parameters as the number of named
      #   (`:name`) or positional (`?`) markers in the original CQL passed to
      #   {Cassandra::Session#prepare}
      #
      # @note Positional arguments are only supported on Apache Cassandra 2.1
      #   and above.
      #
      # @overload add(statement, *args)
      #   Adds a statement to this batch using the deprecated splat-style way of
      #   passing positional arguments
      #
      #   @deprecated Please pass a single {Hash} or {Array} of named or
      #     positional arguments accordingly, the `*args` style is deprecated.
      #
      #   @param statement [String, Cassandra::Statements::Simple,
      #     Cassandra::Statements::Prepared, Cassandra::Statements::Bound]
      #     statement to add.
      #   @param args [*Object] **this style of positional arguments is
      #     deprecated, please pass a single {Array} or {Hash} instead** -
      #     arguments to paramterized query or prepared statement
      #
      # @return [self]
      def add(statement, *args)
        if args.one? && (args.first.is_a?(::Array) || args.first.is_a?(::Hash))
          args = args.first
        elsif !args.empty?
          ::Kernel.warn "[WARNING] Splat style (*args) positional arguments " \
                        "are deprecated, pass a Hash or an Array instead - " \
                        "called from #{caller.first}"
        end

        case statement
        when String
          @statements << Simple.new(statement, args)
        when Prepared
          @statements << statement.bind(args)
        when Bound, Simple
          @statements << statement
        else
          raise ::ArgumentError, "a batch can only consist of simple or prepared statements, #{statement.inspect} given"
        end

        self
      end

      # A batch statement doesn't really have any cql of its own as it is composed of multiple different statements
      # @return [nil] nothing
      def cql
        nil
      end

      # @return [Symbol] one of `:logged`, `:unlogged` or `:counter`
      def type
      end

      # @return [String] a CLI-friendly batch statement representation
      def inspect
        "#<#{self.class.name}:0x#{self.object_id.to_s(16)} @type=#{type.inspect}>"
      end
    end
  end
end
