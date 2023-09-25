module parser

import dom
import net.http

// DOCTYPE conditions; see `fn Parser.initial_insertion_mode()`
const (
	public_id_matches                          = [
		'-//W3O//DTD W3 HTML Strict 3.0//EN//',
		'-/W3C/DTD HTML 4.0 Transitional/EN',
		'HTML',
	]
	public_id_starts_with                      = [
		'+//Silmaril//dtd html Pro v0r11 19970101//',
		'-//AS//DTD HTML 3.0 asWedit + extensions//',
		'-//AdvaSoft Ltd//DTD HTML 3.0 asWedit + extensions//',
		'-//IETF//DTD HTML 2.0 Level 1//',
		'-//IETF//DTD HTML 2.0 Level 2//',
		'-//IETF//DTD HTML 2.0 Strict Level 1//',
		'-//IETF//DTD HTML 2.0 Strict Level 2//',
		'-//IETF//DTD HTML 2.0 Strict//',
		'-//IETF//DTD HTML 2.0//',
		'-//IETF//DTD HTML 2.1E//',
		'-//IETF//DTD HTML 3.0//',
		'-//IETF//DTD HTML 3.2 Final//',
		'-//IETF//DTD HTML 3.2//',
		'-//IETF//DTD HTML 3//',
		'-//IETF//DTD HTML Level 0//',
		'-//IETF//DTD HTML Level 1//',
		'-//IETF//DTD HTML Level 2//',
		'-//IETF//DTD HTML Level 3//',
		'-//IETF//DTD HTML Strict Level 0//',
		'-//IETF//DTD HTML Strict Level 1//',
		'-//IETF//DTD HTML Strict Level 2//',
		'-//IETF//DTD HTML Strict Level 3//',
		'-//IETF//DTD HTML Strict//',
		'-//IETF//DTD HTML//',
		'-//Metrius//DTD Metrius Presentational//',
		'-//Microsoft//DTD Internet Explorer 2.0 HTML Strict//',
		'-//Microsoft//DTD Internet Explorer 2.0 HTML//',
		'-//Microsoft//DTD Internet Explorer 2.0 Tables//',
		'-//Microsoft//DTD Internet Explorer 3.0 HTML Strict//',
		'-//Microsoft//DTD Internet Explorer 3.0 HTML//',
		'-//Microsoft//DTD Internet Explorer 3.0 Tables//',
		'-//Netscape Comm. Corp.//DTD HTML//',
		'-//Netscape Comm. Corp.//DTD Strict HTML//',
		"-//O'Reilly and Associates//DTD HTML 2.0//",
		"-//O'Reilly and Associates//DTD HTML Extended 1.0//",
		"-//O'Reilly and Associates//DTD HTML Extended Relaxed 1.0//",
		'-//SQ//DTD HTML 2.0 HoTMetaL + extensions//',
		'-//SoftQuad Software//DTD HoTMetaL PRO 6.0::19990601::extensions to HTML 4.0//',
		'-//SoftQuad//DTD HoTMetaL PRO 4.0::19971010::extensions to HTML 4.0//',
		'-//Spyglass//DTD HTML 2.0 Extended//',
		'-//Sun Microsystems Corp.//DTD HotJava HTML//',
		'-//Sun Microsystems Corp.//DTD HotJava Strict HTML//',
		'-//W3C//DTD HTML 3 1995-03-24//',
		'-//W3C//DTD HTML 3.2 Draft//',
		'-//W3C//DTD HTML 3.2 Final//',
		'-//W3C//DTD HTML 3.2//',
		'-//W3C//DTD HTML 3.2S Draft//',
		'-//W3C//DTD HTML 4.0 Frameset//',
		'-//W3C//DTD HTML 4.0 Transitional//',
		'-//W3C//DTD HTML Experimental 19960712//',
		'-//W3C//DTD HTML Experimental 970421//',
		'-//W3C//DTD W3 HTML//',
		'-//W3O//DTD W3 HTML 3.0//',
		'-//WebTechs//DTD Mozilla HTML 2.0//',
		'-//WebTechs//DTD Mozilla HTML//',
	]
	public_id_starts_with_if_system_id_missing = [
		'-//W3C//DTD HTML 4.01 Frameset//',
		'-//W3C//DTD HTML 4.01 Transitional//',
	]
)

const implied_end_tag_names = ['caption', 'colgroup', 'dd', 'li', 'optgroup', 'option',
	'p', 'rb', 'rp', 'rt', 'rtc', 'tbody', 'td', 'tfoot', 'th', 'thead']

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

// https://html.spec.whatwg.org/multipage/parsing.html#the-list-of-active-formatting-elements
pub enum AFEMarker {
	applet
	object
	marquee
	template
	td
	th
	caption
}

pub type ActiveFormattingElements = AFEMarker | dom.HTMLElement

// https://html.spec.whatwg.org/multipage/parsing.html#other-parsing-state-flags
pub enum ScriptingFlag {
	enabled
	disabled
}

// https://html.spec.whatwg.org/multipage/parsing.html#other-parsing-state-flags
pub enum FramesetOKFlag {
	ok
	not_ok
}

pub type OpenElements = []&dom.NodeInterface

// has_by_tag_name searches the open elements for a tag with the given tag name
// and returns true if it's found; false if not.
pub fn (open_elements OpenElements) has_by_tag_name(tag_name string) bool {
	for element in open_elements {
		el := &dom.HTMLElement(element)
		println(el.local_name)
		if el.local_name == tag_name {
			return true
		}
	}
	return false
}

// Parser parses the tokens emitted from the Tokenizer and creates
// a document tree which is returned from `fn (mut Parser) parse`.
struct Parser {
mut:
	tokenizer                Tokenizer
	insertion_mode           InsertionMode = .initial
	original_insertion_mode  InsertionMode = .@none
	scripting                ScriptingFlag = .disabled
	frameset_ok              FramesetOKFlag = .ok
	template_insertion_modes []InsertionMode
	open_elems               OpenElements
	active_formatting_elems  []&ActiveFormattingElements
	doc                      &dom.Document = dom.Document.new()
	// adjusted_current_NodeBase    &dom.NodeBase
	last_token      Token
	current_token   Token
	next_token      Token
	reconsume_token bool
}

// Parser.from_string instantiates a Parser from the source string.
[inline]
pub fn Parser.from_string(src string) Parser {
	return Parser.from_runes(src.runes())
}

// Parser.from_runes instantiates a Parser from the source rune array.
pub fn Parser.from_runes(src []rune) Parser {
	mut p := Parser{
		tokenizer: Tokenizer{
			source: src
		}
	}
	p.current_token, p.next_token = p.tokenizer.emit_token(), p.tokenizer.emit_token()
	return p
}

// Parser.from_url instantiates a Parser from the contents at the provided URL
// or returns an error upon network failure or status code other than 200.
pub fn Parser.from_url(url string) !Parser {
	res := http.get(url)!
	if res.status_code != 200 {
		return error('URL get request returned status code ${res.status_code}: ${res.status_msg}')
	}
	mut p := Parser.from_runes(res.body.runes())
	p.doc.base_uri = url
	return p
}

// parse parses the tokens emitted from the Tokenizer and returns
// the document tree of the parsed content or `none`.
pub fn (mut p Parser) parse() &dom.Document {
	for p.tokenizer.state != .eof {
		match p.insertion_mode {
			.@none {}
			.after_after_body {}
			.after_after_frameset {}
			.after_body {}
			.after_frameset {}
			.after_head {}
			.before_head { p.before_head_insertion_mode() }
			.before_html { p.before_html_insertion_mode() }
			.initial { p.initial_insertion_mode() }
			.in_body {}
			.in_caption {}
			.in_cell {}
			.in_column_group {}
			.in_frameset {}
			.in_head {}
			.in_head_no_script {}
			.in_row {}
			.in_select {}
			.in_select_in_table {}
			.in_table {}
			.in_table_body {}
			.in_table_text {}
			.in_template {}
			.text {}
		}

		if p.reconsume_token {
			p.reconsume_token = false
		} else {
			p.consume_token()
		}
	}

	return p.doc
}

// consume_token sets the current token to the next token
// and gets the next token from the tokenizer.
[inline]
fn (mut p Parser) consume_token() {
	p.last_token, p.current_token, p.next_token = p.current_token, p.next_token, p.tokenizer.emit_token()
}

// before_html_insertion mode is the mode the parser is in when
// `Parser.next_token` is an open tag HTML tag (<html>).
// https://html.spec.whatwg.org/multipage/parsing.html#the-before-html-insertion-mode
fn (mut p Parser) before_html_insertion_mode() {
	anything_else := fn [mut p] () {
		mut child := dom.HTMLHtmlElement.new(p.doc)
		p.open_elems << child
		p.insertion_mode = .before_head
		p.reconsume_token = true
	}
	match mut p.current_token {
		DoctypeToken {
			put(typ: .notice, text: 'Ignoring DOCTYPE token.')
		}
		CommentToken {
			mut child := dom.CommentNode.new(p.doc, p.current_token.data())
			p.doc.append_child(child)
		}
		CharacterToken {
			if p.current_token in whitespace {
			} else {
				anything_else()
			}
		}
		TagToken {
			if p.current_token.is_start {
				if p.current_token.name() == 'html' {
					mut child := dom.HTMLHtmlElement.new(p.doc)
					p.doc.append_child(child)
					p.open_elems << child
					p.insertion_mode = .before_head
				} else {
					anything_else()
				}
			} else {
				if p.current_token.name() in ['head', 'body', 'html', 'br'] {
					anything_else()
				} else {
					put(typ: .notice, text: 'Ignoring end tag token: ${p.current_token.html}')
				}
			}
		}
		else {
			anything_else()
		}
	}
}

// initial_insertion_mode is the mode that the parser starts in. From
// here it goes to another mode and should never return to this mode.
// https://html.spec.whatwg.org/multipage/parsing.html#the-initial-insertion-mode
fn (mut p Parser) initial_insertion_mode() {
	match mut p.current_token {
		CharacterToken {
			if p.current_token in whitespace {
				return
			}
		}
		CommentToken {
			mut child := dom.CommentNode.new(p.doc, p.current_token.data())
			p.doc.append_child(child)
		}
		DoctypeToken {
			if p.current_token.name() != 'html' {
				put(text: 'invalid doctype name: ${p.current_token.html()}')
			}
			if p.current_token.public_identifier != doctype_missing {
				put(text: 'public identifier is not missing: ${p.current_token.html()}')
			}
			if p.current_token.system_identifier !in [doctype_missing, 'about:legacy-compat'.bytes()] {
				put(
					text: 'system identifier is not missing or "about:legacy-compat": ${p.current_token.html()}'
				)
			}

			mut doctype := &dom.DocumentType{
				node_type: .document_type
				name: p.current_token.name.str()
				public_id: p.current_token.public_identifier.str()
				system_id: p.current_token.system_identifier.str()
				owner_document: p.doc
			}
			p.doc.append_child(doctype)
			p.doc.doctype = doctype

			if /* p.doc is not iframe srcdoc document && */ !p.doc.parser_cannot_change_mode
				&& (p.current_token.force_quirks || doctype.name != 'html') {
				p.doc.mode = .quirks
			}
			if doctype.public_id in parser.public_id_matches {
				p.doc.mode = .quirks
			}
			for val in parser.public_id_starts_with {
				if doctype.public_id.starts_with(val) {
					p.doc.mode = .quirks
					break
				}
			}
			for val in parser.public_id_starts_with_if_system_id_missing {
				if p.current_token.system_identifier == doctype_missing
					&& doctype.public_id.starts_with(val) {
					p.doc.mode = .quirks
					break
				}
			}
			if p.doc.mode != .quirks {
				if /* p.doc is not iframe srcdoc document && */ !p.doc.parser_cannot_change_mode
					&& (doctype.public_id.starts_with('-//W3C//DTD XHTML 1.0 Frameset//')
					|| doctype.public_id.starts_with('-//W3C//DTD XHTML 1.0 Transitional//')
					|| (p.current_token.system_identifier == doctype_missing
					&& doctype.public_id.starts_with('-//W3C//DTD HTML 4.01 Frameset//'))
					|| (p.current_token.system_identifier == doctype_missing
					&& doctype.public_id.starts_with('-//W3C//DTD HTML 4.01 Transitional//'))) {
					p.doc.mode = .limited_quirks
				}
			}
			p.insertion_mode = .before_html
		}
		else {
			if /* p.doc is not iframe srcdoc document && */ !p.doc.parser_cannot_change_mode {
				p.doc.mode = .quirks
				// parse error if no iframe srcdoc document
			}
			p.insertion_mode = .before_html
		}
	}
}

// before_head_insertion_mode
// https://html.spec.whatwg.org/multipage/parsing.html#the-before-head-insertion-mode
fn (mut p Parser) before_head_insertion_mode() {
	anything_else := fn [mut p] () {
		mut child := dom.HTMLHeadElement.new(p.doc)
		p.doc.head = child
		mut last := p.open_elems.last()
		last.append_child(child)
		p.insertion_mode = .in_head
		return
	}
	match mut p.current_token {
		CharacterToken {
			if p.current_token in parser.whitespace {
				return
			}

			anything_else()
		}
		CommentToken {
			p.insert_comment()
		}
		DoctypeToken {
			put(
				typ: .notice
				text: 'Invalid DOCTYPE token. Ignoring token.'
			)
		}
		TagToken {
			if p.current_token.is_start {
				if p.current_token.name() == 'html' {
					p.in_body_insertion_mode()
					return
				}

				if p.current_token.name() == 'head' {
					mut child := dom.HTMLHeadElement.new(p.doc)
					mut last := p.open_elems.last()
					p.doc.head = child
					last.append_child(child)
					p.open_elems << child
					p.insertion_mode = .in_head
					return
				}

				anything_else()
				return
			}
			
			if p.current_token.name() in ['head', 'body', 'html', 'br'] {
				anything_else()
				return
			}

			put(
				typ: .notice
				text: 'Invalid end tag token. Ignoring token.'
			)
		}
		else {
			anything_else()
		}
	}
}

// in_head_insertion_mode
// https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inhead
fn (mut p Parser) in_head_insertion_mode() {
	anything_else := fn [mut p] () {

	}

	match mut p.current_token {
		CharacterToken {
			if p.current_token in parser.whitespace {
				p.insert_text(p.current_token.str())
			}
		}
		CommentToken {
			p.insert_comment()
		}
		DoctypeToken {
			put(
				typ: .notice
				text: 'Invalid DOCTYPE token. Ignoring token.'
			)
		}
		TagToken {
			mut last_opened_elem := p.open_elems.last()
			tag_name := p.current_token.name()
			if p.current_token.is_start {
				if tag_name == 'html' {
					p.in_body_insertion_mode()
					return
				} else if tag_name in ['base', 'basefont', 'bgsound', 'link'] {
					mut child := match tag_name {
						'base' {
							&dom.HTMLElement(dom.HTMLBaseElement.new(p.doc))
						}
						'basefont' {
							&dom.HTMLElement(&dom.HTMLElement{
								owner_document: p.doc
								node_name: 'basefont'
							})
						}
						'bgsound' {
							// todo: replace with appropriate element
							&dom.HTMLElement(&dom.HTMLElement{
								owner_document: p.doc
								node_name: 'bgsound'
							})
						}
						'link' {
							&dom.HTMLElement(dom.HTMLLinkElement.new(p.doc))
						}
						else {
							put(
								typ: .fatal
								text: 'Unexpected tag name in in_head_insertion_mode > TagToken > "${tag_name}"'
							)
							exit(1)
						}
					}
					last_opened_elem.append_child(child)
					// Do not add to open elems per spec: "immediately pop
					// the current node off the stack of open elements."
					// We have not pushed it yet; no pop is needed.
					return
				} else if tag_name == 'meta' {
					mut child := dom.HTMLMetaElement.new(p.doc)
					last_opened_elem.append_child(child)
					// Do not add to open elems per spec: "immediately pop
					// the current node off the stack of open elements."
					// We have not pushed it yet; no pop is needed.

					// todo: implement substeps 1 and 2 from
					// https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inhead
				} else if tag_name == 'title' {
					// https://html.spec.whatwg.org/multipage/parsing.html#generic-rcdata-element-parsing-algorithm
					mut child := dom.HTMLElement{
						owner_document: p.doc
						local_name: 'title'
					}
					last_opened_elem.append_child(child)
					p.open_elems << child
					p.tokenizer.state = .rcdata
					p.original_insertion_mode = p.insertion_mode
					p.insertion_mode = .text
					return
				} else if (tag_name == 'noscript' && p.doc.scripting) || tag_name in ['noframes', 'style'] {
					mut child := match tag_name {
						'noscript' {
							&dom.HTMLElement(&dom.HTMLElement{
								owner_document: p.doc
								local_name: 'noscript'
							})
						}
						'noframes' {
							&dom.HTMLElement(&dom.HTMLElement{
								owner_document: p.doc
								local_name: 'noframes'
							})
						}
						'style' {
							&dom.HTMLElement(dom.HTMLStyleElement.new(p.doc))
						}
						else {
							put(
								typ: .warning
								text: 'Unexpected tag name in in_head_insertion_mode > TagToken > "${tag_name}"'
							)
							return
						}
					}
					last_opened_elem.append_child(child)
					p.open_elems << child
					p.tokenizer.state = .rawtext
					p.original_insertion_mode = p.insertion_mode
					p.insertion_mode = .text
					return
				} else if tag_name == 'noscript' && !p.doc.scripting {
					mut child := &dom.HTMLElement{
						owner_document: p.doc
						local_name: 'noscript'
					}
					last_opened_elem.append_child(child)
					p.insertion_mode = .in_head_no_script
					return
				} else if tag_name == 'script' {
					mut child := dom.HTMLScriptElement.new(p.doc)
					child.namespace_uri = dom.namespaces[dom.NamespaceURI.html]
					child.force_async = false
					// "if the parser was created as part of the HTML fragment parsing algorithm
					// then set the script element's already started to true"
					// "If the parser was invoked via the document.write() or document.writeln()
					// methods, then optionally set the script element's already started to true.
					// (For example, the user agent might use this clause to prevent execution of
					// cross-origin scripts inserted via document.write() under slow network conditions,
					// or when the page has already taken a long time to load.)"
					last_opened_elem.append_child(child)
					p.open_elems << child
					p.tokenizer.state = .script_data
					p.original_insertion_mode = p.insertion_mode
					p.insertion_mode = .text
					return
				} else if tag_name == 'template' {
					mut child := dom.HTMLTemplateElement.new(p.doc)
					p.open_elems << child
					p.active_formatting_elems << AFEMarker.template
					p.frameset_ok = .not_ok
					p.insertion_mode = .in_template
					p.template_insertion_modes << .in_template
				}
			} else {
				// end tag
				if tag_name == 'head' {
					_ := p.open_elems.pop()
					p.insertion_mode = .after_head
					return
				} else if tag_name in ['body', 'html', 'br'] {
					anything_else()
					return
				} else if tag_name == 'template' {
					if !p.open_elems.has_by_tag_name('template') {
						put(
							typ: .warning
							text: 'Unexpected </template> tag token; ingoring token.'
						)
						return
					}

					p.generate_all_implied_end_tags_thorougly()
					if p.open_elems.len == 0 {
						put(
							typ: .warning
							text: 'Unexpected </template> tag token; ignoring token.'
						)
						return
					}
					mut template_element := p.open_elems.last()
					if &dom.HTMLElement(template_element).local_name != 'template' {
						put(
							typ: .warning
							text: 'Current node is not a <template> tag.'
						)
					}
					for &dom.HTMLElement(template_element).local_name != 'template' {
						if p.open_elems.len == 0 {
							put(
								typ: .warning
								text: 'There were no <template> tags in the parser\'s stack of open elements.'
							)
							break
						}
						template_element = p.open_elems.pop()
					}
					p.clear_active_formatting_elements_to_last_marker()
					if p.template_insertion_modes.len != 0 {
						p.template_insertion_modes.pop()
					} else {
						put(
							typ: .warning
							text: 'There were no items on the parer\'s stack of template insertion modes.'
						)
					}
					p.reset_insertion_mode_appropriately()
				}
			}
		}
		else {}
	}
}

fn (mut p Parser) in_body_insertion_mode() {}

// insert_comment adds a comment to the last opened element (and always assumes
// an element is open).
// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-comment
fn (mut p Parser) insert_comment() {
	if mut p.current_token is CommentToken {
		mut child := dom.CommentNode.new(p.doc, p.current_token.data())
		mut last := p.open_elems.last()
		last.append_child(child)
		return
	}

	put(
		typ: .warning
		text: 'Current token is not a comment.'
	)
}

// insert_text inserts a string into a dom.Text node or creates a new
// one and adds it to the last opened element.
//
// NOTE: Skipping steps 1 and 2 right now.
// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-character
fn (mut p Parser) insert_text(text string) {
	// Step 3:
	// "If the adjusted insertion location is in a Document node, then return.
	// The DOM will not let Document nodes have Text node children, so they are
	// dropped on the floor."
	if p.open_elems.len == 0 {
		put(
			typ: .notice
			text: 'Text nodes cannot be inserted in DOM root. They must go inside an open element. Ignoring token.'
		)
		return
	}

	// Step 4:
	// "If there is a Text node immediately before the adjusted insertion location, then
	// append data to that Text node's data. Otherwise, create a new Text node whose
	// data is data and whose node document is the same as that of the element in which
	// the adjusted insertion location finds itself, and insert the newly created node
	// at the adjusted insertion location."
	mut last_elem := p.open_elems.last()
	insert_text_node := fn [mut p, mut last_elem, text] () {
		mut text_node := dom.Text.new(p.doc, text)
		last_elem.append_child(text_node)
	}

	if last_elem.has_child_nodes() {
		if mut last_elems_last_child := last_elem.last_child {
			if mut last_elems_last_child is dom.Text {
				last_elems_last_child.data += text
				return
			}
			insert_text_node()
			return
		}
		insert_text_node()
		return
	}

	insert_text_node()
}

[params]
pub struct GenerateImpliedTagsParams {
__global:
	exclude []string
}

// https://html.spec.whatwg.org/multipage/parsing.html#closing-elements-that-have-implied-end-tags
fn (mut p Parser) generate_all_implied_end_tags_thorougly(params GenerateImpliedTagsParams) {
	put(
		typ: .warning
		text: 'todo: implement generate implied end tags'
	)
}

// https://html.spec.whatwg.org/multipage/parsing.html#clear-the-list-of-active-formatting-elements-up-to-the-last-marker
fn (mut p Parser) clear_active_formatting_elements_to_last_marker() {
	for p.active_formatting_elems.len > 0 {
		if p.active_formatting_elems.pop() is AFEMarker {
			break
		}
	}
}

// https://html.spec.whatwg.org/multipage/parsing.html#reset-the-insertion-mode-appropriately
fn (mut p Parser) reset_insertion_mode_appropriately() {
	mut last := false
	mut node_index := p.open_elems.len - 1
	mut node := p.open_elems[node_index]
	for {
		if node == p.open_elems.first() {
			last = true
			// if the parser was created as part of the HTML fragment parsing algorithm
			// set the node to the context element passed to that algorithm
		}
		
		if mut node is dom.HTMLSelectElement {
			if last {
				p.insertion_mode = .in_select
				return
			}
			mut ancestor := p.open_elems.first()
			if mut ancestor is dom.HTMLTemplateElement {
				p.insertion_mode = .in_select
				return
			}
			if mut ancestor is dom.HTMLTableElement {
				p.insertion_mode = .in_select_in_table
				return
			}
			continue
		}

		html_node := &dom.HTMLElement(node)
		// todo: this should actually test with
		// `if html_node is dom.HTMLBodyElement` instead
		// of comparing the local name.
		if html_node.local_name in ['td', 'th'] && !last {
			p.insertion_mode = .in_cell
			return
		}
		if html_node.local_name == 'tr' {
			p.insertion_mode = .in_row
			return
		}
		if html_node.local_name in ['tbody', 'thead', 'tfoot'] {
			p.insertion_mode = .in_table_body
			return
		}
		if html_node.local_name == 'caption' {
			p.insertion_mode = .in_caption
			return
		}
		if html_node.local_name == 'colgroup' {
			p.insertion_mode = .in_column_group
			return
		}
		if html_node.local_name == 'table' {
			p.insertion_mode = .in_table
			return
		}
		if html_node.local_name == 'template' {
			p.insertion_mode = p.template_insertion_modes.last()
			return
		}
		if html_node.local_name == 'head' {
			p.insertion_mode = .in_head
			return
		}
		if html_node.local_name == 'body' {
			p.insertion_mode = .in_body
			return
		}
		if html_node.local_name == 'frameset' {
			p.insertion_mode = .in_frameset
			return
		}
		if html_node.local_name == 'html' {
			p.insertion_mode = if p.doc.head == none {
				.before_head
			} else {
				.after_head
			}
			return
		}
		if last {
			p.insertion_mode = .in_body
			return
		}

		node_index--
		node = p.open_elems[node_index]
	}
}