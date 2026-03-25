require "faraday"
require "faraday/multipart"
require "json"
require "time"
require_relative "errors"

module D3RubyClient
  # Dragdropdo Business API Client
  #
  # A Ruby client library for interacting with the Dragdropdo Business API.
  # Provides methods for file uploads, operations, and status checking.
  class Dragdropdo
    attr_reader :api_key, :base_url, :timeout

    # Create a new Dragdropdo Client instance
    #
    # @param api_key [String] API key for authentication
    # @param base_url [String] Base URL of the D3 API (default: 'https://api-dev.dragdropdo.com')
    # @param timeout [Integer] Request timeout in milliseconds (default: 30000)
    # @param headers [Hash] Custom headers to include in all requests
    #
    # @example
    #   client = D3RubyClient::Dragdropdo.new(
    #     api_key: 'your-api-key',
    #     base_url: 'https://api-dev.dragdropdo.com',
    #     timeout: 30000
    #   )
    def initialize(api_key:, base_url: nil, timeout: 30000, headers: {})
      raise D3ValidationError, "API key is required" if api_key.nil? || api_key.empty?

      @api_key = api_key
      @base_url = (base_url || "https://api-dev.dragdropdo.com").chomp("/")
      @timeout = timeout
      @headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}",
      }.merge(headers)
    end

    # Upload a file to D3 storage
    #
    # This method handles the complete upload flow:
    # 1. Request presigned URLs from the API
    # 2. Upload file parts to presigned URLs
    # 3. Return the file key for use in operations
    #
    # @param file [String] File path
    # @param file_name [String] Original file name
    # @param mime_type [String] MIME type (auto-detected if not provided)
    # @param parts [Integer] Number of parts for multipart upload (auto-calculated if not provided)
    # @param on_progress [Proc] Optional progress callback
    # @return [Hash] Upload response with file key
    #
    # @example
    #   result = client.upload_file(
    #     file: '/path/to/file.pdf',
    #     file_name: 'document.pdf',
    #     mime_type: 'application/pdf',
    #     on_progress: ->(progress) { puts "Upload: #{progress[:percentage]}%" }
    #   )
    #   puts "File key: #{result[:file_key]}"
    def upload_file(file:, file_name:, mime_type: nil, parts: nil, on_progress: nil)
      raise D3ValidationError, "file_name is required" if file_name.nil? || file_name.empty?
      raise D3ValidationError, "file must be a file path string" unless file.is_a?(String)
      raise D3ValidationError, "File not found: #{file}" unless File.exist?(file)

      file_size = File.size(file)

      # Calculate parts if not provided
      chunk_size = 5 * 1024 * 1024 # 5MB per part
      calculated_parts = parts || (file_size.to_f / chunk_size).ceil
      actual_parts = [1, [calculated_parts, 100].min].max # Limit to 100 parts

      # Detect MIME type if not provided
      detected_mime_type = mime_type || get_mime_type(file_name)

      begin
        # Step 1: Request presigned URLs
        upload_response = request(:post, "/api/v1/initiate-upload", {
          file_name: file_name,
          size: file_size,
          mime_type: detected_mime_type,
          parts: actual_parts,
        })

        upload_data = if upload_response.is_a?(Hash)
          upload_response[:data] || upload_response["data"] || upload_response
        else
          parsed = JSON.parse(upload_response) rescue {}
          parsed["data"] || parsed[:data] || parsed
        end
        upload_data ||= {}
        file_key = upload_data[:file_key] || upload_data["file_key"]
        upload_id = upload_data[:upload_id] || upload_data["upload_id"]
        presigned_urls = upload_data[:presigned_urls] || upload_data["presigned_urls"] || []
        object_name = upload_data[:object_name] || upload_data["object_name"]

        if presigned_urls.length != actual_parts
          raise D3UploadError, "Mismatch: requested #{actual_parts} parts but received #{presigned_urls.length} presigned URLs"
        end

        raise D3UploadError, "Upload ID not received from server" if upload_id.nil? || upload_id.empty?

        # Step 2: Upload file parts and capture ETags
        chunk_size_per_part = (file_size.to_f / actual_parts).ceil
        bytes_uploaded = 0
        upload_parts = []

        File.open(file, "rb") do |file_handle|
          (0...actual_parts).each do |i|
            start = i * chunk_size_per_part
            ending = [start + chunk_size_per_part, file_size].min
            part_size = ending - start

            # Read chunk
            file_handle.seek(start)
            chunk = file_handle.read(part_size)

            # Upload chunk and capture ETag from response headers
            put_response = Faraday.put(presigned_urls[i]) do |req|
              req.body = chunk
              req.headers["Content-Type"] = detected_mime_type
            end

            raise D3UploadError, "Failed to upload part #{i + 1}" unless put_response.success?

            # Extract ETag from response
            etag = put_response.headers["etag"] || put_response.headers["ETag"] || ""
            raise D3UploadError, "Failed to get ETag for part #{i + 1}" if etag.empty?

            upload_parts << {
              etag: etag.gsub(/^"|"$/, ""), # Remove quotes if present
              part_number: i + 1,
            }

            bytes_uploaded += part_size

            # Report progress
            if on_progress
              progress = {
                current_part: i + 1,
                total_parts: actual_parts,
                bytes_uploaded: bytes_uploaded,
                total_bytes: file_size,
                percentage: ((bytes_uploaded.to_f / file_size) * 100).round,
              }
              on_progress.call(progress)
            end
          end
        end

        # Step 3: Complete the multipart upload
        begin
          request(:post, "/api/v1/complete-upload", {
            file_key: file_key,
            upload_id: upload_id,
            object_name: object_name,
            parts: upload_parts,
          })
        rescue D3ClientError => e
          raise D3UploadError, "Failed to complete upload: #{e.message}"
        end

        {
          file_key: file_key,
          upload_id: upload_id,
          presigned_urls: presigned_urls,
          object_name: object_name,
          # CamelCase aliases for compatibility
          fileKey: file_key,
          uploadId: upload_id,
          presignedUrls: presigned_urls,
          objectName: object_name,
        }
      rescue D3ClientError, D3APIError => e
        raise e
      rescue StandardError => e
        raise D3UploadError, "Upload failed: #{e.message}"
      end
    end

    # Check if an operation is supported for a file extension
    #
    # @param ext [String] File extension (e.g., 'pdf', 'jpg')
    # @param action [String] Optional specific action to check
    # @param parameters [Hash] Optional parameters for validation
    # @return [Hash] Supported operation response
    def check_supported_operation(ext:, action: nil, parameters: nil)
      raise D3ValidationError, "Extension (ext) is required" if ext.nil? || ext.empty?

      begin
        response = request(:post, "/api/v1/supported-operation", {
          ext: ext,
          action: action,
          parameters: parameters,
        })

        # Handle both symbol and string keys
        data = if response.is_a?(Hash)
          response[:data] || response["data"] || response
        else
          {}
        end
        
        # Ensure we return a hash with symbol keys
        if data.is_a?(Hash)
          data.transform_keys(&:to_sym) rescue data
        else
          data
        end
      rescue D3ClientError, D3APIError => e
        raise e
      rescue StandardError => e
        raise D3ClientError, "Failed to check supported operation: #{e.message}"
      end
    end

    # Create a file operation (convert, compress, merge, zip, etc.)
    #
    # @param action [String] Action to perform
    # @param file_keys [Array<String>] Array of file keys from upload
    # @param parameters [Hash] Optional action-specific parameters
    # @param notes [Hash] Optional user metadata
    # @return [Hash] Operation response with main task ID
    def create_operation(action:, file_keys:, parameters: nil, notes: nil)
      raise D3ValidationError, "Action is required" if action.nil? || action.empty?
      raise D3ValidationError, "At least one file key is required" if file_keys.nil? || file_keys.empty?

      begin
        response = request(:post, "/api/v1/do", {
          action: action,
          file_keys: file_keys,
          parameters: parameters,
          notes: notes,
        })

        data = if response.is_a?(Hash)
          response[:data] || response["data"] || response
        else
          parsed = JSON.parse(response) rescue {}
          parsed["data"] || parsed[:data] || parsed
        end
        
        main_task_id = data.is_a?(Hash) ? (data[:main_task_id] || data["main_task_id"]) : nil
        
        {
          main_task_id: main_task_id,
          mainTaskId: main_task_id, # CamelCase alias
        }
      rescue D3ClientError, D3APIError => e
        raise e
      rescue StandardError => e
        raise D3ClientError, "Failed to create operation: #{e.message}"
      end
    end

    # Convenience methods

    # Convert files to a different format
    def convert(file_keys:, convert_to:, notes: nil)
      create_operation(
        action: "convert",
        file_keys: file_keys,
        parameters: { convert_to: convert_to },
        notes: notes
      )
    end

    # Compress files
    def compress(file_keys:, compression_value: "recommended", notes: nil)
      create_operation(
        action: "compress",
        file_keys: file_keys,
        parameters: { compression_value: compression_value },
        notes: notes
      )
    end

    # Merge multiple files
    def merge(file_keys:, notes: nil)
      create_operation(action: "merge", file_keys: file_keys, notes: notes)
    end

    # Create a ZIP archive from files
    def zip(file_keys:, notes: nil)
      create_operation(action: "zip", file_keys: file_keys, notes: notes)
    end

    # Lock PDF with password
    def lock_pdf(file_keys:, password:, notes: nil)
      create_operation(
        action: "lock",
        file_keys: file_keys,
        parameters: { password: password },
        notes: notes
      )
    end

    # Unlock PDF with password
    def unlock_pdf(file_keys:, password:, notes: nil)
      create_operation(
        action: "unlock",
        file_keys: file_keys,
        parameters: { password: password },
        notes: notes
      )
    end

    # Reset PDF password
    def reset_pdf_password(file_keys:, old_password:, new_password:, notes: nil)
      create_operation(
        action: "reset_password",
        file_keys: file_keys,
        parameters: {
          old_password: old_password,
          new_password: new_password,
        },
        notes: notes
      )
    end

    # Get operation status
    #
    # @param main_task_id [String] Main task ID
    # @param file_key [String] Optional input file key for specific file status
    # @return [Hash] Status response
    def get_status(main_task_id:, file_key: nil)
      raise D3ValidationError, "main_task_id is required" if main_task_id.nil? || main_task_id.empty?

      begin
        url = "/api/v1/status/#{main_task_id}"
        url += "/#{file_key}" if file_key

        response = request(:get, url)
        data = if response.is_a?(Hash)
          response[:data] || response["data"] || response
        else
          {}
        end
        
        # Ensure we return a hash with symbol keys, and convert nested arrays
        if data.is_a?(Hash)
          result = data.transform_keys(&:to_sym) rescue data
          # Convert files_data array elements to symbol keys
          if result.is_a?(Hash) && result[:files_data].is_a?(Array)
            result[:files_data] = result[:files_data].map do |file|
              file.is_a?(Hash) ? file.transform_keys(&:to_sym) : file
            end
          end
          # Normalize status to lowercase
          result[:operation_status] = result[:operation_status].to_s.downcase if result[:operation_status]
          # Add camelCase aliases
          result[:operationStatus] = result[:operation_status] if result[:operation_status]
          result[:filesData] = result[:files_data] if result[:files_data]
          if result[:files_data].is_a?(Array)
            result[:files_data] = result[:files_data].map do |file|
              file[:status] = file[:status].to_s.downcase if file[:status]
              file[:downloadLink] = file[:download_link] if file[:download_link]
              file[:errorCode] = file[:error_code] if file[:error_code]
              file[:errorMessage] = file[:error_message] if file[:error_message]
              file[:fileKey] = file[:file_key] if file[:file_key]
              file
            end
            result[:filesData] = result[:files_data]
          end
          result
        else
          data
        end
      rescue D3ClientError, D3APIError => e
        raise e
      rescue StandardError => e
        raise D3ClientError, "Failed to get status: #{e.message}"
      end
    end

    # Poll operation status until completion or failure
    #
    # @param main_task_id [String] Main task ID
    # @param file_key [String] Optional input file key for specific file status
    # @param interval [Integer] Polling interval in milliseconds (default: 2000)
    # @param timeout [Integer] Maximum polling duration in milliseconds (default: 300000)
    # @param on_update [Proc] Optional callback for each status update
    # @return [Hash] Status response with final status
    def poll_status(main_task_id:, file_key: nil, interval: 2000, timeout: 300_000, on_update: nil)
      start_time = Time.now.to_f * 1000

      loop do
        # Check timeout
        if (Time.now.to_f * 1000) - start_time > timeout
          raise D3TimeoutError, "Polling timed out after #{timeout}ms"
        end

        # Get status
        status = get_status(main_task_id: main_task_id, file_key: file_key)

        # Call update callback
        on_update&.call(status)

        # Check if completed or failed (support both snake_case and camelCase)
        op_status = status[:operation_status] || status[:operationStatus]
        return status if %w[completed failed].include?(op_status)

        # Wait before next poll
        sleep(interval / 1000.0) # Convert ms to seconds
      end
    end

    private

    # Make an HTTP request to the API
    def request(method, endpoint, data = nil)
      url = "#{@base_url}#{endpoint}"

      connection = Faraday.new(url: url, headers: @headers) do |f|
        f.request :json
        f.response :json
      end

      response = connection.public_send(method) do |req|
        req.body = data.to_json if data
      end

      unless response.success?
        body = response.body.is_a?(Hash) ? response.body : (JSON.parse(response.body) rescue {})
        raise D3APIError.new(
          body[:message] || body["message"] || body[:error] || body["error"] || "API request failed",
          response.status,
          body[:code] || body["code"],
          body
        )
      end

      # Parse JSON if needed (WebMock might return string)
      body = response.body
      if body.is_a?(String)
        body = JSON.parse(body, symbolize_names: true)
      elsif body.is_a?(Hash)
        # Ensure keys are symbols for consistency
        body = body.transform_keys(&:to_sym) rescue body
      end
      body
    rescue Faraday::Error => e
      if e.response
        body = JSON.parse(e.response[:body]) rescue {}
        raise D3APIError.new(
          body[:message] || body[:error] || e.message || "API request failed",
          e.response[:status],
          body[:code],
          body
        )
      end
      raise D3ClientError, "Network error: #{e.message}"
    rescue StandardError => e
      raise D3ClientError, "Request error: #{e.message}"
    end

    # Get MIME type from file extension
    def get_mime_type(file_name)
      mime_types = {
        ".pdf" => "application/pdf",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".png" => "image/png",
        ".gif" => "image/gif",
        ".webp" => "image/webp",
        ".doc" => "application/msword",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls" => "application/vnd.ms-excel",
        ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".zip" => "application/zip",
        ".txt" => "text/plain",
        ".mp4" => "video/mp4",
        ".mp3" => "audio/mpeg",
      }

      ext = File.extname(file_name).downcase
      mime_types[ext] || "application/octet-stream"
    end
  end
end

