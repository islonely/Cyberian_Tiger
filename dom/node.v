module dom

// TODO:
// - Implement mutation observers
// - fn Node.normalize()
// - fn Node.contains(Node) bool
// - fn Node.lookup_prefix(string) ?string
// - fn Node.lookup_namespace_uri(string) ?string
// - fn Node.is_default_namespace(string) bool
// See: https://github.com/bwrrp/slimdom.js/blob/main/src/Node.ts

struct NullNode {
}

enum DocumentPosition {
	disconnected = 0x1
	preceding = 0x2
	following = 0x4
	contains = 0x8
	contained_by = 0x10
	implementation_specific = 0x20
}

enum NodeType {
	invalid = 0
	element = 1
	attribute = 2
	text = 3
	cdata_section = 4
	entity_reference = 5
	entity = 6
	processing_instruction = 7
	comment = 8
	document = 9
	document_type = 10
	document_fragment = 11
	notation = 12
}

pub type Node = Attribute | Document | Element | Text | NullNode

// Node is like an abstract class and should be used
// as an extension to other structure.
[heap]
struct AbstractNode {
mut:
	owner_document &Document = 0
	parent_node    &Node     = 0
	first_child    &Node     = 0
	last_child     &Node     = 0
	prev_sibling   &Node     = 0
	next_sibling   &Node     = 0
pub mut:
	typ       NodeType = .invalid
	node_name string
	base_uri  string
	child_nodes []&Node
__global:
	node_value   string
	text_content string
}

pub fn (n AbstractNode) str() string {
	mut str := 'AbstractNode{\n\ttyp: $n.typ\n\tnode_name: $n.node_name\n\tbase_uri: $n.base_uri\n\tnode_value: $n.node_value\n\ttext_content: $n.text_content\n\tchildren: ['
	for child in n.child_nodes {
		str += '\n\t\t' + child.str()
	}
	str += '\n\t]\n}\n'
	return str
}

[inline]
pub fn (n &AbstractNode) get_child(i int) &Node {
	return n.child_nodes[i]
}

[inline]
pub fn (mut n AbstractNode) append_child(child &Node) {
	n.child_nodes << child
}

[inline]
pub fn (mut n AbstractNode) prepend_child(child &Node) {
	n.child_nodes.prepend(child)
}

[inline]
pub fn (mut n AbstractNode) insert_before(before &Node, child &Node) {
	n.child_nodes.insert(n.child_nodes.index(&before) - 1, child)
}

[inline]
pub fn (mut n AbstractNode) remove_child(child &Node) {
	n.child_nodes.delete(n.child_nodes.index(child))
}

[inline]
pub fn (mut n AbstractNode) replace_child(replace &Node, child &Node) {
	unsafe {
		n.child_nodes[n.child_nodes.index(replace)] = child
	}
}

// node_type returns the type of node represented as a number
[inline]
pub fn (n &AbstractNode) node_type() int {
	return int(n.typ)
}

// parent_element returns the parent element if one exists.
pub fn (n &AbstractNode) parent_element() ?&Element {
	parent := (ptr_optional(&n.parent_node) or { return err } as Element)
	if parent.typ != .element {
		return error('Parent node is not an element.')
	}

	unsafe {
		return &Element(n.parent_node)
	}
}

[inline]
pub fn (n &AbstractNode) parent_node() ?&Node {
	return ptr_optional(&n.parent_node)
}

[inline]
pub fn (n &AbstractNode) first_child() ?&Node {
	return ptr_optional(&n.first_child)
}

[inline]
pub fn (n &AbstractNode) last_child() ?&Node {
	return ptr_optional(&n.last_child)
}

[inline]
pub fn (n &AbstractNode) prev_sibling() ?&Node {
	return ptr_optional(&n.prev_sibling)
}

[inline]
pub fn (n &AbstractNode) next_sibling() ?&Node {
	return ptr_optional(&n.next_sibling)
}

[inline]
pub fn (n &AbstractNode) has_child_nodes() bool {
	return n.child_nodes.len > 0
}
