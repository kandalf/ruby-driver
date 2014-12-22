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
    module V1
      class Encoder
        HEADER_FORMAT = 'c4N'.freeze

        def initialize(compressor = nil, protocol_version = 1)
          @compressor       = compressor
          @protocol_version = protocol_version
        end

        def encode(buffer, request, stream_id)
          flags = request.trace? ? 2 : 0
          body  = request.write(CqlByteBuffer.new, @protocol_version, self)

          if @compressor && request.compressable? && @compressor.compress?(body)
            flags |= 1
            body   = @compressor.compress(body)
          end

          header  = [@protocol_version, flags, stream_id, request.opcode, body.bytesize]
          buffer << header.pack(HEADER_FORMAT)
          buffer << body
          buffer
        end

        def write_parameters(buffer, params, types)
          Coder.write_values_v1(buffer, params, types)
        end
      end

      class Decoder
        def initialize(handler, compressor = nil)
          @handler    = handler
          @compressor = compressor
          @state      = :header
          @header     = nil
          @length     = nil
          @buffer     = CqlByteBuffer.new
        end

        def <<(data)
          @buffer << data

          __send__(:"decode_#{@state}", @buffer)
        end

        private

        READY = ReadyResponse.new

        def decode_header(buffer)
          loop do
            buffer_length = buffer.length

            return if buffer_length < 8

            frame_header = buffer.read_int
            frame_length = buffer.read_int

            if (buffer_length - 8) < frame_length
              @header = frame_header
              @length = frame_length
              @state  = :body

              return
            end

            actual_decode(buffer, frame_header, frame_length)
          end

          nil
        end

        def decode_body(buffer)
          frame_header = @header
          frame_length = @length

          loop do
            buffer_length = buffer.length

            return if buffer_length < frame_length

            actual_decode(buffer, frame_header, frame_length)

            if (buffer_length - frame_length) < 8
              @header = nil
              @length = nil
              @state  = :header

              return
            end

            frame_header = buffer.read_int
            frame_length = buffer.read_int
          end

          @header = frame_header
          @length = frame_length

          nil
        end

        def actual_decode(buffer, fields, size)
          protocol_version = (fields >> 24) & 0x7f
          compression      = (fields >> 16) & 0x01
          tracing          = (fields >> 16) & 0x02
          stream_id        = (fields >> 8) & 0xff
          stream_id        = (stream_id & 0x7f) - (stream_id & 0x80)
          opcode           = fields & 0xff

          if compression == 1
            if @compressor
              buffer = CqlByteBuffer.new(@compressor.decompress(buffer.read(size)))
              size   = buffer.size
            else
              raise Errors::DecodingError, 'Compressed frame received, but no compressor configured'
            end
          end

          if tracing == 2
            trace_id = buffer.read_uuid
            size    -= 16
          else
            trace_id = nil
          end

          extra_length = buffer.length - size
          response = decode_response(opcode, protocol_version, buffer, size, trace_id)

          if buffer.length > extra_length
            buffer.discard(buffer.length - extra_length)
          end

          if stream_id == -1
            @handler.notify_event_listeners(response)
          else
            @handler.complete_request(stream_id, response)
          end
        end

        private

        def decode_response(opcode, protocol_version, buffer, size, trace_id)
          response = case opcode
          when 0x00 # ERROR
            code    = buffer.read_int
            message = buffer.read_string

            case code
            when 0x1000 # unavailable
              details = {
                :cl       => buffer.read_consistency,
                :required => buffer.read_int,
                :alive    => buffer.read_int
              }

              DetailedErrorResponse.new(code, message, details)
            when 0x1100 # write_timeout
              details = {
                :cl       => buffer.read_consistency,
                :received => buffer.read_int,
                :blockfor => buffer.read_int
              }

              write_type = buffer.read_string
              write_type.downcase!

              details[:write_type] = write_type.to_sym

              DetailedErrorResponse.new(code, message, details)
            when 0x1200 # read_timeout
              details = {
                :cl           => buffer.read_consistency,
                :received     => buffer.read_int,
                :blockfor     => buffer.read_int,
                :data_present => buffer.read_byte != 0
              }

              DetailedErrorResponse.new(code, message, details)
            when 0x2400 # already_exists
              details = {
                :ks    => buffer.read_string,
                :table => buffer.read_string
              }

              DetailedErrorResponse.new(code, message, details)
            when 0x2500
              DetailedErrorResponse.new(code, message, :id => buffer.read_short_bytes)
            else
              ErrorResponse.new(code, message)
            end
          when 0x02 # READY
            READY
          when 0x03 # AUTHENTICATE
            AuthenticateResponse.new(buffer.read_string)
          when 0x06 # SUPPORTED
            SupportedResponse.new(buffer.read_string_multimap)
          when 0x08 # RESULT
            result_type = buffer.read_int
            case result_type
            when 0x0001 # Void
              VoidResultResponse.new(trace_id)
            when 0x0002 # Rows
              original_buffer_length = buffer.length
              column_specs, paging_state = Coder.read_metadata_v1(buffer)

              if column_specs.nil?
                consumed_bytes  = original_buffer_length - buffer.length
                remaining_bytes = CqlByteBuffer.new(buffer.read(size - consumed_bytes - 4))
                RawRowsResultResponse.new(protocol_version, remaining_bytes, paging_state, trace_id)
              else
                RowsResultResponse.new(Coder.read_values_v1(buffer, column_specs), column_specs, paging_state, trace_id)
              end
            when 0x0003 # SetKeyspace
              SetKeyspaceResultResponse.new(buffer.read_string, trace_id)
            when 0x0004 # Prepared
              id              = buffer.read_short_bytes
              params_metadata = Coder.read_metadata_v1(buffer).first
              result_metadata = nil
              result_metadata = Coder.read_metadata_v1(buffer).first if protocol_version > 1

              PreparedResultResponse.new(id, params_metadata, result_metadata, trace_id)
            when 0x0005 # SchemaChange
              SchemaChangeResultResponse.new(buffer.read_string, buffer.read_string, buffer.read_string, trace_id)
            else
              raise Errors::DecodingError, "Unsupported result type: #{result_type.inspect}"
            end
          when 0x0C # EVENT
            event_type = buffer.read_string
            case event_type
            when 'SCHEMA_CHANGE'
              SchemaChangeEventResponse.new(buffer.read_string, buffer.read_string, buffer.read_string)
            when 'STATUS_CHANGE'
              StatusChangeEventResponse.new(buffer.read_string, *buffer.read_inet)
            when 'TOPOLOGY_CHANGE'
              TopologyChangeEventResponse.new(buffer.read_string, *buffer.read_inet)
            else
              raise Errors::DecodingError, "Unsupported event type: #{event_type.inspect}"
            end
          when 0x0E # AUTH_CHALLENGE
            AuthChallengeResponse.new(buffer.read_bytes)
          when 0x10 # AUTH_SUCCESS
            AuthSuccessResponse.new(buffer.read_bytes)
          else
            raise Errors::DecodingError, "Unsupported response opcode: #{opcode.inspect}"
          end
        end
      end
    end
  end
end
