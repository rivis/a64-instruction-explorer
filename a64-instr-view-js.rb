#!/usr/bin/ruby

# SPDX-License-Identifier: MIT-0

require 'set'
require './a64_instruction_explorer'

INSTR_SET_ORDER = {
  'base'   => 0,
  'simdfp' => 1,
  'sve'    => 2,
  'sme'    => 3,
}

all_instrs = []

mnemonic_file_set = Set.new
A64InstructionExplorer::XMLLoader.new.load_instruction_sets('xml') do |encoding|
  section = encoding.instr_section

  if ! mnemonic_file_set.add?(encoding.mnemonic + '@' + section.section_file)
    next
  end

  all_instrs << {
    category: encoding.instr_set.id.to_s,
    mnemonic: encoding.alias_mnemonic ? encoding.alias_mnemonic
                                      : encoding.mnemonic,
    heading:  section.heading,
    brief:    section.brief,
    file:     section.section_file.sub(/\.xml$/, '.html'),
  }
end

all_instrs.sort! do |a, b|
  if a[:mnemonic] != b[:mnemonic]
    a[:mnemonic] <=> b[:mnemonic]
  elsif a[:category] != b[:category]
    INSTR_SET_ORDER[a[:category]] <=> INSTR_SET_ORDER[b[:category]]
  else
    a[:heading] <=> b[:heading]
  end
end

puts("const instrs = #{JSON.generate(all_instrs)};")
