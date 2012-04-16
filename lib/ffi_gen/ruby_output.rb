class FFIGen
  RUBY_KEYWORDS = %w{alias allocate and begin break case class def defined do else elsif end ensure false for if in initialize module next nil not or redo rescue retry return self super then true undef unless until when while yield}

  def write_ruby(writer)
    writer.puts "# Generated by ffi_gen. Please do not change this file by hand.", "", "require 'ffi'", "", "module #{@module_name}"
    writer.indent do
      writer.puts "extend FFI::Library"
      writer.puts "ffi_lib_flags #{@ffi_lib_flags.map(&:inspect).join(', ')}" if @ffi_lib_flags
      writer.puts "ffi_lib '#{@ffi_lib}'", ""
      declarations.values.compact.uniq.each do |declaration|
        declaration.write_ruby writer
      end
    end
    writer.puts "end"
  end
  
  def to_ruby_type(full_type)
    canonical_type = Clang.get_canonical_type full_type
    data_array = case canonical_type[:kind]
    when :void            then [":void",       "nil"]
    when :bool            then [":bool",       "Boolean"]
    when :u_char          then [":uchar",      "Integer"]
    when :u_short         then [":ushort",     "Integer"]
    when :u_int           then [":uint",       "Integer"]
    when :u_long          then [":ulong",      "Integer"]
    when :u_long_long     then [":ulong_long", "Integer"]
    when :char_s, :s_char then [":char",       "Integer"]
    when :short           then [":short",      "Integer"]
    when :int             then [":int",        "Integer"]
    when :long            then [":long",       "Integer"]
    when :long_long       then [":long_long",  "Integer"]
    when :float           then [":float",      "Float"]
    when :double          then [":double",     "Float"]
    when :pointer
      pointee_type = Clang.get_pointee_type canonical_type
      result = nil
      case pointee_type[:kind]
      when :char_s
        result = [":string", "String"]
      when :record
        pointee_declaration = @declarations[Clang.get_cursor_type(Clang.get_type_declaration(pointee_type))]
        result = [pointee_declaration.ruby_name, pointee_declaration.ruby_name] if pointee_declaration and pointee_declaration.written
      when :function_proto
        declaration = @declarations[full_type]
        result = [":#{declaration.ruby_name}", "Proc(_callback_#{declaration.ruby_name}_)"] if declaration
      end
      
      if result.nil?
        pointer_depth = 0
        pointer_target_name = ""
        current_type = full_type
        loop do
          declaration = Clang.get_type_declaration current_type
          pointer_target_name = to_ruby_camelcase Clang.get_cursor_spelling(declaration).to_s_and_dispose
          break if not pointer_target_name.empty?

          case current_type[:kind]
          when :pointer
            pointer_depth += 1
            current_type = Clang.get_pointee_type current_type
          when :unexposed
            break
          else
            pointer_target_name = Clang.get_type_kind_spelling(current_type[:kind]).to_s_and_dispose
            break
          end
        end
        result = [":pointer", "FFI::Pointer(#{'*' * pointer_depth}#{pointer_target_name})", pointer_target_name]
      end
      
      result
    when :record
      declaration = @declarations[canonical_type]
      declaration ? ["#{declaration.ruby_name}.by_value", declaration.ruby_name] : [":char", "unknown"] # TODO
    when :enum
      declaration = @declarations[canonical_type]
      declaration ? [":#{declaration.ruby_name}", "Symbol from _enum_#{declaration.ruby_name}_", declaration.ruby_name] : [":char", "unknown"] # TODO
    when :constant_array
      element_type_data = to_ruby_type Clang.get_array_element_type(canonical_type)
      size = Clang.get_array_size canonical_type
      ["[#{element_type_data[:ffi_type]}, #{size}]", "Array<#{element_type_data[:description]}>"]
    else
      raise NotImplementedError, "No translation for values of type #{canonical_type[:kind]}"
    end
    
    { ffi_type: data_array[0], description: data_array[1], parameter_name: to_ruby_lowercase(data_array[2] || data_array[1]) }
  end
  
  def to_ruby_lowercase(parts, avoid_keywords = false)
    parts = split_name parts if parts.is_a? String
    str = parts.map(&:downcase).join("_")
    str.sub! /^\d/, '_\0' # fix illegal beginnings
    str = "_#{str}" if avoid_keywords and RUBY_KEYWORDS.include? str
    str
  end
  
  def to_ruby_camelcase(parts)
    parts = split_name parts if parts.is_a? String
    parts.map{ |s| s[0].upcase + s[1..-1] }.join
  end
  
  class Enum
    def write_ruby(writer)
      prefix_length = 0
      suffix_length = 0
      
      unless @constants.size < 2
        search_pattern = @constants.all? { |constant| constant[:name].include? "_" } ? /(?<=_)/ : /[A-Z]/
        first_name = @constants.first[:name]
        
        loop do
          position = first_name.index(search_pattern, prefix_length + 1) or break
          prefix = first_name[0...position]
          break if not @constants.all? { |constant| constant[:name].start_with? prefix }
          prefix_length = position
        end
        
        loop do
          position = first_name.rindex(search_pattern, first_name.size - suffix_length - 1) or break
          prefix = first_name[position..-1]
          break if not @constants.all? { |constant| constant[:name].end_with? prefix }
          suffix_length = first_name.size - position
        end
      end
      
      @constants.each do |constant|
        constant[:symbol] = ":#{@generator.to_ruby_lowercase constant[:name][prefix_length..(-1 - suffix_length)]}"
      end
      
      writer.comment do
        writer.write_description @comment
        writer.puts "", "<em>This entry is only for documentation and no real method. The FFI::Enum can be accessed via #enum_type(:#{ruby_name}).</em>"
        writer.puts "", "=== Options:"
        @constants.each do |constant|
          writer.puts "#{constant[:symbol]} ::"
          writer.write_description constant[:comment], false, "  ", "  "
        end
        writer.puts "", "@method _enum_#{ruby_name}_", "@return [Symbol]", "@scope class"
      end
      
      writer.puts "enum :#{ruby_name}, ["
      writer.indent do
        writer.write_array @constants, "," do |constant|
          "#{constant[:symbol]}#{constant[:value] ? ", #{constant[:value]}" : ''}"
        end
      end
      writer.puts "]", ""
    end
    
    def ruby_name
      @ruby_name ||= @generator.to_ruby_lowercase @name
    end
  end
  
  class StructOrUnion
    def write_ruby(writer)
      @fields.each do |field|
        field[:symbol] = ":#{@generator.to_ruby_lowercase field[:name]}"
        field[:type_data] = @generator.to_ruby_type field[:type]
      end
      
      writer.comment do
        writer.write_description @comment
        unless @fields.empty?
          writer.puts "", "= Fields:"
          @fields.each do |field|
            writer.puts "#{field[:symbol]} ::"
            writer.write_description field[:comment], false, "  (#{field[:type_data][:description]}) ", "  "
          end
        end
      end
      
      @fields << { symbol: ":dummy", type_data: { ffi_type: ":char" } } if @fields.empty?
      
      writer.puts "class #{ruby_name} < #{@is_union ? 'FFI::Union' : 'FFI::Struct'}"
      writer.indent do
        writer.write_array @fields, ",", "layout ", "       " do |field|
          "#{field[:symbol]}, #{field[:type_data][:ffi_type]}"
        end
      end
      writer.puts "end", ""
      
      @written = true
    end
    
    def ruby_name
      @ruby_name ||= @generator.to_ruby_camelcase @name
    end
  end
  
  class FunctionOrCallback
    def write_ruby(writer)
      @parameters.each do |parameter|
        parameter[:type_data] = @generator.to_ruby_type parameter[:type]
        parameter[:ruby_name] = !parameter[:name].empty? ? @generator.to_ruby_lowercase(parameter[:name]) : parameter[:type_data][:parameter_name]
        parameter[:description] = []
      end
      return_type_data = @generator.to_ruby_type @return_type
      
      function_description = []
      return_value_description = []
      current_description = function_description
      @comment.split("\n").map do |line|
        line = writer.prepare_comment_line line
        if line.gsub! /\\param (.*?) /, ''
          parameter = @parameters.find { |parameter| parameter[:name] == $1 }
          if parameter
            current_description = parameter[:description]
          else
            current_description << "#{$1}: "
          end
        end
        current_description = return_value_description if line.gsub! '\\returns ', ''
        current_description << line
      end
      
      writer.puts "@blocking = true" if @blocking
      writer.comment do
        writer.write_description function_description
        writer.puts "", "<em>This entry is only for documentation and no real method.</em>" if @is_callback
        writer.puts "", "@method #{@is_callback ? "_callback_#{ruby_name}_" : ruby_name}(#{@parameters.map{ |parameter| parameter[:ruby_name] }.join(', ')})"
        @parameters.each do |parameter|
          writer.write_description parameter[:description], false, "@param [#{parameter[:type_data][:description]}] #{parameter[:ruby_name]} ", "  "
        end
        writer.write_description return_value_description, false, "@return [#{return_type_data[:description]}] ", "  "
        writer.puts "@scope class"
      end
      
      ffi_signature = "[#{@parameters.map{ |parameter| parameter[:type_data][:ffi_type] }.join(', ')}], #{return_type_data[:ffi_type]}"
      if @is_callback
        writer.puts "callback :#{ruby_name}, #{ffi_signature}", ""
      else
        writer.puts "attach_function :#{ruby_name}, :#{@c_name}, #{ffi_signature}", ""
      end
    end
    
    def ruby_name
      @ruby_name ||= @generator.to_ruby_lowercase @name, true
    end
  end
  
  class Constant
    def write_ruby(writer)
      writer.puts "#{@generator.to_ruby_lowercase(@name, true).upcase} = #{@value}", ""
    end
  end
end