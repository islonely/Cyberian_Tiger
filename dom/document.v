module dom

import strings { new_builder }

const (
	html_namespace   = 'http://www.w3.org/1999/xhtml'
	mathml_namespace = 'http://www.w3.org/1998/Math/MathML'
	svg_namespace    = 'http://www.w3.org/2000/svg'
	xlink_namespace  = 'http://www.w3.org/1999/xlink'
	xml_namespace    = 'http://www.w3.org/XML/1998/namespace'
	xmlns_namespace  = 'http://www.w3.org/2000/xmlns/'
)

[heap]
pub struct Document {
	AbstractNode
__global:
	doctype          &Doctype = 0
	document_element &Element = 0
}

// html returns the HTML representation of `Document`.
pub fn (d Document) html() string {
	mut bldr := new_builder(1000)
	bldr.writeln(d.doctype.html())
	for child in d.child_nodes {
		if child is Element {
			bldr.write_string(child.html())
		}
	}
	return bldr.str()
}

// children returns the `child_nodes` of `Document`.
pub fn (d &Document) children() []&Element {
	mut els := []&Element{cap: d.child_nodes.len}
	for i in 0 .. d.child_nodes.len {
		els << &(d.get_child(i) as Element)
	}
	return els
}

pub fn (d &Document) get_elements_by_tag_name(qualified_name string) []&Element {
	mut els := []&Element{cap: d.child_nodes.len}
	for i, _ in d.child_nodes {
		c := &(d.get_child(i) as Element)
		if c.get_qualified_name() == qualified_name {
			els << c
		}
	}
	return els
}

pub fn (d &Document) get_elements_by_tag_name_ns(namespace_uri string, local_name string) []&Element {
	mut els := []&Element{cap: d.child_nodes.len}
	for i, _ in d.child_nodes {
		c := &(d.get_child(i) as Element)
		if c.namespace_uri == namespace_uri && c.local_name == local_name {
			els << c
		}
	}
	return els
}

// create_element creates a new element.
[inline]
pub fn (d &Document) create_element(local_name string) &Element {
	// 1. If local_name does not match the name production throw an error

	// 2. if this is an HTML document, then set local_name to lowercase ASCII.
	// (other documents not implemented)
	new_local_name := local_name.to_lower()

	// 3. Let is be null or options["is"] if it exists
	// Not sure what "is" is, so we'll just gloss over this.

	// 4. Let namespace be the HTML namespace if this is an HTML document or
	// this's content type is "application/xhtml+xml", and null otherwise.
	// (other document not implemented)
	namespace_uri := dom.html_namespace

	return &Element{
		local_name: new_local_name
		namespace_uri: namespace_uri
		owner_document: d
	}
}

// create_comment creates a new comment node.
[inline]
pub fn (d &Document) create_comment(data string) &Comment {
	return &Comment{
		data: data
	}
}
