# frozen_string_literal: true

# Base class for bank statement parsers
# Subclasses implement bank-specific parsing logic
module BankStatementParser
  class ParseError < StandardError; end
  class UnsupportedFormatError < StandardError; end
  class PasswordRequiredError < StandardError; end
  class OCRError < StandardError; end

  class Base
    attr_reader :file, :password, :metadata

    def initialize(file, password: nil)
      @file = file
      @password = password
      @metadata = {}
    end

    # Parse the statement and return an array of transaction hashes
    # Each hash should contain: date, amount, description, notes (optional)
    def parse
      raise NotImplementedError, "Subclass must implement #parse"
    end

    # Detect if file is password protected
    def password_protected?
      return false unless pdf_file?
      
      reader = PDF::Reader.new(file_path)
      false
    rescue PDF::Reader::EncryptedPDFError
      true
    rescue => e
      Rails.logger.warn("Error checking password protection: #{e.message}")
      false
    end

    # Check if PDF is scanned (no extractable text)
    def scanned_pdf?
      return false unless pdf_file?
      
      text = extract_text_from_pdf
      text.strip.length < 100 # If very little text, likely scanned
    rescue => e
      Rails.logger.warn("Error checking if PDF is scanned: #{e.message}")
      false
    end

    protected

    def file_path
      if file.respond_to?(:path)
        file.path
      elsif file.respond_to?(:download)
        # ActiveStorage - download to tempfile
        @temp_file ||= begin
          temp = Tempfile.new(['statement', file_extension])
          temp.binmode
          temp.write(file.download)
          temp.rewind
          temp
        end
        @temp_file.path
      else
        file.to_s
      end
    end

    def file_extension
      if file.respond_to?(:filename)
        ".#{file.filename.extension}"
      elsif file.respond_to?(:content_type)
        case file.content_type
        when /pdf/ then ".pdf"
        when /excel|spreadsheet/ then ".xlsx"
        when /csv/ then ".csv"
        else ".tmp"
        end
      else
        ".tmp"
      end
    end

    def pdf_file?
      return true if file.respond_to?(:content_type) && file.content_type&.include?("pdf")
      return true if file.respond_to?(:filename) && file.filename.to_s.end_with?(".pdf")
      return true if file.respond_to?(:path) && file.path.to_s.end_with?(".pdf")
      false
    end

    # Extract text from PDF, handling password protection
    def extract_text_from_pdf
      require "pdf-reader"
      
      reader = begin
        PDF::Reader.new(file_path)
      rescue PDF::Reader::EncryptedPDFError
        raise PasswordRequiredError, "Password required for this PDF" if password.blank?
        # Try with hexapdf for password decryption
        decrypt_pdf_and_extract_text
      end
      
      text = ""
      reader.pages.each do |page|
        text += page.text + "\n"
      end
      text
    end

    # Decrypt password-protected PDF using hexapdf and extract text
    def decrypt_pdf_and_extract_text
      require "hexapdf"
      
      Rails.logger.info("Decrypting PDF with password: #{password.present? ? 'provided' : 'MISSING!'}")
      
      raise PasswordRequiredError, "Password is required for encrypted PDF" if password.blank?
      
      begin
        # Open and decrypt with HexaPDF
        doc = HexaPDF::Document.open(file_path, decryption_opts: { password: password })
        
        Rails.logger.info("PDF opened with HexaPDF, extracting text from #{doc.pages.count} pages...")
        
        # Extract text directly from HexaPDF document
        text = ""
        doc.pages.each_with_index do |page, idx|
          begin
            page_text = page.text rescue ""
            text += page_text + "\n"
          rescue => e
            Rails.logger.warn("Failed to extract text from page #{idx}: #{e.message}")
          end
        end
        
        # If HexaPDF text extraction fails, try alternate method
        if text.strip.length < 100
          Rails.logger.info("HexaPDF text extraction minimal, trying alternate method...")
          
          # Write decrypted PDF without encryption
          decrypted_file = Tempfile.new(['decrypted', '.pdf'], binmode: true)
          begin
            # Decrypt and remove encryption
            doc.encrypt(name: nil)  # Remove encryption
            doc.write(decrypted_file.path)
            decrypted_file.close
            
            Rails.logger.info("Wrote unencrypted PDF to #{decrypted_file.path}")
            
            # Try pdf-reader on the truly decrypted file
            reader = PDF::Reader.new(decrypted_file.path)
            text = ""
            reader.pages.each { |page| text += page.text + "\n" }
          rescue => e
            Rails.logger.error("Alternate extraction failed: #{e.message}")
          ensure
            decrypted_file.unlink rescue nil
          end
        end
        
        Rails.logger.info("Extracted #{text.length} characters from decrypted PDF")
        text
        
      rescue HexaPDF::EncryptionError => e
        Rails.logger.error("HexaPDF decryption failed: #{e.message}")
        raise PasswordRequiredError, "Invalid password or unsupported encryption: #{e.message}"
      rescue => e
        Rails.logger.error("PDF decryption/extraction failed: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        raise
      end
    end

    # OCR for scanned PDFs
    def extract_text_with_ocr
      require "mini_magick"
      require "rtesseract"
      
      # Convert PDF pages to images and OCR each
      images = convert_pdf_to_images
      
      text = ""
      images.each_with_index do |image_path, idx|
        begin
          result = RTesseract.new(image_path, lang: "eng").to_s
          text += result + "\n"
        rescue => e
          Rails.logger.error("OCR failed for page #{idx + 1}: #{e.message}")
        ensure
          File.delete(image_path) if File.exist?(image_path)
        end
      end
      
      raise OCRError, "OCR produced no text" if text.strip.empty?
      text
    end

    def convert_pdf_to_images
      require "mini_magick"
      
      images = []
      pdf = MiniMagick::Image.open(file_path)
      
      # Get page count
      page_count = pdf.pages.count rescue 1
      
      (0...page_count).each do |page_num|
        output_path = Tempfile.new(["page_#{page_num}", ".png"]).path
        
        MiniMagick::Tool::Convert.new do |convert|
          convert.density(300)
          convert << "#{file_path}[#{page_num}]"
          convert.quality(100)
          convert << output_path
        end
        
        images << output_path
      end
      
      images
    rescue => e
      Rails.logger.error("Failed to convert PDF to images: #{e.message}")
      []
    end

    # Parse date with multiple Indian formats
    def parse_date(date_str)
      return nil if date_str.blank?

      date_str = date_str.to_s.strip

      # Try various Indian date formats
      formats = [
        "%d/%m/%Y",     # 25/12/2024
        "%d-%m-%Y",     # 25-12-2024
        "%d/%m/%y",     # 25/12/24
        "%d-%m-%y",     # 25-12-24
        "%Y-%m-%d",     # 2024-12-25 (ISO)
        "%d %b %Y",     # 25 Dec 2024
        "%d-%b-%Y",     # 25-Dec-2024
        "%d-%b-%y",     # 25-Dec-24
        "%d %B %Y",     # 25 December 2024
        "%d/%b/%Y",     # 25/Dec/2024
        "%b %d, %Y",    # Dec 25, 2024
        "%d.%m.%Y",     # 25.12.2024
        "%d.%m.%y",     # 25.12.24
      ]

      parsed_date = nil
      formats.each do |format|
        begin
          parsed_date = Date.strptime(date_str, format)
          break
        rescue Date::Error, ArgumentError
          next
        end
      end

      # Try parsing with Date.parse as fallback
      if parsed_date.nil?
        begin
          parsed_date = Date.parse(date_str)
        rescue
          return nil
        end
      end

      # Fix 2-digit year issue: years < 100 should be in 2000s for 00-50, 1900s for 51-99
      if parsed_date && parsed_date.year < 100
        if parsed_date.year <= 50
          parsed_date = Date.new(2000 + parsed_date.year, parsed_date.month, parsed_date.day)
        else
          parsed_date = Date.new(1900 + parsed_date.year, parsed_date.month, parsed_date.day)
        end
      end

      parsed_date
    end

    def parse_amount(amount_str)
      return nil if amount_str.blank?

      # Remove common formatting characters
      cleaned = amount_str.to_s.strip
      cleaned = cleaned.gsub(/[,\s₹]/, "")
      cleaned = cleaned.gsub(/^Rs\.?/i, "").gsub(/^INR/i, "").strip
      cleaned = cleaned.gsub(/\(\)/, "")  # Remove empty parens

      # Handle negative amounts in parentheses: (1000.00)
      is_negative = cleaned.start_with?("(") && cleaned.end_with?(")")
      cleaned = cleaned.gsub(/[()]/, "") if is_negative

      # Handle debit/credit indicators
      if cleaned.downcase.match?(/\b(dr|debit)\b/)
        is_negative = true
        cleaned = cleaned.gsub(/\b(dr|debit)\b/i, "").strip
      elsif cleaned.downcase.match?(/\b(cr|credit)\b/)
        is_negative = false
        cleaned = cleaned.gsub(/\b(cr|credit)\b/i, "").strip
      end

      # Remove any remaining non-numeric characters except decimal point
      cleaned = cleaned.gsub(/[^\d.]/, "")
      
      return nil if cleaned.empty?

      amount = BigDecimal(cleaned)
      is_negative ? -amount : amount
    rescue ArgumentError, TypeError
      nil
    end

    def clean_description(description)
      return "" if description.blank?

      description.to_s
        .gsub(/\s+/, " ")  # Normalize whitespace
        .gsub(/[^\w\s\-@.\/]/, "")  # Remove special chars except common ones
        .strip
        .truncate(200)
    end
  end
end
