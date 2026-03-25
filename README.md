# DragDropDo Ruby SDK

Official Ruby client library for the D3 Business API. This library provides a simple and elegant interface for developers to interact with D3's file processing services.

## Features

- ✅ **File Upload** - Upload files with automatic multipart handling
- ✅ **Operation Support** - Check which operations are available for file types
- ✅ **File Operations** - Convert, compress, merge, zip, and more
- ✅ **Status Polling** - Built-in polling for operation status
- ✅ **Error Handling** - Comprehensive error types and messages
- ✅ **Progress Tracking** - Upload progress callbacks

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'dragdropdo-sdk'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install dragdropdo-sdk
```

## Quick Start

```ruby
require 'dragdropdo_sdk'

# Initialize the client
client = D3RubyClient::Dragdropdo.new(
  api_key: 'your-api-key-here',
  base_url: 'https://api.d3.com', # Optional, defaults to https://api.d3.com
  timeout: 30000 # Optional, defaults to 30000ms
)

# Upload a file
upload_result = client.upload_file(
  file: '/path/to/document.pdf',
  file_name: 'document.pdf',
  mime_type: 'application/pdf'
)

puts "File key: #{upload_result[:file_key]}"

# Check if convert to PNG is supported
supported = client.check_supported_operation(
  ext: 'pdf',
  action: 'convert',
  parameters: { convert_to: 'png' }
)

if supported[:supported]
  # Convert PDF to PNG
  operation = client.convert(
    file_keys: [upload_result[:file_key]],
    convert_to: 'png'
  )

  # Poll for completion
  status = client.poll_status(
    main_task_id: operation[:main_task_id],
    interval: 2000, # Check every 2 seconds
    on_update: ->(status) { puts "Status: #{status[:operation_status]}" }
  )

  if status[:operation_status] == 'completed'
    puts "Download links:"
    status[:files_data].each do |file|
      puts "  #{file[:download_link]}"
    end
  end
end
```

## API Reference

### Initialization

#### `D3RubyClient::Dragdropdo.new(api_key:, base_url: nil, timeout: 30000, headers: {})`

Create a new D3 client instance.

**Parameters:**

- `api_key` (required) - Your D3 API key
- `base_url` (optional) - Base URL of the D3 API (default: `'https://api.d3.com'`)
- `timeout` (optional) - Request timeout in milliseconds (default: `30000`)
- `headers` (optional) - Custom headers to include in all requests

**Example:**

```ruby
client = D3RubyClient::Dragdropdo.new(
  api_key: 'your-api-key',
  base_url: 'https://api.d3.com',
  timeout: 30000
)
```

---

### File Upload

#### `upload_file(file:, file_name:, mime_type: nil, parts: nil, on_progress: nil)`

Upload a file to D3 storage. This method handles the complete upload flow including multipart uploads.

**Parameters:**

- `file` (required) - File path (string)
- `file_name` (required) - Original file name
- `mime_type` (optional) - MIME type (auto-detected if not provided)
- `parts` (optional) - Number of parts for multipart upload (auto-calculated if not provided)
- `on_progress` (optional) - Progress callback (Proc)

**Returns:** Hash with `file_key` and `presigned_urls`

**Example:**

```ruby
result = client.upload_file(
  file: '/path/to/file.pdf',
  file_name: 'document.pdf',
  mime_type: 'application/pdf',
  on_progress: ->(progress) { puts "Upload: #{progress[:percentage]}%" }
)
```

---

### Check Supported Operations

#### `check_supported_operation(ext:, action: nil, parameters: nil)`

Check which operations are supported for a file extension.

**Parameters:**

- `ext` (required) - File extension (e.g., `'pdf'`, `'jpg'`)
- `action` (optional) - Specific action to check (e.g., `'convert'`, `'compress'`)
- `parameters` (optional) - Parameters for validation (e.g., `{ convert_to: 'png' }`)

**Returns:** Hash with support information

**Example:**

```ruby
# Get all available actions for PDF
result = client.check_supported_operation(ext: 'pdf')
puts "Available actions: #{result[:available_actions]}"

# Check if convert to PNG is supported
result = client.check_supported_operation(
  ext: 'pdf',
  action: 'convert',
  parameters: { convert_to: 'png' }
)
puts "Supported: #{result[:supported]}"
```

---

### Create Operations

#### `create_operation(action:, file_keys:, parameters: nil, notes: nil)`

Create a file operation (convert, compress, merge, zip, etc.).

**Parameters:**

- `action` (required) - Action to perform: `'convert'`, `'compress'`, `'merge'`, `'zip'`, `'lock'`, `'unlock'`, `'reset_password'`
- `file_keys` (required) - Array of file keys from upload
- `parameters` (optional) - Action-specific parameters
- `notes` (optional) - User metadata

**Returns:** Hash with `main_task_id`

**Example:**

```ruby
# Convert PDF to PNG
result = client.create_operation(
  action: 'convert',
  file_keys: ['file-key-123'],
  parameters: { convert_to: 'png' },
  notes: { userId: 'user-123' }
)
```

#### Convenience Methods

The client also provides convenience methods for common operations:

**Convert:**

```ruby
client.convert(file_keys: ['file-key-123'], convert_to: 'png')
```

**Compress:**

```ruby
client.compress(file_keys: ['file-key-123'], compression_value: 'recommended')
```

**Merge:**

```ruby
client.merge(file_keys: ['file-key-1', 'file-key-2'])
```

**Zip:**

```ruby
client.zip(file_keys: ['file-key-1', 'file-key-2'])
```

**Lock PDF:**

```ruby
client.lock_pdf(file_keys: ['file-key-123'], password: 'secure-password')
```

**Unlock PDF:**

```ruby
client.unlock_pdf(file_keys: ['file-key-123'], password: 'password')
```

**Reset PDF Password:**

```ruby
client.reset_pdf_password(
  file_keys: ['file-key-123'],
  old_password: 'old',
  new_password: 'new'
)
```

---

### Get Status

#### `get_status(main_task_id:, file_key: nil)`

Get the current status of an operation.

**Parameters:**

- `main_task_id` (required) - Main task ID from operation creation
- `file_key` (optional) - Input file key for specific file status

**Returns:** Hash with operation and file statuses

**Example:**

```ruby
# Get main task status
status = client.get_status(main_task_id: 'task-123')

# Get specific file status by file key
status = client.get_status(
  main_task_id: 'task-123',
  file_key: 'file-key-456'
)

puts "Operation status: #{status[:operation_status]}"
# Possible values: 'queued', 'running', 'completed', 'failed'
```

#### `poll_status(main_task_id:, file_key: nil, interval: 2000, timeout: 300000, on_update: nil)`

Poll operation status until completion or failure.

**Parameters:**

- `main_task_id` (required) - Main task ID
- `file_key` (optional) - Input file key for specific file status
- `interval` (optional) - Polling interval in milliseconds (default: `2000`)
- `timeout` (optional) - Maximum polling duration in milliseconds (default: `300000` = 5 minutes)
- `on_update` (optional) - Callback for each status update

**Returns:** Hash with final status

**Example:**

```ruby
status = client.poll_status(
  main_task_id: 'task-123',
  interval: 2000,
  timeout: 300000,
  on_update: ->(status) { puts "Status: #{status[:operation_status]}" }
)

if status[:operation_status] == 'completed'
  puts "All files processed successfully!"
  status[:files_data].each do |file|
    puts "Download: #{file[:download_link]}"
  end
end
```

---

## Complete Workflow Example

Here's a complete example showing the typical workflow:

```ruby
require 'dragdropdo_sdk'

def process_file
  # Initialize client
  client = D3RubyClient::Dragdropdo.new(
    api_key: ENV['D3_API_KEY'],
    base_url: 'https://api.d3.com'
  )

  begin
    # Step 1: Upload file
    puts "Uploading file..."
    upload_result = client.upload_file(
      file: './document.pdf',
      file_name: 'document.pdf',
      on_progress: ->(progress) { puts "Upload progress: #{progress[:percentage]}%" }
    )
    puts "Upload complete. File key: #{upload_result[:file_key]}"

    # Step 2: Check if operation is supported
    puts "Checking supported operations..."
    supported = client.check_supported_operation(
      ext: 'pdf',
      action: 'convert',
      parameters: { convert_to: 'png' }
    )

    unless supported[:supported]
      raise "Convert to PNG is not supported for PDF"
    end

    # Step 3: Create operation
    puts "Creating convert operation..."
    operation = client.convert(
      file_keys: [upload_result[:file_key]],
      convert_to: 'png',
      notes: { userId: 'user-123', source: 'api' }
    )
    puts "Operation created. Task ID: #{operation[:main_task_id]}"

    # Step 4: Poll for completion
    puts "Waiting for operation to complete..."
    status = client.poll_status(
      main_task_id: operation[:main_task_id],
      interval: 2000,
      on_update: ->(status) { puts "Status: #{status[:operation_status]}" }
    )

    # Step 5: Handle result
    if status[:operation_status] == 'completed'
      puts "Operation completed successfully!"
      status[:files_data].each_with_index do |file, index|
        puts "File #{index + 1}:"
        puts "  Status: #{file[:status]}"
        puts "  Download: #{file[:download_link]}"
      end
    else
      puts "Operation failed"
      status[:files_data].each do |file|
        puts "Error: #{file[:error_message]}" if file[:error_message]
      end
    end
  rescue D3RubyClient::D3APIError => e
    puts "API Error (#{e.status_code}): #{e.message}"
  rescue D3RubyClient::D3ValidationError => e
    puts "Validation Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end

process_file
```

---

## Error Handling

The client provides several error types for better error handling:

```ruby
begin
  client.upload_file(...)
rescue D3RubyClient::D3APIError => e
  # API returned an error
  puts "API Error (#{e.status_code}): #{e.message}"
  puts "Error code: #{e.code}"
  puts "Details: #{e.details}"
rescue D3RubyClient::D3ValidationError => e
  # Validation error (missing required fields, etc.)
  puts "Validation Error: #{e.message}"
rescue D3RubyClient::D3UploadError => e
  # Upload-specific error
  puts "Upload Error: #{e.message}"
rescue D3RubyClient::D3TimeoutError => e
  # Timeout error (from polling)
  puts "Timeout: #{e.message}"
rescue StandardError => e
  # Other errors
  puts "Error: #{e.message}"
end
```

---

## Requirements

- Ruby 2.7.0 or higher

---

## License

ISC

---

## Support

For API documentation and support, visit [D3 Developer Portal](https://developer.d3.com).
