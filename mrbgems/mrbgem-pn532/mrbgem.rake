MRuby::Gem::Specification.new("mrbgem-pn532") do |spec|
  spec.license = "MIT"
  spec.author  = "Kai Matsudate"
  spec.summary = "PN532 NFC reader driver for PicoRuby/mruby (FeliCa IDm / MIFARE Type A UID)"

  spec.add_dependency "picoruby-i2c", core: "picoruby-i2c"

  spec.rbfiles = [
    "#{dir}/src/pn532/errors.rb",
    "#{dir}/src/pn532/frame.rb",
    "#{dir}/src/pn532.rb",
  ]
end
