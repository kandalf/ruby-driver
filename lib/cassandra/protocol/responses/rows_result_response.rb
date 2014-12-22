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
  module Protocol
    class RowsResultResponse < ResultResponse
      attr_reader :rows, :metadata, :paging_state

      def initialize(rows, metadata, paging_state, trace_id)
        super(trace_id)
        @rows, @metadata, @paging_state = rows, metadata, paging_state
      end

      def self.decode(protocol_version, buffer, length, trace_id=nil)
        original_buffer_length = buffer.length
        column_specs, columns_count, paging_state = read_metadata(protocol_version, buffer)
        if column_specs.nil?
          consumed_bytes = original_buffer_length - buffer.length
          remaining_bytes = CqlByteBuffer.new(buffer.read(length - consumed_bytes))
          RawRowsResultResponse.new(protocol_version, remaining_bytes, paging_state, trace_id)
        else
          new(read_rows(protocol_version, buffer, column_specs), column_specs, paging_state, trace_id)
        end
      end

      def to_s
        %(RESULT ROWS #@metadata #@rows)
      end

      private

      RESULT_TYPES[0x02] = self
    end
  end
end
