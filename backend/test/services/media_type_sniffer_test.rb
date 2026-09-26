require "test_helper"

class MediaTypeSnifferTest < ActiveSupport::TestCase
  test "identifies allowed formats from leading bytes only" do
    {
      "\x89PNG\r\n\x1A\n\x00\x00" => "image/png",
      "\xFF\xD8\xFF\xE0\x00\x10JFIF" => "image/jpeg",
      "RIFF\x00\x00\x00\x00WEBPVP8 " => "image/webp",
      "RIFF\x00\x00\x00\x00WAVEfmt " => "audio/wav",
      "%PDF-1.4\n" => "application/pdf",
      "\x00\x00\x00\x18ftypmp42\x00\x00" => "video/mp4",
      "ID3\x03\x00\x00\x00\x00" => "audio/mpeg",
      "\xFF\xFB\x90\x64\x00" => "audio/mpeg"
    }.each { |bytes, type| assert_equal type, MediaTypeSniffer.detect(bytes.b), type }
  end

  test "rejects markup, scripts, unknown binaries and invalid MPEG frames" do
    ["<html>", "<svg onload=alert(1)>", "MZ\x90\x00", "PK\x03\x04", "\xFF\xFF\xFF\xFF", "", "RIFF\x00\x00\x00\x00AVI "].each do |bytes|
      assert_nil MediaTypeSniffer.detect(bytes.b), bytes.inspect
    end
  end

  test "normalizes browser aliases" do
    assert_equal "audio/wav", MediaTypeSniffer.canonical("audio/x-wav")
    assert_equal "audio/mpeg", MediaTypeSniffer.canonical("Audio/MP3; charset=binary")
    assert_equal "image/jpeg", MediaTypeSniffer.canonical("image/jpg")
    assert_not MediaTypeSniffer.allowed?("image/svg+xml")
  end
end
