module parser

import datatypes { Stack }
import strings { new_builder }

const (
	null = rune(0)
	replacement_token = CharacterToken{0xfffd}
)

const (
	whitespace = [rune(0x0009), 0x000a, 0x000c, 0x000d, 0x0020]
	ascii_alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.runes()
	ascii_alphanumeric = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.runes()
	decimal_digits = '0123456789'.runes()
	hex_digits_lower = '0123456789abcdef'.runes()
	hex_digits_upper = '01234566789ABCDEF'.runes()
)

struct Tokenizer {
	source []rune
mut:
	pos int
	char rune

	state TokenizerState = .data
	return_state TokenizerState = .@none

	token Token = EOFToken{}
	attr Attribute
	buffer strings.Builder = new_builder(50)
	open_tags Stack<string>
	char_ref_code rune
}

// https://html.spec.whatwg.org/multipage/parsing.html#tokenization
enum TokenizerState {
	@none
	after_attribute_name
	after_attribute_value_quoted
	after_doctype_name
	after_doctype_public_identifier
	after_doctype_public_keyword
	after_doctype_system_identifier
	after_doctype_system_keyword
	ambiguous_ampersand
	attribute_name
	attribute_value_double_quoted
	attribute_value_single_quoted
	attribute_value_unquoted
	before_attribute_name
	before_attribute_value
	before_doctype_name
	before_doctype_public_identifier
	before_doctype_system_identifier
	between_doctype_public_and_system_identifiers
	bogus_comment
	bogus_doctype
	cdata_section
	cdata_section_bracket
	cdata_section_end
	character_reference
	comment
	comment_end
	comment_end_bang
	comment_end_dash
	comment_less_than_sign
	comment_less_than_sign_bang
	comment_less_than_sign_bang_dash
	comment_less_than_sign_bang_dash_dash
	comment_start
	comment_start_dash
	data
	decimal_character_reference
	decimal_character_reference_start
	doctype
	doctype_name
	doctype_public_identifier_double_quoted
	doctype_public_identifier_single_quoted
	doctype_system_identifier_double_quoted
	doctype_system_identifier_single_quoted
	end_tag_open
	eof
	hexadecimal_character_reference
	hexadecimal_character_reference_start
	markup_declaration_open
	named_character_reference
	numeric_character_reference
	numeric_character_reference_end
	plaintext
	rawtext
	rawtext_end_tag_name
	rawtext_end_tag_open
	rawtext_less_than_sign
	rcdata
	rcdata_end_tag_name
	rcdata_end_tag_open
	rcdata_less_than_sign
	script_data
	script_data_end_tag_name
	script_data_end_tag_open
	script_data_escape_start
	script_data_escape_start_dash
	script_data_escaped
	script_data_escaped_dash
	script_data_escaped_dash_dash
	script_data_escaped_end_tag_name
	script_data_escaped_end_tag_open
	script_data_escaped_less_than_sign
	script_data_double_escape_start
	script_data_double_escaped
	script_data_double_escaped_dash
	script_data_double_escaped_dash_dash
	script_data_double_escaped_less_than_sign
	script_data_double_escape_end
	script_data_less_than_sign
	self_closing_start_tag
	tag_name
	tag_open
}

// reconsume moves the cursor position back one space, so that the
// consume function will not change t.char.
[inline]
fn (mut t Tokenizer) reconsume() { t.pos-- }

// consume returns the next value in buffer and moves the
// cursor forward once.
fn (mut t Tokenizer) consume() ? {
	if t.pos >= t.source.len {
		return error('End of file.')
	}

	t.char = t.source[t.pos]
	t.pos++
}

// peek returns the next value in buffer without moving the cursor.
fn (mut t Tokenizer) peek() ?rune {
	if t.pos >= t.source.len {
		return error('End of file.')
	}

	return t.source[t.pos]
}

// look_ahead returns the next value in buffer without moving the
// cursor forward.
fn (mut t Tokenizer) look_ahead(look_for string, case_sensitive bool) bool {
	if t.pos + look_for.len > t.source.len-1 {
		return false
	}

	if case_sensitive {
		if t.source[t.pos..(t.pos + look_for.len)].string() == look_for {
			for _ in 0..look_for.len {
				t.consume() or {
					return false
				}
			}
			return true
		} else {
			return false
		}
	} else {
		if t.source[t.pos..(t.pos + look_for.len)].string().to_lower() == look_for.to_lower() {
			for _ in 0..look_for.len {
				t.consume() or {
					return false
				}
			}
			return true
		} else {
			return false
		}
	}
}

// flush_codepoints adds all the characters in the buffer to either the
// current attribute or emits them as CharacterTokens.
fn (mut t Tokenizer) flush_codepoints() []Token {
	if t.return_state in [
		.attribute_value_double_quoted,
		.attribute_value_single_quoted,
		.attribute_value_unquoted,
	] {
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.value.write_string(builder_contents(t.buffer))
		return []Token{}
	} else {
		return string_to_tokens(builder_contents(t.buffer))
	}
}

// is_token_appropriate_end_tag returns whether or not the current token
// is an end tag that corresponds to the last tag pushed to the open
// tags stack.
fn (mut t Tokenizer) is_token_appropriate_end_tag() bool {
	tag := t.token as TagToken
	if tag.is_start { return false }

	if start_tag := t.open_tags.peek() {
		return if start_tag == tag.name() {
			true
		} else {
			false
		}
	}

	return false
}

// emit_token returns the next token(s) from the Tokenizer
fn (mut t Tokenizer) emit_token() []Token {
	return match t.state {
		.after_attribute_name { t.after_attribute_name_state() }
		.after_attribute_value_quoted { t.after_attribute_value_quoted_state() }
		.after_doctype_name { t.after_doctype_name_state() }
		.after_doctype_public_identifier { t.after_doctype_public_identifier_state() }
		.after_doctype_public_keyword { t.after_doctype_public_keyword_state() }
		.after_doctype_system_identifier { t.after_doctype_system_identifier_state() }
		.after_doctype_system_keyword { t.after_doctype_system_keyword_state() }
		.ambiguous_ampersand { t.ambiguous_ampersand_state() }
		.attribute_name { t.attribute_name_state() }
		.attribute_value_double_quoted { t.attribute_value_double_quoted_state() }
		.attribute_value_single_quoted { t.attribute_value_single_quoted_state() }
		.attribute_value_unquoted { t.attribute_value_unquoted_state() }
		.before_attribute_name { t.before_attribute_name_state() }
		.before_attribute_value { t.before_attribute_value_state() }
		.before_doctype_name { t.before_doctype_name_state() }
		.before_doctype_public_identifier { t.before_doctype_public_identifier_state() }
		.before_doctype_system_identifier { t.before_doctype_system_identifier_state() }
		.between_doctype_public_and_system_identifiers { t.between_doctype_public_and_system_identifiers_state() }
		.bogus_comment { t.bogus_comment_state() }
		.bogus_doctype { t.bogus_doctype_state() }
		.cdata_section { t.cdata_section_state() }
		.cdata_section_bracket { t.cdata_section_bracket_state() }
		.cdata_section_end { t.cdata_section_end_state() }
		.character_reference { t.character_reference_state() }
		.comment { t.comment_state() }
		.comment_end { t.comment_end_state() }
		.comment_end_bang { t.comment_end_bang_state() }
		.comment_end_dash { t.comment_end_dash_state() }
		.comment_less_than_sign { t.comment_less_than_sign_state() }
		.comment_less_than_sign_bang { t.comment_less_than_sign_bang_state() }
		.comment_less_than_sign_bang_dash { t.comment_less_than_sign_bang_dash_state() }
		.comment_less_than_sign_bang_dash_dash { t.comment_less_than_sign_bang_dash_dash_state() }
		.comment_start { t.comment_start_state() }
		.comment_start_dash { t.comment_start_dash_state() }
		.data { t.data_state() }
		.decimal_character_reference { t.decimal_character_reference_state() }
		.decimal_character_reference_start { t.decimal_character_reference_start_state() }
		.doctype { t.doctype_state() }
		.doctype_name { t.doctype_name_state() }
		.doctype_public_identifier_double_quoted { t.doctype_public_identifier_double_quoted_state() }
		.doctype_public_identifier_single_quoted { t.doctype_public_identifier_single_quoted_state() }
		.doctype_system_identifier_double_quoted { t.doctype_system_identifier_double_quoted_state() }
		.doctype_system_identifier_single_quoted { t.doctype_system_identifier_single_quoted_state() }
		.end_tag_open { t.end_tag_open_state() }
		.hexadecimal_character_reference { t.hexadecimal_character_reference_state() }
		.hexadecimal_character_reference_start { t.hexadecimal_character_reference_start_state() }
		.markup_declaration_open { t.markup_declaration_open_state() }
		.named_character_reference { t.named_character_reference_state() }
		.numeric_character_reference { t.numeric_character_reference_state() }
		.numeric_character_reference_end { t.numeric_character_reference_end_state() }
		.plaintext { t.plaintext_state() }
		.rawtext { t.rawtext_state() }
		.rawtext_end_tag_name { t.rawtext_end_tag_name_state() }
		.rawtext_end_tag_open { t.rawtext_end_tag_open_state() }
		.rawtext_less_than_sign { t.rawtext_less_than_sign_state() }
		.rcdata { t.rcdata_state() }
		.rcdata_end_tag_name { t.rcdata_end_tag_name_state() }
		.rcdata_end_tag_open { t.rcdata_end_tag_open_state() }
		.rcdata_less_than_sign { t.rcdata_less_than_sign_state() }
		.script_data { t.script_data_state() }
		.script_data_end_tag_name { t.script_data_end_tag_name_state() }
		.script_data_end_tag_open { t.script_data_end_tag_open_state() }
		.script_data_escape_start { t.script_data_escape_start_state() }
		.script_data_escape_start_dash { t.script_data_escape_start_dash_state() }
		.script_data_escaped { t.script_data_escaped_state() }
		.script_data_escaped_dash { t.script_data_escaped_dash_state() }
		.script_data_escaped_dash_dash { t.script_data_escaped_dash_dash_state() }
		.script_data_escaped_end_tag_name { t.script_data_escaped_end_tag_name_state() }
		.script_data_escaped_end_tag_open { t.script_data_escaped_end_tag_open_state() }
		.script_data_escaped_less_than_sign { t.script_data_escaped_less_than_sign_state() }
		.script_data_double_escape_start { t.script_data_double_escape_start_state() }
		.script_data_double_escaped { t.script_data_double_escaped_state() }
		.script_data_double_escaped_dash { t.script_data_double_escaped_dash_state() }
		.script_data_double_escaped_dash_dash { t.script_data_double_escaped_dash_dash_state() }
		.script_data_double_escaped_less_than_sign { t.script_data_double_escaped_less_than_sign_state() }
		.script_data_double_escape_end { t.script_data_double_escape_end_state() }
		.script_data_less_than_sign { t.script_data_less_than_sign_state() }
		.self_closing_start_tag { t.self_closing_start_tag_state() }
		.tag_name { t.tag_name_state() }
		.tag_open { t.tag_open_state() }
		else {
			println('State not implemented ($t.state).')
			[]Token{}
		}
	}
}

// 13.2.5.1
fn (mut t Tokenizer) data_state() []Token {
	t.consume() or {
		t.state = .eof
		return [EOFToken{}]
	}

	if t.char == `&` {
		t.return_state = .data
		t.state = .character_reference
		tokens := t.emit_token()
		return tokens
	}

	if t.char == `<` {
		t.state = .tag_open
		return t.emit_token()
	}

	if t.char == null {
		// parse error: unexpected null character
		println('Unexpected Null Character')
		// return [CharacterToken{t.char}]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.2
fn (mut t Tokenizer) rcdata_state() []Token {
	t.consume() or {
		t.state = .eof
		return [EOFToken{}]
	}

	if t.char == `&` {
		t.return_state = .rcdata
		t.state = .character_reference
		tokens := t.emit_token()
		return tokens
	}

	if t.char == `<` {
		t.state = .rcdata_less_than_sign
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected Null Character')
		return [replacement_token]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.3
fn (mut t Tokenizer) rawtext_state() []Token {
	t.consume() or {
		t.state = .eof
		return [EOFToken{}]
	}

	if t.char == `<` {
		t.state = .rawtext_less_than_sign
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected Null Character')
		return [replacement_token]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.4
fn (mut t Tokenizer) script_data_state() []Token {
	t.consume() or {
		t.state = .eof
		return [EOFToken{}]
	}

	if t.char == `<` {
		t.state = .script_data_less_than_sign
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected Null Character')
		return [replacement_token]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.5
fn (mut t Tokenizer) plaintext_state() []Token {
	t.consume() or {
		t.state = .eof
		return [EOFToken{}]
	}

	if t.char == null {
		// parse error
		println('Unexpected Null Character')
		return [replacement_token]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.6
fn (mut t Tokenizer) tag_open_state() []Token {
	t.consume() or {
		// parse error
		println('EOF before tag name.')
		t.state = .eof
		return [
			CharacterToken{`<`},
			EOFToken{
				name: name__eof_before_tag_name
				mssg: mssg__eof_before_tag_name
			}
		]
	}

	if t.char == `!` {
		t.state = .markup_declaration_open
		return t.emit_token()
	}

	if t.char == `/` {
		t.state = .end_tag_open
		return t.emit_token()
	}

	if t.char in ascii_alpha {
		t.token = TagToken{}
		t.reconsume()
		t.state = .tag_name
		return t.emit_token()
	}

	if t.char == `?` {
		// parse error
		println('Unexpected question mark instead of tag name.')
		t.token = CommentToken{}
		t.reconsume()
		t.state = .bogus_comment
		return t.emit_token()
	}

	// parse error
	println('Invalid first character of tag name.')
	t.reconsume()
	t.state = .data
	return [CharacterToken{`<`}]
}

// 13.2.5.7
fn (mut t Tokenizer) end_tag_open_state() []Token {
	t.consume() or {
		// parse error
		println('EOF before tag name.')
		t.state = .eof
		return [
			CharacterToken{`<`},
			CharacterToken{`/`},
			EOFToken{
				name: name__eof_before_tag_name
				mssg: mssg__eof_before_tag_name
			}
		]
	}

	if t.char in ascii_alpha {
		t.token = TagToken{is_start: false}
		t.reconsume()
		t.state = .tag_name
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing end tag name.')
		t.state = .data
		return t.emit_token()
	}

	// parse error
	println('Invalid first character of tag name.')
	t.token = CommentToken{}
	t.reconsume()
	t.state = .bogus_comment
	return t.emit_token()
}

// 13.2.5.8
fn (mut t Tokenizer) tag_name_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char in whitespace {
		t.state = .before_attribute_name
		return t.emit_token()
	}

	if t.char == `/` {
		t.state = .self_closing_start_tag
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.char == null {
		// parse error
		println('Unexpected Null Character')
		//t.tagtoken__name_append(0xfffd)
		mut tok := &(t.token as TagToken)
		tok.name.write_rune(0xfffd)
		return t.emit_token()
	}

	// t.tagtoken__name_append(t.char)
	mut tok := &(t.token as TagToken)
	tok.name.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.9
fn (mut t Tokenizer) rcdata_less_than_sign_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .rcdata
		return [CharacterToken{`<`}]
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `/` {
		t.buffer = new_builder(50)
		t.state = .rcdata_end_tag_open
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.10
fn (mut t Tokenizer) rcdata_end_tag_open_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .rcdata
		return string_to_tokens('</')
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in ascii_alpha {
		t.token = TagToken{is_start: false}
		t.reconsume()
		t.state = .rcdata_end_tag_name
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.11
fn (mut t Tokenizer) rcdata_end_tag_name_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .rcdata
		return string_to_tokens('</' + t.buffer.str())
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace {
		if t.is_token_appropriate_end_tag() {
			t.state = .before_attribute_name
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `/` {
		if t.is_token_appropriate_end_tag() {
			t.state = .self_closing_start_tag
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `>` {
		if t.is_token_appropriate_end_tag() {
			t.state = .data
			return [t.token]
		}

		return anything_else()
	}

	if t.char in ascii_alpha {
		// t.tagtoken__name_append(rune_to_lower(t.char))
		mut tok := &(t.token as TagToken)
		tok.name.write_rune(rune_to_lower(t.char))
		t.buffer.write_rune(t.char)
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.12
fn (mut t Tokenizer) rawtext_less_than_sign_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .rawtext
		return [CharacterToken{`<`}]
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `/` {
		t.buffer = new_builder(50)
		t.state = .rawtext_end_tag_open
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.13
fn (mut t Tokenizer) rawtext_end_tag_open_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .rawtext
		return string_to_tokens('</')
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in ascii_alpha {
		t.token = TagToken{is_start: false}
		t.reconsume()
		t.state = .rawtext_end_tag_name
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.14
fn (mut t Tokenizer) rawtext_end_tag_name_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .rawtext
		return string_to_tokens('</' + t.buffer.str())
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace {
		if t.is_token_appropriate_end_tag() {
			t.state = .before_attribute_name
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `/` {
		if t.is_token_appropriate_end_tag() {
			t.state = .self_closing_start_tag
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `>` {
		if t.is_token_appropriate_end_tag() {
			t.state = .data
			return [t.token]
		}

		return anything_else()
	}

	if t.char in ascii_alpha {
		// t.tagtoken__name_append(rune_to_lower(t.char))
		mut tok := &(t.token as TagToken)
		tok.name.write_rune(rune_to_lower(t.char))
		t.buffer.write_rune(t.char)
	}

	return anything_else()
}

// 13.2.5.15
fn (mut t Tokenizer) script_data_less_than_sign_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data
		return [CharacterToken{`<`}]
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `/` {
		t.buffer = new_builder(50)
		t.state = .script_data_end_tag_open
		return t.emit_token()
	}

	if t.char == `!` {
		t.state = .script_data_escape_start
		return string_to_tokens('<!')
	}

	return anything_else()
}

// 13.2.5.16
fn (mut t Tokenizer) script_data_end_tag_open_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data
		return string_to_tokens('</')
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in ascii_alpha {
		t.token = TagToken{is_start: false}
		t.reconsume()
		t.state = .script_data_end_tag_name
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.17
fn (mut t Tokenizer) script_data_end_tag_name_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data
		return string_to_tokens('</' + t.buffer.str())
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace {
		if t.is_token_appropriate_end_tag() {
			t.state = .before_attribute_name
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `/` {
		if t.is_token_appropriate_end_tag() {
			t.state = .self_closing_start_tag
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `>` {
		if t.is_token_appropriate_end_tag() {
			t.state = .data
			return [t.token]
		}

		return anything_else()
	}

	if t.char in ascii_alpha {
		mut tok := &(t.token as TagToken)
		tok.name.write_rune(rune_to_lower(t.char))
		t.buffer.write_rune(t.char)
	}

	return anything_else()
}

// 13.2.5.18
fn (mut t Tokenizer) script_data_escape_start_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `-` {
		t.state = .script_data_escape_start_dash
		return [CharacterToken{`-`}]
	}

	return anything_else()
}

// 13.2.5.19
fn (mut t Tokenizer) script_data_escape_start_dash_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `-` {
		t.state = .script_data_escaped_dash_dash
		return [CharacterToken{`-`}]
	}

	return anything_else()
}

// 13.2.5.20
fn (mut t Tokenizer) script_data_escaped_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in script html comment like text.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_script_comment_like_text
			mssg: mssg__eof_in_script_comment_like_text
		}]
	}

	if t.char == `-` {
		t.state = .script_data_escaped_dash
		return [CharacterToken{`-`}]
	}

	if t.char == `<` {
		t.state = .script_data_escaped_less_than_sign
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		return [replacement_token]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.21
fn (mut t Tokenizer) script_data_escaped_dash_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in script html comment like text.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_script_comment_like_text
			mssg: mssg__eof_in_script_comment_like_text
		}]
	}

	if t.char == `-` {
		t.state = .script_data_escaped_dash_dash
		return [CharacterToken{`-`}]
	}

	if t.char == `<` {
		t.state = .script_data_escaped_less_than_sign
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		return [replacement_token]
	}

	t.state = .script_data_escaped
	return [CharacterToken{t.char}]
}

// 13.2.5.22
fn (mut t Tokenizer) script_data_escaped_dash_dash_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in script html comment like text.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_script_comment_like_text
			mssg: mssg__eof_in_script_comment_like_text
		}]
	}

	if t.char == `-` {
		return [CharacterToken{`-`}]
	}

	if t.char == `<` {
		t.state = .script_data_escaped_less_than_sign
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .script_data
		return [CharacterToken{`>`}]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		return [replacement_token]
	}

	t.state = .script_data_escaped
	return [CharacterToken{t.char}]
}

// 13.2.5.23
fn (mut t Tokenizer) script_data_escaped_less_than_sign_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data_escaped
		return [CharacterToken{`<`}]
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `/` {
		t.buffer = new_builder(50)
		t.state = .script_data_escaped_end_tag_open
		return t.emit_token()
	}

	if t.char in ascii_alpha {
		t.buffer = new_builder(50)
		t.reconsume()
		t.state = .script_data_double_escape_start
		return [CharacterToken{`<`}]
	}

	return anything_else()
}

// 13.2.5.24
fn (mut t Tokenizer) script_data_escaped_end_tag_open_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data_escaped
		return string_to_tokens('</')
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in ascii_alpha {
		t.token = TagToken{}
		t.reconsume()
		t.state = .script_data_escaped_end_tag_name
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.25
fn (mut t Tokenizer) script_data_escaped_end_tag_name_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data_escaped
		return string_to_tokens('</' + t.buffer.str())
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace {
		if t.is_token_appropriate_end_tag() {
			t.state = .before_attribute_name
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `/` {
		if t.is_token_appropriate_end_tag() {
			t.state = .self_closing_start_tag
			return t.emit_token()
		}

		return anything_else()
	}

	if t.char == `>` {
		if t.is_token_appropriate_end_tag() {
			t.state = .data
			return [t.token]
		}

		return anything_else()
	}

	if t.char in ascii_alpha {
		mut tok := &(t.token as TagToken)
		tok.name.write_rune(rune_to_lower(t.char))
		t.buffer.write_rune(t.char)
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.26
fn (mut t Tokenizer) script_data_double_escape_start_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data_escaped
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace || t.char in [`/`, `>`] {
		if builder_contents(t.buffer) == 'script' {
			t.state = .script_data_double_escaped
			return t.emit_token()
		} else {
			t.state = .script_data_escaped
			return [CharacterToken{t.char}]
		}
	}

	if t.char in ascii_alpha {
		t.buffer.write_rune(t.char)
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.27
fn (mut t Tokenizer) script_data_double_escaped_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in script html comment like text.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_script_comment_like_text
			mssg: mssg__eof_in_script_comment_like_text
		}]
	}

	if t.char == `-` {
		t.state = .script_data_double_escaped_dash
		return [CharacterToken{`-`}]
	}

	if t.char == `<` {
		t.state = .script_data_double_escaped_less_than_sign
		return [CharacterToken{`<`}]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		return [replacement_token]
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.28
fn (mut t Tokenizer) script_data_double_escaped_dash_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in script html comment like text.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_script_comment_like_text
			mssg: mssg__eof_in_script_comment_like_text
		}]
	}

	if t.char == `-` {
		t.state = .script_data_double_escaped_dash_dash
		return [CharacterToken{`-`}]
	}

	if t.char == `<` {
		t.state = .script_data_double_escaped_less_than_sign
		return [CharacterToken{`<`}]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		t.state = .script_data_double_escaped
		return [replacement_token]
	}

	t.state = .script_data_double_escaped
	return [CharacterToken{t.char}]
}

// 13.2.5.29
fn (mut t Tokenizer) script_data_double_escaped_dash_dash_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in script html comment like text.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_script_comment_like_text
			mssg: mssg__eof_in_script_comment_like_text
		}]
	}

	if t.char == `-` {
		return [CharacterToken{`-`}]
	}

	if t.char == `<` {
		t.state = .script_data_double_escaped_less_than_sign
		return [CharacterToken{`<`}]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		t.state = .script_data_double_escaped
		return [replacement_token]
	}

	t.state = .script_data_double_escaped
	return [CharacterToken{t.char}]
}

// 13.2.5.30
fn (mut t Tokenizer) script_data_double_escaped_less_than_sign_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data_double_escaped
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `/` {
		t.buffer = new_builder(50)
		t.state = .script_data_double_escape_end
		return [CharacterToken{`/`}]
	}
	
	return anything_else()
}

// 13.2.5.31
fn (mut t Tokenizer) script_data_double_escape_end_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .script_data_double_escaped
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace || t.char in [`/`, `>`] {
		if builder_contents(t.buffer) == 'script' {
			t.state = .script_data_escaped
			return t.emit_token()
		} else {
			t.state = .script_data_double_escaped
			return [CharacterToken{t.char}]
		}
	}

	if t.char in ascii_alpha {
		t.buffer.write_rune(rune_to_lower(t.char))
		return [CharacterToken{t.char}]
	}

	return anything_else()
}

// 13.2.5.32
fn (mut t Tokenizer) before_attribute_name_state() []Token {
	t.consume() or {
		t.reconsume()
		t.state = .after_attribute_name
		return t.emit_token()
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char in [`/`, `>`] {
		t.reconsume()
		t.state = .after_attribute_name
		return t.emit_token()
	}

	if t.char == `=` {
		// parse error
		println('Unexpected equals sign before attribute name.')
		mut tok := &(t.token as TagToken)
		tok.attributes << Attribute{}
		mut attr := &(tok.attributes[tok.attributes.len - 1])
		attr.name.write_rune(t.char)
		t.state = .attribute_name
		return t.emit_token()
	}

	mut tok := &(t.token as TagToken)
	tok.attributes << Attribute{}
	t.reconsume()
	t.state = .attribute_name
	return t.emit_token()
}

// 13.2.5.33
fn (mut t Tokenizer) attribute_name_state() []Token {
	ws := fn [mut t] () []Token {
		t.reconsume()
		t.state = .after_attribute_name
		return t.emit_token()
	}
	
	anything_else := fn [mut t] () []Token {
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.name.write_rune(rune_to_lower(t.char))
		return t.emit_token()
	}

	t.consume() or {
		return ws()
	}

	if t.char in whitespace || t.char in [`/`, `>`] {
		return ws()
	}

	if t.char == `=` {
		t.state = .before_attribute_value
		return t.emit_token()
	}

	// if t.char in ascii_alpha_upper {
	// 	mut tok := &(t.token as TagToken)
	// 	mut attr := &(tok.attributes[tok.attributes.len-1])
	// 	attr.name.write_rune(rune_to_lower(t.char))
	// 	return t.emit_token()
	// }

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.name.write_rune(0xfffd)
	}

	if t.char in [`'`, `"`, `<`] {
		// parse error
		println('Unexpected character in attribute name.')
		return anything_else()
	}

	return anything_else()
}

// 13.2.5.34
fn (mut t Tokenizer) after_attribute_name_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char == `/` {
		t.state = .self_closing_start_tag
		return t.emit_token()
	}

	if t.char == `=` {
		t.state = .before_attribute_value
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as TagToken)
	tok.attributes << Attribute{}
	t.reconsume()
	t.state = .attribute_name
	return t.emit_token()
}

// 13.2.5.35
fn (mut t Tokenizer) before_attribute_value_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .attribute_value_unquoted
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char == `"` {
		t.state = .attribute_value_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		t.state = .attribute_value_single_quoted
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing attribute value.')
		t.state = .data
		return [t.token]
	}

	return anything_else()
}

// 13.2.5.36
fn (mut t Tokenizer) attribute_value_double_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char == `"` {
		t.state = .after_attribute_value_quoted
		return t.emit_token()
	}

	if t.char == `&` {
		t.return_state = .attribute_value_double_quoted
		t.state = .character_reference
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.value.write_rune(0xfffd)
	}

	mut tok := &(t.token as TagToken)
	mut attr := &(tok.attributes[tok.attributes.len-1])
	attr.value.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.37
fn (mut t Tokenizer) attribute_value_single_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char == `'` {
		t.state = .after_attribute_value_quoted
		return t.emit_token()
	}

	if t.char == `&` {
		t.return_state = .attribute_value_single_quoted
		t.state = .character_reference
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.value.write_rune(0xfffd)
	}

	mut tok := &(t.token as TagToken)
	mut attr := &(tok.attributes[tok.attributes.len-1])
	attr.value.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.38
fn (mut t Tokenizer) attribute_value_unquoted_state() []Token {
	anything_else := fn [mut t] () []Token {
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.value.write_rune(0xfffd)
		return t.emit_token()
	}

	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char in whitespace {
		t.state = .before_attribute_name
		return t.emit_token()
	}

	if t.char == `&` {
		t.return_state = .attribute_value_unquoted
		t.state = .character_reference
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as TagToken)
		mut attr := &(tok.attributes[tok.attributes.len-1])
		attr.value.write_rune(0xfffd)
	}

	if t.char in [`'`, `"`, `=`, `<`, `\``] {
		// parse error
		println('Unexpected character in unquoted attribute value.')
		return anything_else()
	}

	return anything_else()
}

// 13.2.5.39
fn (mut t Tokenizer) after_attribute_value_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char in whitespace {
		t.state = .before_attribute_name
		return t.emit_token()
	}

	if t.char == `/` {
		t.state = .self_closing_start_tag
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Missing whitespace between attributes.')
	t.reconsume()
	t.state = .before_attribute_name
	return t.emit_token()
}

// 13.2.5.40
fn (mut t Tokenizer) self_closing_start_tag_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in tag.')
		t.state = .eof
		return [EOFToken{
			name: name__eof_in_tag
			mssg: mssg__eof_in_tag
		}]
	}

	if t.char == `>` {
		mut tok := &(t.token as TagToken)
		tok.self_closing = true
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Unexpected solidus in tag.')
	t.reconsume()
	t.state = .before_attribute_name
	return t.emit_token()
}

// 13.2.5.41
fn (mut t Tokenizer) bogus_comment_state() []Token {
	t.consume() or {
		t.state = .eof
		return [t.token, EOFToken{}]
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as CommentToken)
		tok.data.write_rune(0xfffd)
	}

	mut tok := &(t.token as CommentToken)
	tok.data.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.42
fn (mut t Tokenizer) markup_declaration_open_state() []Token {
	if t.look_ahead('--', true) {
		t.token = CommentToken{}
		t.state = .comment_start
		return t.emit_token()
	}

	if t.look_ahead('DOCTYPE', false) {
		t.state = .doctype
		return t.emit_token()
	}

	// not sure I understand what the adjusted current node is
	if t.look_ahead('[CDATA[', true) {
		// Consume those characters. If there is an adjusted current
		// node and it is not an element in the HTML namespace, then
		// switch to the CDATA section state. Otherwise, this is a
		// cdata-in-html-content parse error. Create a comment token
		// whose data is the "[CDATA[" string. Switch to the bogus
		// comment state.
		t.state = .bogus_comment
		return t.emit_token()
	}

	// parse error
	println('Incorrectly opened comment.')
	t.token = CommentToken{}
	t.state = .bogus_comment
	return t.emit_token()
}

// 13.2.5.43
fn (mut t Tokenizer) comment_start_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .comment
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `-` {
		t.state = .comment_start_dash
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Abrupt closing of empty comment.')
		t.state = .data
		return [t.token]
	}

	return anything_else()
}

// 13.2.5.44
fn (mut t Tokenizer) comment_start_dash_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in comment.')
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_comment
			mssg: mssg__eof_in_comment
		}]
	}

	if t.char == `-` {
		t.state = .comment_end
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Abrupt closing of empty comment.')
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as CommentToken)
	tok.data.write_rune(`-`)
	t.reconsume()
	t.state = .comment
	return t.emit_token()
}

// 13.2.5.45
fn (mut t Tokenizer) comment_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in comment.')
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_comment
			mssg: mssg__eof_in_comment
		}]
	}

	if t.char == `<` {
		mut tok := &(t.token as CommentToken)
		tok.data.write_rune(`<`)
		t.state = .comment_less_than_sign
		return t.emit_token()
	}

	if t.char == `-` {
		t.state = .comment_end_dash
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as CommentToken)
		tok.data.write_rune(0xfffd)
		return t.emit_token()
	}

	mut tok := &(t.token as CommentToken)
	tok.data.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.46
fn (mut t Tokenizer) comment_less_than_sign_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .comment
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `!` {
		mut tok := &(t.token as CommentToken)
		tok.data.write_rune(`!`)
		t.state = .comment_less_than_sign_bang
		return t.emit_token()
	}

	if t.char == `<` {
		mut tok := &(t.token as CommentToken)
		tok.data.write_rune(`<`)
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.47
fn (mut t Tokenizer) comment_less_than_sign_bang_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .comment
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `-` {
		t.state = .comment_less_than_sign_bang_dash
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.48
fn (mut t Tokenizer) comment_less_than_sign_bang_dash_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .comment_end_dash
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `-` {
		t.state = .comment_less_than_sign_bang_dash_dash
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.49
fn (mut t Tokenizer) comment_less_than_sign_bang_dash_dash_state() []Token {
	gteof := fn [mut t] () []Token {
		t.reconsume()
		t.state = .comment_end
		return t.emit_token()
	}

	t.consume() or {
		return gteof()
	}

	if t.char == `>` {
		return gteof()
	}

	// parse error
	println('Nested comment.')
	t.reconsume()
	t.state = .comment_end
	return t.emit_token()
}

// 13.2.5.50
fn (mut t Tokenizer) comment_end_dash_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in comment.')
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_comment
			mssg: mssg__eof_in_comment
		}]
	}

	if t.char == `-` {
		t.state = .comment_end
		return t.emit_token()
	}

	mut tok := &(t.token as CommentToken)
	tok.data.write_rune(`-`)
	t.reconsume()
	t.state = .comment
	return t.emit_token()
}

// 13.2.5.51
fn (mut t Tokenizer) comment_end_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in comment.')
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_comment
			mssg: mssg__eof_in_comment
		}]
	}

	if t.char == `>` {
		t.state = .data
		return t.emit_token()
	}

	if t.char == `!` {
		t.state = .comment_end_bang
		return t.emit_token()
	}

	if t.char == `-` {
		mut tok := &(t.token as CommentToken)
		tok.data.write_rune(`-`)
		return t.emit_token()
	}

	mut tok := &(t.token as CommentToken)
	tok.data.write_string('--')
	t.reconsume()
	t.state = .comment
	return t.emit_token()
}

// 13.2.5.52
fn (mut t Tokenizer) comment_end_bang_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in comment.')
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_comment
			mssg: mssg__eof_in_comment
		}]
	}

	if t.char == `>` {
		// parse error
		println('Incorrectly closed comment.')
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as CommentToken)
	tok.data.write_string('--!')
	t.reconsume()
	t.state = .comment
	return t.emit_token()
}

// 13.2.5.53
fn (mut t Tokenizer) doctype_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		t.token = DoctypeToken{}
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}
	
	if t.char in whitespace {
		t.state = .before_doctype_name
		return t.emit_token()
	}

	if t.char == `>` {
		t.reconsume()
		t.state = .before_doctype_name
		return t.emit_token()
	}

	// parse error
	println('Missing whitespace before doctype name.')
	t.reconsume()
	t.state = .before_doctype_name
	return t.emit_token()
}

// 13.2.5.54
fn (mut t Tokenizer) before_doctype_name_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		t.token = DoctypeToken{}
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		t.token = DoctypeToken{}
		mut tok := &(t.token as DoctypeToken)
		tok.name = new_builder(50)
		tok.name.write_rune(0xfffd)
		t.state = .doctype_name
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing DOCTYPE name.')
		t.token = DoctypeToken{}
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	t.token = DoctypeToken{}
	mut tok := &(t.token as DoctypeToken)
	tok.name = new_builder(50)
	tok.name.write_rune(rune_to_lower(t.char))
	t.state = .doctype_name
	return t.emit_token()
}

// 13.2.5.55
fn (mut t Tokenizer) doctype_name_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		t.state = .after_doctype_name
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as DoctypeToken)
		tok.name.write_rune(0xfffd)
		return t.emit_token()
	}

	mut tok := &(t.token as DoctypeToken)
	tok.name.write_rune(rune_to_lower(t.char))
	return t.emit_token()
}

// 13.2.5.56
fn (mut t Tokenizer) after_doctype_name_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.look_ahead('PUBLIC', false) {
		t.state = .after_doctype_public_keyword
		return t.emit_token()
	}

	if t.look_ahead('SYSTEM', false) {
		t.state = .after_doctype_system_keyword
		return t.emit_token()
	}

	// parse error
	println('Invalid character sequence after doctype name.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.57
fn (mut t Tokenizer) after_doctype_public_keyword_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		t.state = .before_doctype_public_identifier
		return t.emit_token()
	}

	if t.char == `"` {
		// parse error
		println('Missing whitespace after doctype public keyword.')
		mut tok := &(t.token as DoctypeToken)
		tok.public_identifier = new_builder(50)
		t.state = .doctype_public_identifier_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		// parse error
		println('Missing whitespace after doctype public keyword.')
		mut tok := &(t.token as DoctypeToken)
		tok.public_identifier = new_builder(50)
		t.state = .doctype_public_identifier_single_quoted
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing doctype public identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Missing quote before doctype public identifier.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.58
fn (mut t Tokenizer) before_doctype_public_identifier_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char == `"` {
		mut tok := &(t.token as DoctypeToken)
		tok.public_identifier = new_builder(50)
		t.state = .doctype_public_identifier_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		mut tok := &(t.token as DoctypeToken)
		tok.public_identifier = new_builder(50)
		t.state = .doctype_public_identifier_single_quoted
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing doctype public identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Missing quote before doctype public identifier.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.59
fn (mut t Tokenizer) doctype_public_identifier_double_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char == `"` {
		t.state = .after_doctype_public_identifier
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as DoctypeToken)
		tok.public_identifier.write_rune(0xfffd)
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Abrubt doctype public identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as DoctypeToken)
	tok.public_identifier.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.60
fn (mut t Tokenizer) doctype_public_identifier_single_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char == `'` {
		t.state = .after_doctype_public_identifier
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as DoctypeToken)
		tok.public_identifier.write_rune(0xfffd)
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Abrubt doctype public identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as DoctypeToken)
	tok.public_identifier.write_rune(t.char)
	return t.emit_token()
}

// 13.2.5.61
fn (mut t Tokenizer) after_doctype_public_identifier_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		t.state = .between_doctype_public_and_system_identifiers
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.char == `"` {
		// parse error
		println('Missing whitespace between doctype public and system identifiers.')
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		// parse error
		println('Missing whitespace between doctype public and system identifiers.')
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_single_quoted
		return t.emit_token()
	}

	// parse error
	println('Missing quote before doctype system identifier.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.62
fn (mut t Tokenizer) between_doctype_public_and_system_identifiers_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		return t.emit_token()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}
	
	if t.char == `"` {
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_single_quoted
		return t.emit_token()
	}

	// parse error
	println('Missing quote before doctype system identifier.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.63
fn (mut t Tokenizer) after_doctype_system_keyword_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		t.state = .before_doctype_system_identifier
		return t.emit_token()
	}

	if t.char == `"` {
		// parse error
		println('Missing whitespace between system keyword and system identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		// parse error
		println('Missing whitespace between system keyword and system identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_single_quoted
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing doctype system identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Missing quote before doctype system identifier.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.64
fn (mut t Tokenizer) before_doctype_system_identifier_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		return t.before_doctype_system_identifier_state()
	}

	if t.char == `"` {
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_double_quoted
		return t.emit_token()
	}

	if t.char == `'` {
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier = new_builder(50)
		t.state = .doctype_system_identifier_single_quoted
		return t.emit_token()
	}

	if t.char == `>` {
		// parse error
		println('Missing doctype system identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Missing quote before doctype system identifier.')
	mut tok := &(t.token as DoctypeToken)
	tok.force_quirks = true
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.65
fn (mut t Tokenizer) doctype_system_identifier_double_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char == `"` {
		t.state = .after_doctype_system_identifier
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier.write_rune(0xfffd)
		return t.doctype_system_identifier_double_quoted_state()
	}

	if t.char == `>` {
		// parse error
		println('Abrubt doctype system identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as DoctypeToken)
	tok.system_identifier.write_rune(t.char)
	return t.doctype_system_identifier_double_quoted_state()
}

// 13.2.5.66
fn (mut t Tokenizer) doctype_system_identifier_single_quoted_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char == `'` {
		t.state = .after_doctype_system_identifier
		return t.emit_token()
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		mut tok := &(t.token as DoctypeToken)
		tok.system_identifier.write_rune(0xfffd)
		return t.doctype_system_identifier_single_quoted_state()
	}

	if t.char == `>` {
		// parse error
		println('Abrubt doctype system identifier.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .data
		return [t.token]
	}

	mut tok := &(t.token as DoctypeToken)
	tok.system_identifier.write_rune(t.char)
	return t.doctype_system_identifier_single_quoted_state()
}

// 13.2.5.67
fn (mut t Tokenizer) after_doctype_system_identifier_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in DOCTYPE.')
		mut tok := &(t.token as DoctypeToken)
		tok.force_quirks = true
		t.state = .eof
		return [t.token, EOFToken{
			name: name__eof_in_doctype
			mssg: mssg__eof_in_doctype
		}]
	}

	if t.char in whitespace {
		return t.after_doctype_system_identifier_state()
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	// parse error
	println('Unexpected character after doctype system identifier.')
	t.reconsume()
	t.state = .bogus_doctype
	return t.emit_token()
}

// 13.2.5.68
fn (mut t Tokenizer) bogus_doctype_state() []Token {
	t.consume() or {
		t.state = .eof
		return [t.token, EOFToken{}]
	}

	if t.char == `>` {
		t.state = .data
		return [t.token]
	}

	if t.char == null {
		// parse error
		println('Unexpected null character.')
		return t.bogus_doctype_state()
	}

	return t.bogus_doctype_state()
}

// 13.2.5.69
fn (mut t Tokenizer) cdata_section_state() []Token {
	t.consume() or {
		// parse error
		println('EOF in CDATA.')
		t.state = .eof
		return [EOFToken{}]
	}

	if t.char == `]` {
		t.state = .cdata_section_bracket
		return t.emit_token()
	}

	return [CharacterToken{t.char}]
}

// 13.2.5.70
fn (mut t Tokenizer) cdata_section_bracket_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .cdata_section
		return [Token(CharacterToken{`]`})]
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `]` {
		t.state = .cdata_section_end
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.71
fn (mut t Tokenizer) cdata_section_end_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = .cdata_section_bracket
		return [Token(CharacterToken{`]`})]
	}

	t.consume() or {
		return anything_else()
	}

	if t.char == `]` {
		return [CharacterToken{`]`}]
	}

	if t.char == `>` {
		t.state = .data
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.72
fn (mut t Tokenizer) character_reference_state() []Token {
	anything_else := fn [mut t] () []Token {
		toks := t.flush_codepoints()		
		t.reconsume()
		t.state = t.return_state
		t.return_state = .@none
		return if toks.len == 0 {
			t.emit_token()
		} else {
			toks
		}
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in ascii_alphanumeric {
		t.reconsume()
		t.state = .named_character_reference
		return t.emit_token()
	}

	if t.char == `#` {
		t.buffer.write_rune(t.char)
		t.state = .numeric_character_reference
		return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.73
// NOTE: this is not implemented according to spec. I don't
// quite understand what exactly it wants me to do.
// https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
fn (mut t Tokenizer) named_character_reference_state() []Token {
	mut char_ref := new_builder(50)
	char_ref.write_rune(`&`)

	anything_else := fn [mut t] () []Token {
		toks := t.flush_codepoints()
		t.state = .ambiguous_ampersand
		return if toks.len > 0 { toks } else { t.ambiguous_ampersand_state() }
	}

	for {
		t.consume() or { return anything_else() }

		if t.char !in ascii_alpha { break }
		char_ref.write_rune(t.char)
	}

	if t.char in whitespace {
		// println
		println('Missing semicolon after character reference parse error.')
		t.char_ref_code = named_char_ref[builder_contents(char_ref)] or {
			t.state = .ambiguous_ampersand
			return t.ambiguous_ampersand_state()
		}
		t.buffer.write_rune(t.char_ref_code)
		toks := t.flush_codepoints()
		t.state = t.return_state
		t.return_state = .@none
		return if toks.len > 0 { toks } else { t.emit_token() }
	}

	if t.char == `;` {
		char_ref.write_rune(`;`)
		t.char_ref_code = named_char_ref[builder_contents(char_ref)] or {
			t.state = .ambiguous_ampersand
			return t.ambiguous_ampersand_state()
		}
		t.buffer.write_rune(t.char_ref_code)
		toks := t.flush_codepoints()
		t.state = t.return_state
		t.return_state = .@none
		return if toks.len > 0 { toks } else { t.emit_token() }
	}

	return anything_else()
}

// 13.2.5.74
fn (mut t Tokenizer) ambiguous_ampersand_state() []Token {
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		t.state = t.return_state
		t.return_state = .@none
		return t.emit_token()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in ascii_alphanumeric {
		if t.return_state in [
			.attribute_value_double_quoted,
			.attribute_value_single_quoted,
			.attribute_value_unquoted
		] {
			mut tok := &(t.token as TagToken)
			mut attr := &(tok.attributes[tok.attributes.len-1])
			attr.value.write_rune(t.char)
			return t.ambiguous_ampersand_state()
		} else {
			return [CharacterToken{t.char}]
		}
	}

	if t.char == `;` {
		// parse error
		println('Unknown named character reference.')
		// t.reconsume()
		// t.state = t.return_state
		// t.return_state = .@none
		// return t.emit_token()
	}

	return anything_else()
}

// 13.2.5.75
fn (mut t Tokenizer) numeric_character_reference_state() []Token {
	t.char_ref_code = 0
	anything_else := fn [mut t] () []Token {
		t.reconsume()
		return t.decimal_character_reference_start_state()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in [`x`, `X`] {
		t.buffer.write_rune(t.char)
		t.state = .hexadecimal_character_reference_start
		return t.hexadecimal_character_reference_start_state()
	}

	return anything_else()
}

// 13.2.5.76
fn (mut t Tokenizer) hexadecimal_character_reference_start_state() []Token {
	anything_else := fn [mut t] () []Token {
		// parse error
		println('Absence of digits in numeric character reference')
		toks := t.flush_codepoints()
		t.reconsume()
		t.state = t.return_state
		t.return_state = .@none
		return if toks.len > 0 {
			toks
		} else {
			t.emit_token()
		}
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in hex_digits_lower || t.char in hex_digits_upper {
		t.reconsume()
		t.state = .hexadecimal_character_reference
		return t.hexadecimal_character_reference_state()
	}

	return anything_else()
}

// 13.2.5.77
fn (mut t Tokenizer) decimal_character_reference_start_state() []Token {
	anything_else := fn [mut t] () []Token {
		// parse error
		println('Absence of digits in numeric character reference')
		toks := t.flush_codepoints()
		t.reconsume()
		t.state = t.return_state
		t.return_state = .@none
		return if toks.len > 0 {
			toks
		} else {
			t.emit_token()
		}
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in decimal_digits {
		t.reconsume()
		t.state = .decimal_character_reference
		return t.decimal_character_reference_state()
	}

	return anything_else()
}

// 13.2.5.78
fn (mut t Tokenizer) hexadecimal_character_reference_state() []Token {
	anything_else := fn [mut t] () []Token {
		// parse error
		println('Missing semicolor after character reference.')
		t.reconsume()
		t.state = .numeric_character_reference
		return t.numeric_character_reference_state()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in decimal_digits {
		t.char_ref_code *= 16
		t.char_ref_code += t.char - 0x0030
		return t.hexadecimal_character_reference_state()
	}

	if t.char in hex_digits_upper {
		t.char_ref_code *= 16
		t.char_ref_code += t.char - 0x0037
		return t.hexadecimal_character_reference_state()
	}

	if t.char in hex_digits_lower {
		t.char_ref_code *= 16
		t.char_ref_code += t.char - 0x0057
		return t.hexadecimal_character_reference_state()
	}

	if t.char == `;` {
		t.state = .numeric_character_reference_end
		return t.numeric_character_reference_end_state()
	}

	return anything_else()
}

// 13.2.5.79
fn (mut t Tokenizer) decimal_character_reference_state() []Token {
	anything_else := fn [mut t] () []Token {
		// parse error
		println('Missing semicolon after character reference parse error.')
		t.reconsume()
		t.state = .numeric_character_reference_end
		return t.numeric_character_reference_end_state()
	}

	t.consume() or {
		return anything_else()
	}

	if t.char in decimal_digits {
		t.char_ref_code *= 10
		t.char_ref_code += t.char - 0x0030
		return t.decimal_character_reference_state()
	}

	if t.char == `;` {
		t.state = .numeric_character_reference_end
		return t.numeric_character_reference_end_state()
	}

	return anything_else()
}

// 13.2.5.80
fn (mut t Tokenizer) numeric_character_reference_end_state() []Token {
	if t.char_ref_code == 0x00 {
		// parse error
		println('Null character parse error.')
		t.char_ref_code = 0xfffd
	} else if t.char_ref_code > 0x10ffff {
		// parse error
		println('Character reference outside unicode range.')
		t.char_ref_code = 0xfffd
	} else if is_surrogate(t.char_ref_code) {
		// parser error
		println('Surrogate character reference.')
		t.char_ref_code = 0xfffd
	} else if is_noncharacter(t.char_ref_code) {
		// parse error
		println('Noncharacter character reference.')
	} else if t.char_ref_code == 0x0d || (is_control(t.char_ref_code) && t.char_ref_code !in whitespace) {
		// parse error
		println('Control character reference.')
		table := {
			rune(0x80): rune(0x20ac),
			0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e, 0x85: 0x2026,
			0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02c6, 0x89: 0x2030,
			0x8a: 0x0160, 0x8b: 0x2039, 0x8c: 0x0152, 0x8e: 0x017d,
			0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201c, 0x94: 0x201d,
			0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02dc,
			0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a, 0x9c: 0x0153,
			0x9e: 0x017e, 0x9f: 0x0178
		}
		t.char_ref_code = table[t.char_ref_code] or { t.char_ref_code }
	}

	t.buffer = new_builder(10)
	t.buffer.write_rune(t.char_ref_code)
	toks := t.flush_codepoints()
	t.state = t.return_state
	t.return_state = .@none
	return if toks.len > 0 { toks } else { t.emit_token() }
}