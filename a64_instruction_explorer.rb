#!/usr/bin/ruby

# SPDX-License-Identifier: MIT-0

require 'rexml/document'
require 'json'

module A64InstructionExplorer
  INSTR_SET_DATA = {
    base:   { name: 'Base',    file: 'index.xml' },
    simdfp: { name: 'SIMD&FP', file: 'fpsimdindex.xml' },
    sve:    { name: 'SVE',     file: 'sveindex.xml' },
    sme:    { name: 'SME',     file: 'mortlachindex.xml' },
  }

  INSTR_CLASS_FEATURE_MAP = {
    'general'   => nil,
    'system'    => nil,
    'float'     => 'FEAT_FP',
    'fpsimd'    => 'FEAT_FP',
    'advsimd'   => 'FEAT_AdvSIMD',
    'sve'       => 'FEAT_SVE',
    'sve2'      => 'FEAT_SVE2',
    'mortlach'  => 'FEAT_SME',
    'mortlach2' => 'FEAT_SME2',
  }

  module XMLElement
    def each_xpath(xpath)
      if block_given?
        REXML::XPath.each(@xml_elem, xpath) { |node| yield(node) }
      else
        Enumerator.new do |yielder|
          REXML::XPath.each(@xml_elem, xpath) { |node| yielder << node }
        end
      end
    end

    def elem_text(xpath)
      elem = REXML::XPath.first(@xml_elem, xpath)
      elem ? elem.text : nil
    end

    def attr_value(xpath)
      attr = REXML::XPath.first(@xml_elem, xpath)
      attr ? attr.value : nil
    end

    def docvar_hash
      docvars = {}
      REXML::XPath.each(@xml_elem, 'docvars/docvar') do |e|
        docvars[e.attribute('key').value.to_sym] = e.attribute('value').value
      end
      docvars
    end
  end

  class ArchVariant
    attr_reader :name, :feature

    def self.parse(xml_elem)
      arch_variants = []
      REXML::XPath.each(xml_elem, 'arch_variants/arch_variant') do |e|
        name_attr = e.attribute('name')
        feature_attr = e.attribute('feature')
        name_value = name_attr ? name_attr.value : nil
        feature_value = feature_attr ? feature_attr.value : nil
        arch_variants << ArchVariant.new(name_value, feature_value)
      end
      arch_variants
    end

    def initialize(name, feature)
      @name = name
      @feature = feature
    end
  end

  class InstructionEncoding
    include XMLElement

    attr_reader :xml_elem, :instr_class, :docvars
    attr_reader :name, :iclass, :mnemonic, :alias_mnemonic, :asmtemplate
    attr_reader :arch_variants, :features

    def initialize(xml_elem, instr_class)
      @xml_elem = xml_elem
      @instr_class = instr_class
      @instr_class.instr_encodings << self
      @docvars = docvar_hash
      @name = attr_value('@name')
      @iclass = @docvars['instr-class'.to_sym]
      @mnemonic = @docvars[:mnemonic]
      @alias_mnemonic = @docvars[:alias_mnemonic]
      @asmtemplate =
        each_xpath('asmtemplate//text()').collect { |t| t.value }.join
      @arch_variants = ArchVariant.parse(xml_elem)
      @features = @arch_variants.collect { |v| v.feature }
      if @features.empty?
        @features = @instr_class.arch_variants.collect { |v| v.feature }
      end
      if @features.empty? && @iclass
        @features = [INSTR_CLASS_FEATURE_MAP[@iclass]]
      end
      if @features.empty? && @instr_class.iclass
        @features = [INSTR_CLASS_FEATURE_MAP[@instr_class.iclass]]
      end
    end

    def instr_section
      @instr_class.instr_section
    end

    def instr_set
      @instr_class.instr_section.instr_set
    end
  end

  class InstructionClass
    include XMLElement

    attr_reader :xml_elem, :instr_section, :instr_encodings, :docvars
    attr_reader :id, :name, :iclass, :arch_variants

    def initialize(xml_elem, instr_section)
      @xml_elem = xml_elem
      @instr_section = instr_section
      @instr_section.instr_classes << self
      @instr_encodings = []
      @docvars = docvar_hash
      @id = attr_value('@id')
      @name = attr_value('@name')
      @iclass = @docvars['instr-class'.to_sym]
      @arch_variants = ArchVariant.parse(xml_elem)
    end

    def instr_set
      @instr_section.instr_set
    end
  end

  class InstructionSection
    include XMLElement

    attr_reader :xml_elem, :instr_set, :instr_classes, :docvars
    attr_reader :section_file, :id, :title, :heading, :brief

    def initialize(xml_elem, section_file, instr_set)
      @xml_elem = xml_elem
      @section_file = section_file
      @instr_set = instr_set
      @instr_set.instr_sections << self
      @instr_classes = []
      @docvars = docvar_hash
      @id = attr_value('@id')
      @title = attr_value('@title')
      @heading = elem_text('heading')
      @brief = elem_text('desc/brief/para') || elem_text('desc/brief')
    end
  end

  class InstructionSet
    include XMLElement

    attr_reader :xml_elem, :instr_sections
    attr_reader :id, :name, :index_file

    def initialize(xml_elem, id)
      @xml_elem = xml_elem
      @instr_sections = []
      @id = id
      @name = INSTR_SET_DATA[id][:name]
      @index_file = INSTR_SET_DATA[id][:file]
    end
  end

  class XMLLoader
    INSTR_SET_IDS = INSTR_SET_DATA.keys

    def load_instruction_section(xml_file, stop_at = :encoding, instr_set = nil,
                                 &block)
      @stop_at = stop_at
      @user_block = block

      if ! instr_set
        instr_set = InstructionSet.new(nil, '-', '-', '-')
      end

      section_xml = File.open(xml_file) { |io| io.read }
      section_doc = REXML::Document.new(section_xml)
      instr_section = InstructionSection.new(section_doc.root,
                                             File.basename(xml_file), instr_set)
      enumerator = instr_section.each_xpath('classes/iclass')
      process(instr_section, :section, enumerator, instr_set.instr_sections) \
        do |iclass_elem|
        instr_class = InstructionClass.new(iclass_elem, instr_section)
        enumerator = instr_class.each_xpath('encoding')
        process(instr_class, :class, enumerator, instr_section.instr_classes) \
          do |encoding_elem|
          instr_encoding = InstructionEncoding.new(encoding_elem, instr_class)
          if ! instr_encoding.mnemonic
            instr_class.instr_encodings.pop
            next
          end
          process(instr_encoding, :encoding, nil, instr_class.instr_encodings)
        end
      end

      block_given? ? nil : instr_section
    end

    def load_instruction_set(xml_dir, instr_set_id, stop_at = :encoding, &block)
      @stop_at = stop_at
      @user_block = block

      instr_set_data = INSTR_SET_DATA[instr_set_id]
      index_file = "#{xml_dir}/#{instr_set_data[:file]}"
      index_xml = File.open(index_file) { |io| io.read }
      index_doc = REXML::Document.new(index_xml)
      instr_set = InstructionSet.new(index_doc.root, instr_set_id)
      enumerator = instr_set.each_xpath('//iform/@iformfile')
      process(instr_set, :set, enumerator) do |iformfile_attr|
        section_file = "#{xml_dir}/#{iformfile_attr.value}"
        if block_given?
          load_instruction_section(section_file, stop_at, instr_set) do |i|
            yield(i)
          end
        else
          load_instruction_section(section_file, stop_at, instr_set)
        end
      end

      block_given? ? nil : instr_set
    end

    def load_instruction_sets(xml_dir, stop_at = :encoding,
                            instr_set_ids = INSTR_SET_IDS, &block)
      @stop_at = stop_at
      @user_block = block

      instr_sets = []
      instr_set_ids.each do |instr_set_id|
        if block_given?
          load_instruction_set(xml_dir, instr_set_id, stop_at) do |i|
            yield(i)
          end
        else
          instr_sets << load_instruction_set(xml_dir, instr_set_id, stop_at)
        end
      end

      block_given? ? nil : instr_sets
    end

    private

    def process(object, level, enumerator, array = nil)
      if @stop_at == level
        if @user_block
          @user_block.call(object)
        end
      else
        if enumerator
          enumerator.each do |item|
            yield(item)
          end
        end
      end
      if array && @user_block
        array.pop
      end
    end
  end
end

if __FILE__ == $0
  A64InstructionExplorer::XMLLoader.new.load_instruction_sets('xml') \
    do |encoding|
    puts("%-7s %s %s ; [%s] '%s' - `%s` @ %s" %
         [encoding.instr_set.name, encoding.alias_mnemonic ? 'A' : '-',
          encoding.asmtemplate, encoding.features.join(' '),
          encoding.instr_section.heading, encoding.instr_section.brief,
          encoding.instr_section.section_file])
  end
end
