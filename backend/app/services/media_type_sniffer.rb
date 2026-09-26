# Identifies an upload from its leading bytes only. The declared (client) type and the
# filename are never consulted, so a renamed HTML/SVG/executable is rejected.
module MediaTypeSniffer
  HEADER_BYTES = 16

  # Canonical types the platform stores, and the aliases browsers send for them.
  ALLOWED_TYPES = %w[audio/mpeg audio/wav video/mp4 image/jpeg image/png image/webp application/pdf].freeze
  ALIASES = {
    "audio/mp3" => "audio/mpeg", "audio/x-wav" => "audio/wav", "audio/wave" => "audio/wav",
    "audio/vnd.wave" => "audio/wav", "image/jpg" => "image/jpeg", "image/pjpeg" => "image/jpeg"
  }.freeze

  module_function

  def canonical(type)
    value = type.to_s.split(";").first.to_s.strip.downcase
    ALIASES.fetch(value, value)
  end

  def allowed?(type) = ALLOWED_TYPES.include?(canonical(type))

  # Returns the canonical MIME type for the header bytes, or nil when they match none
  # of the allowed formats.
  def detect(header)
    bytes = header.to_s.b
    return "image/png" if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
    return "image/jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
    return "application/pdf" if bytes.start_with?("%PDF-".b)
    if bytes.start_with?("RIFF".b) && bytes.bytesize >= 12
      return "image/webp" if bytes[8, 4] == "WEBP".b
      return "audio/wav" if bytes[8, 4] == "WAVE".b
    end
    return "video/mp4" if bytes.bytesize >= 12 && bytes[4, 4] == "ftyp".b
    return "audio/mpeg" if bytes.start_with?("ID3".b) || mpeg_audio_frame?(bytes)
    nil
  end

  # MPEG audio frame header: 11 sync bits, a defined version and layer, and a bitrate
  # index that is neither "free" nor "bad".
  def mpeg_audio_frame?(bytes)
    return false if bytes.bytesize < 3
    b0, b1, b2 = bytes.getbyte(0), bytes.getbyte(1), bytes.getbyte(2)
    b0 == 0xFF && (b1 & 0xE0) == 0xE0 && (b1 & 0x18) != 0x08 && (b1 & 0x06) != 0 && (b2 >> 4) != 0x0F && (b2 >> 4) != 0
  end
end
