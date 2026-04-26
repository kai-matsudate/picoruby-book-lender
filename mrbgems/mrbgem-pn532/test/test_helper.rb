$LOAD_PATH.unshift File.expand_path("../src", __dir__)
$LOAD_PATH.unshift File.expand_path(".", __dir__)

require "minitest/autorun"
require "pn532"
