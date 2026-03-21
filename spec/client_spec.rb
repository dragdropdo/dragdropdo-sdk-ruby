require "spec_helper"
require "tempfile"
require "webmock/rspec"

RSpec.describe D3RubyClient::Dragdropdo do
  API_BASE = "https://api-dev.dragdropdo.com"

  let(:client) do
    D3RubyClient::Dragdropdo.new(
      api_key: "test-key",
      base_url: API_BASE,
      timeout: 30_000
    )
  end

  describe "#initialize" do
    it "raises error when API key is missing" do
      expect do
        D3RubyClient::Dragdropdo.new(api_key: "")
      end.to raise_error(D3RubyClient::D3ValidationError, "API key is required")
    end

    it "creates a valid client with API key" do
      expect(client).not_to be_nil
      expect(client.api_key).to eq("test-key")
    end
  end

  describe "#upload_file" do
    let(:temp_file) do
      file = Tempfile.new(["d3-test", ".pdf"])
      file.write("a" * (6 * 1024 * 1024)) # 6MB
      file.rewind
      file.path
    end

    after do
      File.unlink(temp_file) if File.exist?(temp_file)
    end

    it "uploads a file with multipart flow" do
      # Mock presigned URL request
      stub_request(:post, "#{API_BASE}/api/v1/initiate-upload")
        .to_return(
          status: 200,
          body: {
            data: {
              file_key: "file-key-123",
              upload_id: "upload-id-456",
              presigned_urls: [
                "https://upload.d3.com/part1",
                "https://upload.d3.com/part2"
              ]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Mock part uploads
      stub_request(:put, "https://upload.d3.com/part1")
        .to_return(status: 200, headers: { "ETag" => '"etag-part-1"' })
      stub_request(:put, "https://upload.d3.com/part2")
        .to_return(status: 200, headers: { "ETag" => '"etag-part-2"' })

      # Mock complete upload
      stub_request(:post, "#{API_BASE}/api/v1/complete-upload")
        .to_return(
          status: 200,
          body: {
            data: {
              message: "Upload completed successfully",
              file_key: "file-key-123"
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.upload_file(
        file: temp_file,
        file_name: "test.pdf",
        mime_type: "application/pdf",
        parts: 2
      )

      expect(result[:file_key]).to eq("file-key-123")
      expect(result[:upload_id]).to eq("upload-id-456")
      expect(result[:presigned_urls].length).to eq(2)
    end
  end

  describe "#convert and #poll_status" do
    it "creates an operation and polls status to completion" do
      # Mock create operation
      stub_request(:post, "#{API_BASE}/api/v1/do")
        .to_return(
          status: 200,
          body: {
            data: {
              main_task_id: "task-123"
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Mock status calls (queued then completed) - need multiple responses for polling
      # First call: queued
      stub_request(:get, "#{API_BASE}/api/v1/status/task-123")
        .to_return(
          status: 200,
          body: {
            data: {
              operation_status: "queued",
              files_data: [
                { file_key: "file-key-123", status: "queued" }
              ]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      
      # Second call: completed (after polling interval)
      stub_request(:get, "#{API_BASE}/api/v1/status/task-123")
        .to_return(
          status: 200,
          body: {
            data: {
              operation_status: "completed",
              files_data: [
                {
                  file_key: "file-key-123",
                  status: "completed",
                  download_link: "https://files.d3.com/output.png"
                }
              ]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      
      # Additional calls: also return completed (in case of extra polls)
      stub_request(:get, "#{API_BASE}/api/v1/status/task-123")
        .to_return(
          status: 200,
          body: {
            data: {
              operation_status: "completed",
              files_data: [
                {
                  file_key: "file-key-123",
                  status: "completed",
                  download_link: "https://files.d3.com/output.png"
                }
              ]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Create operation
      operation = client.convert(file_keys: ["file-key-123"], convert_to: "png")
      expect(operation[:main_task_id]).to eq("task-123")

      # Poll status
      status = client.poll_status(
        main_task_id: operation[:main_task_id],
        interval: 10, # 10ms
        timeout: 5000 # 5 seconds (in milliseconds)
      )

      expect(status[:operation_status]).to eq("completed")
      expect(status[:files_data].length).to be > 0
      expect(status[:files_data][0][:download_link]).to include("files.d3.com")
    end
  end

  describe "#check_supported_operation" do
    it "checks if an operation is supported" do
      stub_request(:post, "#{API_BASE}/api/v1/supported-operation")
        .to_return(
          status: 200,
          body: {
            data: {
              supported: true,
              ext: "pdf",
              available_actions: ["convert", "compress", "merge"]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.check_supported_operation(ext: "pdf")

      expect(result[:supported]).to be true
      expect(result[:ext]).to eq("pdf")
      expect(result[:available_actions]).to include("convert")
    end
  end

  describe "#convert" do
    it "creates a convert operation" do
      stub_request(:post, "#{API_BASE}/api/v1/do")
        .with(
          body: hash_including(
            action: "convert",
            file_keys: ["file-key-123"],
            parameters: { convert_to: "png" }
          )
        )
        .to_return(
          status: 200,
          body: {
            data: {
              main_task_id: "task-123"
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.convert(file_keys: ["file-key-123"], convert_to: "png")
      expect(result[:main_task_id]).to eq("task-123")
    end
  end

  describe "#compress" do
    it "creates a compress operation" do
      stub_request(:post, "#{API_BASE}/api/v1/do")
        .with(
          body: hash_including(
            action: "compress",
            parameters: { compression_value: "recommended" }
          )
        )
        .to_return(
          status: 200,
          body: {
            data: {
              main_task_id: "task-456"
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.compress(file_keys: ["file-key-123"], compression_value: "recommended")
      expect(result[:main_task_id]).to eq("task-456")
    end
  end
end

