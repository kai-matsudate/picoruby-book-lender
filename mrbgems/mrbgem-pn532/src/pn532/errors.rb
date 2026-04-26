class PN532
  class Error < StandardError; end
  class TimeoutError    < Error; end
  class ChecksumError   < Error; end
  class ProtocolError   < Error; end
end
