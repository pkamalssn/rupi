# frozen_string_literal: true

# RupiEngine::Client - API client for communicating with rupi-engine
#
# This module handles all communication with the proprietary rupi-engine
# service which contains the bank statement parsers and AI logic.
#
# Usage:
#   result = RupiEngine::Client.parse_statement(file, bank_name: "HDFC", password: "optional")
#   if result.success?
#     transactions = result.transactions
#   else
#     error = result.error_message
#   end
#
module RupiEngine
  class Client
    include HTTParty

    # Configuration
    base_uri ENV.fetch("RUPI_ENGINE_URL", "http://localhost:4000")
    default_timeout 60  # PDF parsing can take time

    # Custom error classes
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class ValidationError < Error; end
    class ServerError < Error; end
    class ConnectionError < Error; end
    class TimeoutError < Error; end

    # Response wrapper for consistent handling
    class Response
      attr_reader :data, :error_type, :error_message, :request_id

      def initialize(success:, data: nil, error_type: nil, error_message: nil, request_id: nil)
        @success = success
        @data = data
        @error_type = error_type
        @error_message = error_message
        @request_id = request_id
      end

      def success?
        @success
      end

      def failure?
        !@success
      end

      def transactions
        @data&.dig("transactions") || []
      end

      def transaction_count
        @data&.dig("transaction_count") || 0
      end
    end

    class << self
      # Parse a bank statement PDF/Excel file
      #
      # @param file [ActionDispatch::Http::UploadedFile, Tempfile] The uploaded file
      # @param bank_name [String] Name of the bank (e.g., "HDFC", "ICICI")
      # @param password [String, nil] Optional password for encrypted PDFs
      # @return [Response] Response object with success/failure and data
      #
      def parse_statement(file, bank_name:, password: nil)
        request_id = generate_request_id

        Rails.logger.tagged("RupiEngine", request_id) do
          Rails.logger.info("Parsing statement for bank: #{bank_name}")

          begin
            # Prepare file for upload
            file_to_upload = prepare_file(file)

            # Build request body
            body = {
              file: file_to_upload,
              bank_name: bank_name
            }
            body[:password] = password if password.present?

            # Make the request
            response = post(
              "/api/v1/parse_statement",
              body: body,
              headers: request_headers(request_id)
            )

            handle_response(response, request_id)

          rescue Net::OpenTimeout, Net::ReadTimeout => e
            Rails.logger.error("Timeout connecting to rupi-engine: #{e.message}")
            Response.new(
              success: false,
              error_type: "timeout",
              error_message: "The parsing service is taking too long to respond. Please try again.",
              request_id: request_id
            )

          rescue Errno::ECONNREFUSED, SocketError => e
            Rails.logger.error("Connection refused to rupi-engine: #{e.message}")
            Response.new(
              success: false,
              error_type: "connection_error",
              error_message: "Unable to connect to the parsing service. Please try again later.",
              request_id: request_id
            )

          rescue => e
            Rails.logger.error("Unexpected error calling rupi-engine: #{e.class} - #{e.message}")
            Rails.logger.error(e.backtrace.first(5).join("\n"))
            Response.new(
              success: false,
              error_type: "internal_error",
              error_message: "An unexpected error occurred. Please try again.",
              request_id: request_id
            )
          end
        end
      end

      # Get list of supported banks
      #
      # @return [Response] Response with list of supported bank codes
      #
      def supported_banks
        request_id = generate_request_id

        begin
          response = get(
            "/api/v1/supported_banks",
            headers: request_headers(request_id)
          )

          handle_response(response, request_id)

        rescue => e
          Rails.logger.error("Error fetching supported banks: #{e.message}")
          Response.new(
            success: false,
            error_type: "connection_error",
            error_message: "Unable to fetch supported banks",
            request_id: request_id
          )
        end
      end

      # Health check for rupi-engine
      #
      # @return [Boolean] true if engine is healthy
      #
      def healthy?
        response = get("/api/v1/health", timeout: 5)
        response.success? && response.parsed_response&.dig("status") == "ok"
      rescue => e
        Rails.logger.warn("rupi-engine health check failed: #{e.message}")
        false
      end

      # =================================================================
      # AI ENDPOINTS - Calls to rupi-engine's proprietary AI services
      # =================================================================
      
      # Categorize transactions using AI (with NEW: category suggestions)
      #
      # @param transactions [Array<Hash>] Array of {id:, description:, amount:, classification:}
      # @param categories [Array<Hash>] Array of {id:, name:, classification:}
      # @return [Response] Response with categorizations array
      #
      def categorize_transactions(transactions:, categories:)
        request_id = generate_request_id
        
        Rails.logger.tagged("RupiEngine", request_id) do
          Rails.logger.info("Categorizing #{transactions.size} transactions")
          
          begin
            response = post(
              "/api/v1/ai/categorize",
              body: {
                transactions: transactions,
                categories: categories
              }.to_json,
              headers: request_headers(request_id).merge("Content-Type" => "application/json")
            )
            
            handle_response(response, request_id)
            
          rescue Net::OpenTimeout, Net::ReadTimeout => e
            Rails.logger.error("Timeout during AI categorization: #{e.message}")
            Response.new(
              success: false,
              error_type: "timeout",
              error_message: "AI categorization is taking too long. Please try again.",
              request_id: request_id
            )
            
          rescue Errno::ECONNREFUSED, SocketError => e
            Rails.logger.error("Connection refused during AI categorization: #{e.message}")
            Response.new(
              success: false,
              error_type: "connection_error",
              error_message: "Unable to connect to AI service. Please try again later.",
              request_id: request_id
            )
          end
        end
      end
      
      # Parse loan document using AI
      #
      # @param file [ActionDispatch::Http::UploadedFile, Tempfile] The loan document PDF
      # @return [Response] Response with loan_data hash
      #
      def parse_loan_document(file)
        request_id = generate_request_id
        
        Rails.logger.tagged("RupiEngine", request_id) do
          Rails.logger.info("Parsing loan document with AI")
          
          begin
            file_to_upload = prepare_file(file)
            
            response = post(
              "/api/v1/ai/parse_loan_document",
              body: { file: file_to_upload },
              headers: request_headers(request_id)
            )
            
            handle_response(response, request_id)
            
          rescue Net::OpenTimeout, Net::ReadTimeout => e
            Rails.logger.error("Timeout during loan document parsing: #{e.message}")
            Response.new(
              success: false,
              error_type: "timeout",
              error_message: "Loan document parsing is taking too long. Please try again.",
              request_id: request_id
            )
            
          rescue Errno::ECONNREFUSED, SocketError => e
            Rails.logger.error("Connection refused during loan parsing: #{e.message}")
            Response.new(
              success: false,
              error_type: "connection_error",
              error_message: "Unable to connect to AI service. Please try again later.",
              request_id: request_id
            )
          end
        end
      end
      
      # AI chat for financial queries
      #
      # @param message [String] User's message
      # @param context [String] Optional context about user's finances
      # @param instructions [String] Optional custom instructions
      # @param chat_history [Array<Hash>] Previous messages [{role:, content:}]
      # @return [Response] Response with AI's reply
      #
      def chat(message:, context: nil, instructions: nil, chat_history: [])
        request_id = generate_request_id
        
        Rails.logger.tagged("RupiEngine", request_id) do
          Rails.logger.info("AI chat request")
          
          begin
            response = post(
              "/api/v1/ai/chat",
              body: {
                message: message,
                context: context,
                instructions: instructions,
                chat_history: chat_history
              }.to_json,
              headers: request_headers(request_id).merge("Content-Type" => "application/json")
            )
            
            handle_response(response, request_id)
            
          rescue Net::OpenTimeout, Net::ReadTimeout => e
            Rails.logger.error("Timeout during AI chat: #{e.message}")
            Response.new(
              success: false,
              error_type: "timeout",
              error_message: "AI is taking too long to respond. Please try again.",
              request_id: request_id
            )
            
          rescue Errno::ECONNREFUSED, SocketError => e
            Rails.logger.error("Connection refused during AI chat: #{e.message}")
            Response.new(
              success: false,
              error_type: "connection_error",
              error_message: "Unable to connect to AI service. Please try again later.",
              request_id: request_id
            )
          end
        end
      end
      
      # Detect merchants from transaction descriptions using AI
      #
      # @param transactions [Array<Hash>] Array of {id:, description:}
      # @param merchants [Array<Hash>] Known merchants [{name:}]
      # @return [Response] Response with merchant mappings
      #
      def detect_merchants(transactions:, merchants: [])
        request_id = generate_request_id
        
        Rails.logger.tagged("RupiEngine", request_id) do
          Rails.logger.info("Detecting merchants for #{transactions.size} transactions")
          
          begin
            response = post(
              "/api/v1/ai/detect_merchants",
              body: {
                transactions: transactions,
                merchants: merchants
              }.to_json,
              headers: request_headers(request_id).merge("Content-Type" => "application/json")
            )
            
            handle_response(response, request_id)
            
          rescue Net::OpenTimeout, Net::ReadTimeout => e
            Rails.logger.error("Timeout during merchant detection: #{e.message}")
            Response.new(
              success: false,
              error_type: "timeout",
              error_message: "Merchant detection is taking too long. Please try again.",
              request_id: request_id
            )
            
          rescue Errno::ECONNREFUSED, SocketError => e
            Rails.logger.error("Connection refused during merchant detection: #{e.message}")
            Response.new(
              success: false,
              error_type: "connection_error",
              error_message: "Unable to connect to AI service. Please try again later.",
              request_id: request_id
            )
          end
        end
      end

      private

      def api_key
        ENV.fetch("RUPI_ENGINE_API_KEY", "")
      end

      def request_headers(request_id = nil)
        headers = {
          "X-Api-Key" => api_key,
          "Accept" => "application/json"
        }
        headers["X-Request-ID"] = request_id if request_id
        headers
      end

      def generate_request_id
        "rupi-v3-#{SecureRandom.uuid}"
      end

      def prepare_file(file)
        if file.respond_to?(:tempfile)
          # ActionDispatch::Http::UploadedFile
          File.open(file.tempfile.path)
        elsif file.respond_to?(:path)
          # Tempfile or File
          File.open(file.path)
        elsif file.respond_to?(:download)
          # ActiveStorage attachment
          temp = Tempfile.new(["statement", ".pdf"])
          temp.binmode
          temp.write(file.download)
          temp.rewind
          temp
        else
          raise ArgumentError, "Unsupported file type: #{file.class}"
        end
      end

      def handle_response(response, request_id)
        case response.code
        when 200
          Response.new(
            success: true,
            data: response.parsed_response,
            request_id: request_id
          )

        when 401
          Rails.logger.error("Authentication failed with rupi-engine")
          Response.new(
            success: false,
            error_type: "unauthorized",
            error_message: "Authentication failed with parsing service",
            request_id: request_id
          )

        when 422
          # Validation error (password required, parse error, etc.)
          parsed = response.parsed_response || {}
          Response.new(
            success: false,
            error_type: parsed["error"] || "validation_error",
            error_message: parsed["message"] || "Failed to parse the statement",
            request_id: request_id
          )

        when 500..599
          Rails.logger.error("rupi-engine server error: #{response.code}")
          Response.new(
            success: false,
            error_type: "server_error",
            error_message: "The parsing service encountered an error. Please try again.",
            request_id: request_id
          )

        else
          Rails.logger.warn("Unexpected response from rupi-engine: #{response.code}")
          Response.new(
            success: false,
            error_type: "unknown_error",
            error_message: "Received unexpected response from parsing service",
            request_id: request_id
          )
        end
      end
    end
  end
end
