module parser

import datatypes { Stack }
import dom
import net.http

const(
	auto_self_closers = [
		'input'
		'br'
		'link'
		'meta'
	]
)

// InsertionMode is the state of `Parser`.
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

// parse_url fetches the HTML data from a URL and parses it.
// Returns an error if the connection to the URL fails.
pub fn parse_url(url string) ?&dom.Document {
	res := http.get(url)?
	mut p := parser.new(res.body.runes())
	p.parse()
	return p.doc
}

// parse_runes parses the HTML data provided as an array of
// runes.
pub fn parse_runes(src []rune) &dom.Document {
	mut p := new(src)
	p.parse()
	return p.doc
}

// Parser parses the tokens emitted from the Tokenizer.
struct Parser {
	source []rune
mut:
	tokenizer                Tokenizer
	insertion_mode           InsertionMode = .initial
	original_insertion_mode  InsertionMode = .@none
	template_insertion_modes Stack<InsertionMode>
	ots						 OpenTagStack
	doc                      &dom.Document = &dom.Document{}
}

// new instantiates a Parser out of the provided runes.
pub fn new(src []rune) Parser {
	return Parser{
		source: src
		tokenizer: Tokenizer{
			source: src
		}
	}
}

// new_url instantiates a parser from a URL.
pub fn new_url(url string) Parser {
	src := http.get_text(url).runes()
	return new(src)
}

// parse parses the tokens emitted from the Tokenizer.
pub fn (mut p Parser) parse() &dom.Document {
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
	
	if p.doc.children().len > 0 {
		c := p.doc.children()
		p.doc.first_child = c[0]
		p.doc.last_child = c[c.len-1]
	}

	return p.doc
}

// parse_character_token parses CharacterToken's emitted from the Tokenizer.
fn (mut p Parser) parse_character_token(tok CharacterToken) {
	if p.ots.len() > 0 {
		mut last := &(p.ots.peek() as dom.Element)
		last.text_content += tok.data.str()
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
		mut n := &dom.Node(p.doc.create_element(tok.name()))
		mut elem := &(n as dom.Element)
		for attr in tok.attributes {
			elem.set_attribute_node(dom.new_attribute(elem.namespace_uri, '', attr.name(), attr.value(), elem))
		}

		if p.ots.len() > 0 {
			mut lastn := p.ots.peek()
			mut last := &(lastn as dom.Element)
			last.append_child(n)
		} else {
			p.doc.append_child(n)
		}

		if !tok.self_closing && tok.name() !in auto_self_closers {
			p.ots.push(n)
		}
	} else {
		if p.ots.len() > 0 {
			lastn := p.ots.peek()
			last := &(lastn as dom.Element)
			if last.local_name == tok.name() {
				p.ots.pop()
			}
		} else {
			println('Parse Error: Encountered closing tag; no start tags open.')
		}
	}
}

// parse_eof_token parses EOFToken's emitted from the Tokenizer.
fn (mut p Parser) parse_eof_token(tok EOFToken) {
	println('EOF#$tok.name: $tok.mssg')
}
