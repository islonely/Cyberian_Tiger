module parser

import strings { Builder, new_builder }

type Token = DoctypeToken | TagToken | CommentToken | CharacterToken | EOFToken

// According to the HTML spec, doctype missing is distinct from an
// empty string. Since V doesn't have null, we're using this since
// it should never show up in an HTML doctype tag.
//
// https://html.spec.whatwg.org/multipage/parsing.html#tokenization
const doctype_missing = Builder('\0\0\0\0\0\0\0\0'.bytes())

// DoctypeToken represents the occurence of <!DOCTYPE ...> in an
// HTML documents.
struct DoctypeToken {
mut:
	name Builder = doctype_missing
	public_identifier Builder = doctype_missing
	system_identifier Builder = doctype_missing
	force_quirks bool
}

[inline]
pub fn (tok DoctypeToken) name() string {
	return builder_contents(tok.name)
}

[inline]
pub fn (tok DoctypeToken) public_identifier() string {
	return builder_contents(tok.public_identifier)
}

[inline]
pub fn (tok DoctypeToken) system_identifier() string {
	return builder_contents(tok.system_identifier)
}

[inline]
pub fn (tok DoctypeToken) str() string {
	return '<!DOCTYPE $tok.name' + if tok.public_identifier != doctype_missing {'public="$tok.public_identifier()"'} else {''} + if tok.system_identifier != doctype_missing {' system="$tok.system_identifier()"'} else {''} + '>'
}

// TagToken represents the occurence of <tag attribute="value"></tag>
// in an HTML document.
struct TagToken {
	is_start bool = true
mut:
	self_closing bool
	// <blockquote> is the longest (10 characters) HTML tag name.
	name Builder = strings.new_builder(10)
	attributes []Attribute
}

// name returns the contents of the `TagToken.name` field.
[inline]
pub fn (tok TagToken) name() string {
	return builder_contents(tok.name)
}

// str returns the HTML representation of the `TagToken`.
[inline]
pub fn (tok TagToken) str() string {
	mut bldr := new_builder(100)
	if !tok.is_start {
		return '</' + tok.name() + '>'
	}
	bldr.write_string('<$tok.name()')
	for attr in tok.attributes {
		bldr.write_string(' $attr.name()="$attr.value()"')
	}
	bldr.write_string(if tok.self_closing {' />'} else {'>'})
	return bldr.str()
}

// Attribute represents the occurence of tag attributes in an HTML
// document.
struct Attribute {
mut:
	// onloadedmetadata is the longest (16 characters) vanilla HTML
	// attribute.
	name Builder = strings.new_builder(16)
	value Builder = strings.new_builder(100)
}

[inline]
pub fn (attr Attribute) name() string {
	return builder_contents(attr.name)
}

[inline]
pub fn (attr Attribute) value() string {
	return builder_contents(attr.value)
}

// CommentToken represents the characters inside a comment in an HTML
// document.
struct CommentToken {
mut:
	data Builder = strings.new_builder(50)
}

[inline]
pub fn (tok CommentToken) data() string {
	return builder_contents(tok.data)
}

[inline]
pub fn (mut tok CommentToken) str() string {
	return '<!--$tok.data.str()-->'
}

// CharacterToken represents consecutive characters in an HTML
// document.
struct CharacterToken {
	data rune
}

[inline]
pub fn (tok CharacterToken) str() string {
	return '$tok.data'
}

// string_to_tokens converts a string into an array of CharacterTokens.
fn string_to_tokens(str string) []Token {
	mut toks := []Token{cap: str.runes().len}
	for r in str.runes() {
		toks << CharacterToken{data: r}
	}
	return toks
}

// NOTE: It makes more sense to me to combine all consecutive
// characters into one token. I assume the spec would've taken
// this into account, but I wrote this just in case.

// // CharacterToken represents consecutive characters in an HTML
// // document.
// struct CharacterToken {
// mut:
// 	data Builder = strings.new_builder(50)
// }

// [inline]
// pub fn (tok CharacterToken) data() string {
// 	return builder_contents(tok.data)
// }

struct EOFToken {
	name string = 'EOF'
	mssg string = 'End of file.'
}