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
    class AuthSuccessResponse < Response
      attr_reader :token

      def self.decode(protocol_version, buffer, length, trace_id=nil)
        new(buffer.read_bytes)
      end

      def initialize(token)
        @token = token
      end

      def to_s
        %(AUTH_SUCCESS #{@token && @token.bytesize})
      end

      private

      RESPONSE_TYPES[0x10] = self
    end
  end
end
