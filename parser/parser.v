module parser

import datatypes { Stack }
import dom
import net.http

enum InsertionMode {
	@none
	after_after_body
	after_after_frameset
	after_body
	after_frameset
	after_head
	before_head
	before_html
	initial
	in_body
	in_caption
	in_cell
	in_column_group
	in_frameset
	in_head
	in_head_no_script
	in_row
	in_select
	in_select_in_table
	in_table
	in_table_body
	in_table_text
	in_template
	text
}

// Parser parses the tokens emitted from the Tokenizer.
struct Parser {
	source []rune
mut:
	tokenizer                Tokenizer
	insertion_mode           InsertionMode = .initial
	original_insertion_mode  InsertionMode = .@none
	template_insertion_modes Stack<InsertionMode>
	open_tags                []&dom.Element
	doc                      &dom.Document = &dom.Document{}
}

// new instantiates a Parser
pub fn new(src []rune) Parser {
	return Parser{
		source: src
		tokenizer: Tokenizer{
			source: src
		}
	}
}

pub fn new_url(url string) Parser {
	src := http.get_text(url).runes()
	return new(src)
}

// parse parses the tokens emitted from the Tokenizer.
pub fn (mut p Parser) parse() {
	for p.tokenizer.state != .eof {
		tokens := p.tokenizer.emit_token()
		for tok in tokens {
			match tok {
				CharacterToken { p.parse_character_token(tok) }
				CommentToken { p.parse_comment_token(tok) }
				DoctypeToken { p.parse_doctype_token(tok) }
				TagToken { p.parse_tag_token(tok) }
				EOFToken { p.parse_eof_token(tok) }
			}
		}
	}
	// println(p.doc.children())
}

// parse_character_token parses CharacterToken's emitted from the Tokenizer.
fn (mut p Parser) parse_character_token(tok CharacterToken) {
	if p.open_tags.len > 0 {
		mut last_opened := p.open_tags.last()
		last_opened.text_content += tok.data.str()
	} else {
		p.doc.text_content += tok.data.str()
	}
}

// parse_comment_token parses CommentToken's emitted from the Tokenizer.
fn (mut p Parser) parse_comment_token(tok CommentToken) {
}

// parse_doctype_token parses DoctypeToken's emitted from the Tokenizer.
fn (mut p Parser) parse_doctype_token(tok DoctypeToken) {
	p.doc.doctype = &dom.Doctype{
		name: tok.name()
		public_id: tok.public_identifier()
		system_id: tok.system_identifier()
	}
}

// parse_tag_token parses TagToken's emitted from the Tokenizer.
fn (mut p Parser) parse_tag_token(tok TagToken) {
	if tok.is_start {
		mut elem := p.doc.create_element(tok.name())
		for attr in tok.attributes {
			elem.set_attribute_node(dom.new_attribute(elem.namespace_uri, '', attr.name(), attr.value(), elem))
		}

		if p.open_tags.len > 0 {
			mut last_opened := p.open_tags.last()
			last_opened.append_child(elem)
		} else {
			p.doc.append_child(elem)
		}

		if !tok.self_closing {
			p.open_tags << elem
		}
	} else {
		if p.open_tags.len > 0 {
			mut last_opened := p.open_tags.last()
			if last_opened.local_name == tok.name() {
				p.open_tags.pop()
			}
		} else {
			println('Parse Error: Encountered closing tag, but no tags are opened.')
		}
	}
}

// parse_eof_token parses EOFToken's emitted from the Tokenizer.
fn (mut p Parser) parse_eof_token(tok EOFToken) {
}
