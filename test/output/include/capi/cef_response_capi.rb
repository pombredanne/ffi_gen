# Generated by ffi-gen. Please do not change this file by hand.

require 'ffi'

module CEF
  extend FFI::Library
  ffi_lib 'cef'
  
  def self.attach_function(name, *_)
    begin; super; rescue FFI::NotFoundError => e
      (class << self; self; end).class_eval { define_method(name) { |*_| raise e } }
    end
  end
  
  # Structure used to represent a web response. The functions of this structure
  # may be called on any thread.
  # 
  # = Fields:
  # :base ::
  #   (unknown) Base structure.
  # :is_read_only ::
  #   (FFI::Pointer(*)) Returns true (1) if this object is read-only.
  # :get_status ::
  #   (FFI::Pointer(*)) Get the response status code.
  # :set_status ::
  #   (FFI::Pointer(*)) Set the response status code.
  # :get_status_text ::
  #   (FFI::Pointer(*)) The resulting string must be freed by calling cef_string_userfree_free().
  # :set_status_text ::
  #   (FFI::Pointer(*)) Set the response status text.
  # :get_mime_type ::
  #   (FFI::Pointer(*)) The resulting string must be freed by calling cef_string_userfree_free().
  # :set_mime_type ::
  #   (FFI::Pointer(*)) Set the response mime type.
  # :get_header ::
  #   (FFI::Pointer(*)) The resulting string must be freed by calling cef_string_userfree_free().
  # :get_header_map ::
  #   (FFI::Pointer(*)) Get all response header fields.
  # :set_header_map ::
  #   (FFI::Pointer(*)) Set all response header fields.
  class Response < FFI::Struct
    layout :base, :char,
           :is_read_only, :pointer,
           :get_status, :pointer,
           :set_status, :pointer,
           :get_status_text, :pointer,
           :set_status_text, :pointer,
           :get_mime_type, :pointer,
           :set_mime_type, :pointer,
           :get_header, :pointer,
           :get_header_map, :pointer,
           :set_header_map, :pointer
  end
  
  # Create a new cef_response_t object.
  # 
  # @method response_create()
  # @return [Response] 
  # @scope class
  attach_function :response_create, :cef_response_create, [], Response
  
end
