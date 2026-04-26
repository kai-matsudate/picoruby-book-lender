require "test_helper"

class SanityTest < Minitest::Test
  def test_version_is_defined
    assert_kind_of String, PN532::VERSION
  end
end
